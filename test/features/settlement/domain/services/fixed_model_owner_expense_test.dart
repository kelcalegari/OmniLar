import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/domain/value_objects/financial_cycle.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/features/finance/domain/entities/house_expense.dart';
import 'package:omni_lar/features/finance/domain/entities/house_member.dart';
import 'package:omni_lar/features/finance/domain/entities/split_rule.dart';
import 'package:omni_lar/features/settlement/domain/services/global_clearing_engine.dart';

void main() {
  group('Aportes fixos e despesa de categoria com dono', () {
    const engine = GlobalClearingEngine();
    final cycle = FinancialCycle.fromDate(date: DateTime(2026, 10, 12), cycleStartDay: 9);
    const members = [
      HouseMember(id: 'ana', name: 'Ana', defaultFixedAmountCents: 100000),
      HouseMember(id: 'bia', name: 'Bia', defaultFixedAmountCents: 100000),
    ];
    final targets = {for (final m in members) m.id: Money(m.defaultFixedAmountCents!)};

    HouseExpense expense(String id, int cents, SplitRule rule) => HouseExpense(
          id: id,
          title: id,
          amount: Money(cents),
          date: DateTime(2026, 10, 12),
          categoryId: 'c',
          paidByMemberId: 'ana',
          paymentMethodId: 'pm_caixa',
          splitRule: rule,
        );

    test('a despesa do dono é cobrada dele por cima do aporte fixo e não consome o balde', () {
      final summary = engine.computeSettlement(
        cycle: cycle,
        members: members,
        expenses: [
          expense('contas', 150000, const SplitRule.percentage(null)),
          expense('carro da bia', 30000, const SplitRule.singleResponsible('bia')),
        ],
        contributions: const [],
        loans: const [],
        customContributionTargets: targets,
      );

      final ana = summary.memberBalances.firstWhere((b) => b.memberId == 'ana');
      final bia = summary.memberBalances.firstWhere((b) => b.memberId == 'bia');
      expect(ana.contributionDue.cents, 100000);
      expect(bia.contributionDue.cents, 100000 + 30000);
      // O balde (R$ 2.000) cobre as contas compartilhadas (R$ 1.500): sem excedente
      expect(summary.bucketDeficit.cents, 0);
      // Sobra do Caixa: balde menos as contas compartilhadas
      expect(summary.houseTreasuryBalance.cents, 50000);
      expect(summary.auditTrails['bia']!.personalItemsSharesTotal.cents, 30000);
    });

    test('sem a despesa do dono o balde e a sobra não mudam', () {
      final summary = engine.computeSettlement(
        cycle: cycle,
        members: members,
        expenses: [expense('contas', 150000, const SplitRule.percentage(null))],
        contributions: const [],
        loans: const [],
        customContributionTargets: targets,
      );

      expect(summary.memberBalances.every((b) => b.contributionDue.cents == 100000), isTrue);
      expect(summary.houseTreasuryBalance.cents, 50000);
    });
  });
}
