import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/domain/value_objects/financial_cycle.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/features/finance/data/settled_contribution_dues.dart';
import 'package:omni_lar/features/finance/domain/entities/house_expense.dart';
import 'package:omni_lar/features/finance/domain/entities/house_member.dart';
import 'package:omni_lar/features/finance/domain/entities/split_rule.dart';
import 'package:omni_lar/features/finance/domain/services/cycle_funding_estimator.dart';

void main() {
  group('Cotas do fechamento lidas do retrato', () {
    Map<String, dynamic> row(String status) => {
          'status': status,
          'summary_snapshot': {
            'v': 1,
            'member_balances': [
              {'member_id': 'a', 'contribution_due_cents': 282450},
              {'member_id': 'b', 'contribution_due_cents': 84761},
            ],
          },
        };

    test('ciclo fechado devolve a cota de cada morador', () {
      expect(settledContributionDuesFromRow(row('confirmed')), {
        'a': const Money(282450),
        'b': const Money(84761),
      });
      expect(settledContributionDuesFromRow(row('completed')), isNotNull);
    });

    test('ciclo reaberto, sem fechamento ou sem retrato segue calculando', () {
      expect(settledContributionDuesFromRow(row('draft')), isNull);
      expect(settledContributionDuesFromRow(null), isNull);
      expect(
        settledContributionDuesFromRow({'status': 'confirmed', 'summary_snapshot': null}),
        isNull,
      );
    });
  });

  group('Planejador de um ciclo já fechado', () {
    const estimator = CycleFundingEstimator();
    final cycle = FinancialCycle(start: DateTime(2026, 10, 7), end: DateTime(2026, 11, 6));
    final expense = HouseExpense(
      id: 'e1',
      title: 'Aluguel',
      paymentMethodId: 'pm_caixa',
      amount: const Money(100000),
      date: DateTime(2026, 10, 10),
      categoryId: 'cat_moradia',
      paidByMemberId: 'a',
      splitRule: const SplitRule.percentage({}),
    );

    List<HouseMember> members(double a, double b) => [
          HouseMember(id: 'a', name: 'A', role: 'owner', defaultSplitPercent: a),
          HouseMember(id: 'b', name: 'B', role: 'member', defaultSplitPercent: b),
        ];

    test('mudar o rateio depois do fechamento não muda as cotas', () {
      const settled = {'a': Money(60000), 'b': Money(40000)};
      for (final split in [(60.0, 40.0), (50.0, 50.0), (30.0, 70.0)]) {
        final estimate = estimator.calculateEstimate(
          cycle: cycle,
          members: members(split.$1, split.$2),
          categories: const [],
          currentCycleExpenses: [expense],
          historicalExpenses: const [],
          currentCycleContributions: const [],
          settledQuotas: settled,
        );
        expect(estimate.isSettled, isTrue);
        final byId = {for (final q in estimate.memberQuotes) q.memberId: q};
        expect(byId['a']!.recommendedAmount, const Money(60000));
        expect(byId['b']!.recommendedAmount, const Money(40000));
        expect(byId.values.every((q) => q.isFulfilled), isTrue);
      }
    });

    test('ciclo aberto continua seguindo o rateio atual', () {
      final estimate = estimator.calculateEstimate(
        cycle: cycle,
        members: members(30, 70),
        categories: const [],
        currentCycleExpenses: [expense],
        historicalExpenses: const [],
        currentCycleContributions: const [],
      );
      expect(estimate.isSettled, isFalse);
      final byId = {for (final q in estimate.memberQuotes) q.memberId: q};
      expect(byId['a']!.recommendedAmount, const Money(30000));
      expect(byId['b']!.recommendedAmount, const Money(70000));
    });
  });
}
