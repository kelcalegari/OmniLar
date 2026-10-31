import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/domain/value_objects/financial_cycle.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/features/finance/domain/entities/contribution.dart';
import 'package:omni_lar/features/finance/domain/entities/house_expense.dart';
import 'package:omni_lar/features/finance/domain/entities/house_member.dart';
import 'package:omni_lar/features/finance/domain/entities/payment_method.dart';
import 'package:omni_lar/features/finance/domain/entities/split_rule.dart';
import 'package:omni_lar/features/settlement/data/settlement_summary_codec.dart';
import 'package:omni_lar/features/settlement/domain/services/global_clearing_engine.dart';

/// Despesa paga com saldo próprio (VA marcado como "não consome aportes",
/// 0122): conta como despesa da casa, mas não consome o aporte de ninguém.
void main() {
  const engine = GlobalClearingEngine();
  final cycle = FinancialCycle(start: DateTime(2026, 10, 5), end: DateTime(2026, 11, 4));
  const members = [
    HouseMember(id: 'k', name: 'Kelvynn', role: 'owner', defaultSplitPercent: 50),
    HouseMember(id: 'c', name: 'Cris', role: 'member', defaultSplitPercent: 50),
  ];
  const vaSelfFunded = PaymentMethod(
    id: 'pm_va',
    name: 'VA Kelvynn',
    type: PaymentMethodType.va,
    ownerMemberId: 'k',
    consumesContributions: false,
  );
  const vaCommon = PaymentMethod(
    id: 'pm_va',
    name: 'VA Kelvynn',
    type: PaymentMethodType.va,
    ownerMemberId: 'k',
  );
  const caixa = PaymentMethod(id: 'pm_caixa', name: 'Caixa', type: PaymentMethodType.account);

  HouseExpense expense(String id, int cents, String methodId, {bool outOfPocket = false}) => HouseExpense(
        id: id,
        title: id,
        amount: Money(cents),
        date: DateTime(2026, 10, 10),
        paidByMemberId: 'k',
        paidOutOfPocket: outOfPocket,
        dueDate: DateTime(2026, 10, 10),
        categoryId: 'cat_mercado',
        paymentMethodId: methodId,
        splitRule: const SplitRule.percentage({'k': 50, 'c': 50}),
      );

  final expenses = [
    expense('luz', 20000, 'pm_caixa'),
    expense('mercado_va', 60000, 'pm_va', outOfPocket: true),
  ];

  test('VA comum: entra no rateio e o dono é reembolsado (como sempre)', () {
    final summary = engine.computeSettlement(
      cycle: cycle,
      members: members,
      expenses: expenses,
      contributions: const [],
      loans: const [],
      paymentMethods: const [vaCommon, caixa],
    );
    final k = summary.memberBalances.firstWhere((m) => m.memberId == 'k');
    expect(summary.totalHouseExpenses.cents, 80000);
    expect(summary.selfFundedExpenses.cents, 0);
    expect(k.contributionDue.cents, 40000);
    expect(k.outOfPocketExpenses.cents, 60000);
  });

  test('VA que não consome aportes: conta no total, fora do rateio e do reembolso', () {
    final contributions = [
      Contribution(id: 'a1', memberId: 'k', amount: const Money(10000), date: DateTime(2026, 10, 6)),
      Contribution(id: 'a2', memberId: 'c', amount: const Money(10000), date: DateTime(2026, 10, 6)),
    ];
    final summary = engine.computeSettlement(
      cycle: cycle,
      members: members,
      expenses: expenses,
      contributions: contributions,
      loans: const [],
      paymentMethods: const [vaSelfFunded, caixa],
    );
    final k = summary.memberBalances.firstWhere((m) => m.memberId == 'k');
    final c = summary.memberBalances.firstWhere((m) => m.memberId == 'c');

    // Despesa da casa: luz + VA
    expect(summary.totalHouseExpenses.cents, 80000);
    expect(summary.selfFundedExpenses.cents, 60000);
    expect(summary.totalSharedHouseExpenses.cents, 20000);
    // Só a luz é rateada; o VA não gera reembolso
    expect(k.contributionDue.cents, 10000);
    expect(c.contributionDue.cents, 10000);
    expect(k.outOfPocketExpenses.cents, 0);
    // O Caixa paga só a luz, coberta pelos aportes
    expect(summary.houseTreasuryBalance.cents, 0);
    expect(summary.isNetZeroSum, isTrue);
  });

  test('Aporte fixo: o VA não estoura o balde', () {
    final summary = engine.computeSettlement(
      cycle: cycle,
      members: members,
      expenses: expenses,
      contributions: const [],
      loans: const [],
      paymentMethods: const [vaSelfFunded, caixa],
      customContributionTargets: const {'k': Money(15000), 'c': Money(15000)},
    );
    expect(summary.bucketDeficit.cents, 0);
    expect(summary.memberBalances.firstWhere((m) => m.memberId == 'k').contributionDue.cents, 15000);
    // Sobra do balde: 300 de aportes - 200 de luz
    expect(summary.houseTreasuryBalance.cents, 10000);
  });

  test('O retrato do fechamento guarda o que foi pago com saldo próprio', () {
    final summary = engine.computeSettlement(
      cycle: cycle,
      members: members,
      expenses: expenses,
      contributions: const [],
      loans: const [],
      paymentMethods: const [vaSelfFunded, caixa],
    );
    final restored = settlementSummaryFromJson(
      settlementSummaryToJson(summary),
      cycle: cycle,
      settledAt: DateTime(2026, 11, 5),
    );
    expect(restored?.selfFundedExpenses.cents, 60000);
  });
}
