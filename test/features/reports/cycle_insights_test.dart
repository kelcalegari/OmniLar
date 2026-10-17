import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/domain/value_objects/cycle_schedule.dart';
import 'package:omni_lar/core/domain/value_objects/financial_cycle.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/features/finance/domain/entities/house_expense.dart';
import 'package:omni_lar/features/finance/domain/entities/house_member.dart';
import 'package:omni_lar/features/finance/domain/entities/payment_method.dart';
import 'package:omni_lar/features/finance/domain/entities/split_rule.dart';
import 'package:omni_lar/features/finance/domain/repositories/finance_repository.dart';
import 'package:omni_lar/features/finance/presentation/cubit/finance_state.dart';
import 'package:omni_lar/features/p2p/domain/entities/p2p_installment.dart';
import 'package:omni_lar/features/p2p/domain/entities/p2p_loan.dart';
import 'package:omni_lar/features/reports/domain/services/cycle_insights_builder.dart';
import 'package:omni_lar/features/reports/presentation/cubit/reports_cubit.dart';
import 'package:omni_lar/features/settlement/domain/entities/settlement_options.dart';
import 'package:omni_lar/features/settlement/domain/entities/settlement_summary.dart';
import 'package:omni_lar/features/settlement/domain/repositories/settlement_repository.dart';

const members = [
  HouseMember(id: 'm_ana', name: 'Ana', role: 'owner', defaultSplitPercent: 50),
  HouseMember(
    id: 'm_bia',
    name: 'Bia',
    role: 'member',
    defaultSplitPercent: 50,
  ),
];
const anaCard = PaymentMethod(
  id: 'pm_card_ana',
  name: 'Nubank Ana',
  type: PaymentMethodType.card,
  ownerMemberId: 'm_ana',
  closingDay: 28,
  dueDay: 5,
);
const account = PaymentMethod(
  id: 'pm_conta',
  name: 'Conta da Casa',
  type: PaymentMethodType.account,
);
const methods = [anaCard, account];

HouseExpense expense(
  String id,
  int cents, {
  String method = 'pm_conta',
  String category = 'cat_casa',
  bool recurring = false,
  ExpenseStatus status = ExpenseStatus.paid,
  DateTime? dueDate,
}) => HouseExpense(
  id: id,
  title: id,
  amount: Money(cents),
  date: DateTime(2026, 10, 12),
  dueDate: dueDate,
  categoryId: category,
  paidByMemberId: 'm_ana',
  paymentMethodId: method,
  splitRule: const SplitRule.percentage({'m_ana': 50, 'm_bia': 50}),
  status: status,
  isRecurring: recurring,
);

class _FakeSettlementRepository implements SettlementRepository {
  @override
  Future<void> markTransferSent(String recordId) async {}

  @override
  Future<SettlementSummary> getSettlementSummary(
    FinancialCycle cycle, {
    SettlementOptions? options,
  }) async => SettlementSummary(
    cycle: cycle,
    memberBalances: const [],
    transfers: const [],
    totalHouseExpenses: const Money.zero(),
    totalContributions: const Money.zero(),
    totalP2PCleared: const Money.zero(),
    houseTreasuryBalance: const Money.zero(),
  );

  @override
  Future<void> confirmSettlement(
    SettlementSummary summary, {
    SettlementOptions? options,
  }) async {}

  @override
  Future<void> reopenSettlement(FinancialCycle cycle) async {}

  @override
  Future<bool> isCycleSettled(FinancialCycle cycle) async => false;
}

/// Só a leitura de despesas por ciclo: R$ 10 vezes o mês do início do ciclo.
class _FakeFinanceRepository implements FinanceRepository {
  final reads = <FinancialCycle>[];

  @override
  Future<List<HouseExpense>> getExpensesForCycle(FinancialCycle cycle) async {
    reads.add(cycle);
    return [expense('c${cycle.startDate.month}', cycle.startDate.month * 1000)];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final today = DateTime(2026, 10, 20);

  group('Leitura do ciclo', () {
    test('compara cada categoria com o ciclo anterior', () {
      final insights = const CycleInsightsBuilder().build(
        expenses: [
          expense('mercado', 12000, category: 'cat_mercado'),
          expense('luz', 5000, category: 'cat_luz'),
        ],
        previousExpenses: [
          expense('mercado_ant', 10000, category: 'cat_mercado'),
        ],
        members: members,
        paymentMethods: methods,
        loans: const [],
        today: today,
      );
      expect(insights.previousTotal.cents, 10000);
      expect(insights.changeOf('cat_mercado', 12000), closeTo(20, 0.001));
      // Sem gasto no ciclo anterior não há porcentagem
      expect(insights.changeOf('cat_luz', 5000), isNull);
    });

    test('sem o ciclo anterior não compara', () {
      final insights = const CycleInsightsBuilder().build(
        expenses: [expense('mercado', 12000)],
        members: members,
        paymentMethods: methods,
        loans: const [],
        today: today,
      );
      expect(insights.hasPrevious, isFalse);
      expect(insights.changeOf('cat_casa', 12000), isNull);
    });

    test('quem paga: fatura em aberto pelo titular, o resto pelo Caixa', () {
      final insights = const CycleInsightsBuilder().build(
        expenses: [
          expense(
            'compra',
            40000,
            method: anaCard.id,
            status: ExpenseStatus.pending,
            dueDate: DateTime(2026, 11, 5),
          ),
          expense('aluguel', 150000, recurring: true),
        ],
        members: members,
        paymentMethods: methods,
        loans: const [],
        today: today,
      );
      final byPayer = {
        for (final p in insights.byPayer) p.memberId: p.amount.cents,
      };
      expect(byPayer, {null: 150000, 'm_ana': 40000});
      expect(insights.byMethod.first.name, 'Conta da Casa');
      expect(insights.recurring.cents, 150000);
      expect(insights.oneOff.cents, 40000);
    });

    test('posição nos empréstimos, com as parcelas vencidas de quem deve', () {
      final loan = P2PLoan(
        id: 'l',
        title: 'Empréstimo',
        totalAmount: const Money(10000),
        lenderMemberId: 'm_ana',
        borrowerMemberId: 'm_bia',
        installmentsCount: 2,
        createdAt: DateTime(2026, 9, 1),
        firstDueDate: DateTime(2026, 10, 1),
        installments: [
          P2PInstallment(
            id: 'l1',
            loanId: 'l',
            number: 1,
            totalCount: 2,
            amount: const Money(5000),
            paidAmount: const Money(2000),
            dueDate: DateTime(2026, 10, 1),
          ),
          P2PInstallment(
            id: 'l2',
            loanId: 'l',
            number: 2,
            totalCount: 2,
            amount: const Money(5000),
            dueDate: DateTime(2026, 11, 1),
          ),
        ],
      );
      final insights = const CycleInsightsBuilder().build(
        expenses: const [],
        members: members,
        paymentMethods: methods,
        loans: [loan],
        today: today,
      );
      final ana = insights.loanPositions.singleWhere(
        (p) => p.memberId == 'm_ana',
      );
      final bia = insights.loanPositions.singleWhere(
        (p) => p.memberId == 'm_bia',
      );
      expect(ana.toReceive.cents, 8000);
      expect(bia.toPay.cents, 8000);
      expect(bia.alreadyPaid.cents, 2000);
      expect(bia.overdueInstallments, 1);
    });
  });

  group('Cubit', () {
    const schedule = CycleSchedule(10);
    final cycle = schedule.cycleFor(today);
    final finance = FinanceState(
      currentCycle: cycle,
      members: members,
      expenses: [expense('atual', 99000)],
      paymentMethods: methods,
    );

    test('a prévia lê o ciclo anterior para comparar', () async {
      final repo = _FakeFinanceRepository();
      final cubit = ReportsCubit(
        _FakeSettlementRepository(),
        financeRepository: repo,
        now: () => today,
      );
      await cubit.loadPreview(finance, schedule: schedule);
      expect(repo.reads, [schedule.previous(cycle)]);
      expect(cubit.state.insights!.hasPrevious, isTrue);
      expect(cubit.state.insights!.previousTotal.cents, 9000);
    });

    test(
      'evolução: seis ciclos até o mostrado, sem reler o ciclo mostrado',
      () async {
        final repo = _FakeFinanceRepository();
        final cubit = ReportsCubit(
          _FakeSettlementRepository(),
          financeRepository: repo,
          now: () => today,
        );
        await cubit.loadEvolution(finance, schedule);

        final evolution = cubit.state.evolution!;
        expect(evolution, hasLength(6));
        expect(evolution.last.cycle, cycle);
        expect(evolution.last.total.cents, 99000);
        expect(evolution.first.cycle.startDate, DateTime(2026, 5, 10));
        expect(repo.reads, hasLength(5));
        expect(cubit.evolutionRequested, isTrue);
      },
    );
  });
}
