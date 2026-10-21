import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/domain/value_objects/financial_cycle.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/features/finance/domain/entities/category.dart';
import 'package:omni_lar/features/finance/domain/entities/house_expense.dart';
import 'package:omni_lar/features/finance/domain/entities/house_member.dart';
import 'package:omni_lar/features/finance/domain/entities/payment_method.dart';
import 'package:omni_lar/features/finance/domain/entities/split_rule.dart';
import 'package:omni_lar/features/finance/domain/services/transaction_aggregator.dart';
import 'package:omni_lar/features/settlement/domain/services/global_clearing_engine.dart';

void main() {
  group('Reconcile Cash Balance - Dual Mode Integration Tests', () {
    final now = DateTime(2026, 10, 15);
    final cycle = FinancialCycle.fromDate(
      date: DateTime(2026, 10, 15),
      cycleStartDay: 5,
    );

    const members = [
      HouseMember(
        id: 'member_kelvynn',
        name: 'Kelvynn',
        defaultSplitPercent: 50.0,
      ),
      HouseMember(
        id: 'member_cristiano',
        name: 'Cristiano',
        defaultSplitPercent: 50.0,
      ),
    ];

    final paymentMethod = PaymentMethod(
      id: 'pm_caixa',
      name: 'Caixa da Casa',
      type: PaymentMethodType.account,
      ownerMemberId: null,
    );

    test('Modo Apenas Caixa (sem_rateio): Despesa de ajuste reduz extrato mas NÃO é cobrada dos moradores no Fechamento', () {
      final adjustmentExpense = HouseExpense(
        id: 'exp_adj_1',
        title: 'Ajuste de Conciliacao de Caixa',
        amount: const Money(20000), // R$ 200,00 de diferença negativa
        date: now,
        categoryId: 'cat_ajuste',
        paidByMemberId: 'member_kelvynn',
        paymentMethodId: 'pm_caixa',
        status: ExpenseStatus.paid,
        splitRule: const SplitRule.percentage({'member_kelvynn': 50.0, 'member_cristiano': 50.0}),
        notes: '[sem_rateio] Conciliacao com saldo bancario',
      );

      // 1. Verifica flag na entidade
      expect(adjustmentExpense.isReconciliationAdjustment, isTrue);

      // 2. Verifica no Extrato (TransactionAggregator): deve estar presente como saída
      final transactions = TransactionAggregator.aggregate(
        expenses: [adjustmentExpense],
        contributions: const [],
        inflows: const [],
        receipts: const [],
        categories: [
          const ExpenseCategory(id: 'cat_ajuste', name: 'Ajustes', icon: 'tune', colorHex: '#000000'),
        ],
        members: members,
        paymentMethods: [paymentMethod],
      );

      final metrics = TransactionAggregator.computeMetrics(transactions);
      expect(transactions.length, equals(1));
      expect(metrics.totalExpenses, equals(const Money(20000)));
      expect(metrics.netBalance, equals(const Money(-20000))); // Extrato deduziu os R$ 200

      // 3. Verifica no Fechamento (GlobalClearingEngine): NENHUM morador deve ser cobrado por essa despesa!
      const engine = GlobalClearingEngine();
      final settlement = engine.computeSettlement(
        cycle: cycle,
        members: members,
        expenses: [adjustmentExpense],
        contributions: const [],
        loans: const [],
      );

      // O total de despesas da casa a serem rateadas entre os moradores deve ser ZERO!
      expect(settlement.totalHouseExpenses, equals(const Money.zero()));
      final kelvynn = settlement.memberBalances.firstWhere((b) => b.memberId == 'member_kelvynn');
      final cristiano = settlement.memberBalances.firstWhere((b) => b.memberId == 'member_cristiano');
      expect(kelvynn.netBalance, equals(const Money.zero()));
      expect(cristiano.netBalance, equals(const Money.zero()));
    });

    test('Modo Ratear no Ciclo: Despesa de ajuste é rateada entre os moradores no Fechamento', () {
      final adjustmentExpense = HouseExpense(
        id: 'exp_adj_2',
        title: 'Ajuste de Conciliacao de Caixa',
        amount: const Money(20000), // R$ 200,00
        date: now,
        categoryId: 'cat_ajuste',
        paidByMemberId: 'member_kelvynn',
        paymentMethodId: 'pm_caixa',
        status: ExpenseStatus.paid,
        splitRule: const SplitRule.percentage({'member_kelvynn': 50.0, 'member_cristiano': 50.0}),
        notes: 'Ajuste rateado com todos', // Sem a tag [sem_rateio]
      );

      expect(adjustmentExpense.isReconciliationAdjustment, isFalse);

      const engine = GlobalClearingEngine();
      final settlement = engine.computeSettlement(
        cycle: cycle,
        members: members,
        expenses: [adjustmentExpense],
        contributions: const [],
        loans: const [],
      );

      // Agora o total é considerado despesa da casa e rateado 50/50 (R$ 100 cada)
      expect(settlement.totalHouseExpenses, equals(const Money(20000)));
      final kelvynn = settlement.memberBalances.firstWhere((b) => b.memberId == 'member_kelvynn');
      final cristiano = settlement.memberBalances.firstWhere((b) => b.memberId == 'member_cristiano');
      expect(kelvynn.contributionDue, equals(const Money(10000)));
      expect(cristiano.contributionDue, equals(const Money(10000)));
    });
  });
}
