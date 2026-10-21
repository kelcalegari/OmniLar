import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/domain/value_objects/cycle_schedule.dart';
import 'package:omni_lar/core/domain/value_objects/financial_cycle.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/features/finance/domain/entities/category.dart';
import 'package:omni_lar/features/finance/domain/entities/contribution.dart';
import 'package:omni_lar/features/finance/domain/entities/house_expense.dart';
import 'package:omni_lar/features/finance/domain/entities/house_inflow.dart';
import 'package:omni_lar/features/finance/domain/entities/house_member.dart';
import 'package:omni_lar/features/finance/domain/entities/house_transaction.dart';
import 'package:omni_lar/features/finance/domain/entities/payment_method.dart';
import 'package:omni_lar/features/finance/domain/entities/split_rule.dart';
import 'package:omni_lar/features/finance/domain/entities/third_party_receipt.dart';
import 'package:omni_lar/features/finance/domain/repositories/finance_repository.dart';
import 'package:omni_lar/features/finance/domain/value_objects/transaction_filter.dart';
import 'package:omni_lar/features/finance/presentation/cubit/transactions_cubit.dart';
import 'package:omni_lar/features/finance/presentation/cubit/transactions_state.dart';

class FakeFinanceRepository implements FinanceRepository {
  List<HouseExpense> expenses = [];
  List<Contribution> contributions = [];
  List<HouseInflow> inflows = [];
  List<ThirdPartyReceipt> receipts = [];

  List<ExpenseCategory> categories = [
    const ExpenseCategory(id: 'cat_mercado', name: 'Mercado', icon: 'cart', colorHex: '#4CAF50'),
  ];
  List<HouseMember> members = [
    const HouseMember(id: 'mem_1', name: 'Kelvyn'),
  ];
  List<PaymentMethod> paymentMethods = [
    const PaymentMethod(id: 'pm_card', name: 'Cartão C6', type: PaymentMethodType.card),
  ];

  @override
  Future<List<ExpenseCategory>> getCategories() async => categories;

  @override
  Future<List<HouseMember>> getMembers() async => members;

  @override
  Future<List<PaymentMethod>> getPaymentMethods() async => paymentMethods;

  @override
  Future<List<HouseExpense>> getExpensesForCycle(FinancialCycle cycle) async => expenses;

  @override
  Future<List<Contribution>> getContributionsForCycle(FinancialCycle cycle) async => contributions;

  @override
  Future<List<HouseInflow>> getHouseInflowsForCycle(FinancialCycle cycle) async => inflows;

  @override
  Future<List<ThirdPartyReceipt>> getThirdPartyReceipts() async => receipts;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('TransactionsCubit', () {
    late FakeFinanceRepository repository;
    late CycleSchedule cycleSchedule;
    late TransactionsCubit cubit;

    final testCycle = FinancialCycle(
      start: DateTime(2026, 10, 1),
      end: DateTime(2026, 10, 31),
    );

    setUp(() {
      repository = FakeFinanceRepository();
      cycleSchedule = const CycleSchedule(1);
      cubit = TransactionsCubit(
        repository: repository,
        cycleSchedule: cycleSchedule,
      );
    });

    tearDown(() {
      cubit.close();
    });

    test('initial state has TransactionsStatus.initial', () {
      expect(cubit.state.status, TransactionsStatus.initial);
      expect(cubit.state.allTransactions, isEmpty);
      expect(cubit.state.filteredTransactions, isEmpty);
    });

    test('initialize loads categories, members, payment methods and fetches cycle transactions', () async {
      repository.expenses = [
        HouseExpense(
          id: 'exp_1',
          title: 'Supermercado',
          amount: const Money(12000), // R$ 120,00
          date: DateTime(2026, 10, 5),
          categoryId: 'cat_mercado',
          paidByMemberId: 'mem_1',
          paymentMethodId: 'pm_card',
          splitRule: const SplitRule.percentage({'mem_1': 100}),
        ),
      ];
      repository.contributions = [
        Contribution(
          id: 'cb_1',
          memberId: 'mem_1',
          amount: const Money(30000), // R$ 300,00
          date: DateTime(2026, 10, 6),
        ),
      ];

      await cubit.initialize(initialCycle: testCycle);

      expect(cubit.state.status, TransactionsStatus.success);
      expect(cubit.state.availableCycles, isNotEmpty);
      expect(cubit.state.availableCycles.first, testCycle);
      expect(cubit.state.allTransactions.length, 2);
      expect(cubit.state.filteredTransactions.length, 2);
      expect(cubit.state.metrics.totalExpenses.cents, 12000);
      expect(cubit.state.metrics.totalInflows.cents, 30000);
      expect(cubit.state.metrics.netBalance.cents, 18000);
    });

    test('in-memory filters update filteredTransactions and metrics without remote refetch', () async {
      repository.expenses = [
        HouseExpense(
          id: 'exp_1',
          title: 'Supermercado',
          amount: const Money(12000),
          date: DateTime(2026, 10, 5),
          categoryId: 'cat_mercado',
          paidByMemberId: 'mem_1',
          paymentMethodId: 'pm_card',
          splitRule: const SplitRule.percentage({'mem_1': 100}),
        ),
      ];
      repository.contributions = [
        Contribution(
          id: 'cb_1',
          memberId: 'mem_1',
          amount: const Money(30000),
          date: DateTime(2026, 10, 6),
        ),
      ];

      await cubit.initialize(initialCycle: testCycle);

      // Filter to expenses only
      cubit.setTypeFilter(TransactionType.expense);
      expect(cubit.state.filteredTransactions.length, 1);
      expect(cubit.state.filteredTransactions.first.id, 'exp_exp_1');
      expect(cubit.state.metrics.totalExpenses.cents, 12000);
      expect(cubit.state.metrics.totalInflows.cents, 0);

      // Instant search filter
      cubit.setTypeFilter(null);
      cubit.setSearchQuery('mercado');
      expect(cubit.state.filteredTransactions.length, 1);
      expect(cubit.state.filteredTransactions.first.title, 'Supermercado');
    });

    test('setDateRange switches periodMode and triggers aggregation', () async {
      repository.expenses = [
        HouseExpense(
          id: 'exp_old',
          title: 'Compra Antiga',
          amount: const Money(5000),
          date: DateTime(2026, 8, 15),
          categoryId: 'cat_mercado',
          paidByMemberId: 'mem_1',
          paymentMethodId: 'pm_card',
          splitRule: const SplitRule.percentage({'mem_1': 100}),
        ),
      ];

      await cubit.setDateRange(
        startDate: DateTime(2026, 8, 1),
        endDate: DateTime(2026, 8, 31),
        preset: DateRangePreset.custom,
      );

      expect(cubit.state.filter.periodMode, PeriodMode.dateRange);
      expect(cubit.state.filter.datePreset, DateRangePreset.custom);
      expect(cubit.state.status, TransactionsStatus.success);
      expect(cubit.state.allTransactions.length, 1);
    });
  });
}
