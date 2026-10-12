import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/domain/value_objects/financial_cycle.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/features/finance/domain/entities/cycle_funding_estimate.dart';
import 'package:omni_lar/features/finance/presentation/widgets/cycle_funding_planner_card.dart';

void main() {
  final testCycle = FinancialCycle(
    start: DateTime(2026, 10, 5),
    end: DateTime(2026, 11, 4),
  );

  final testEstimate = CycleFundingEstimate(
    cycle: testCycle,
    mode: FundingEstimateMode.historicalAverage,
    fixedCommittedExpenses: const Money(120000), // R$ 1.200,00
    variableCategoryEstimates: const [
      CategoryFundingEstimate(
        categoryId: 'cat_mercado',
        categoryName: 'Supermercado',
        averageMonthlyAmount: Money(80000),
        adjustedAmount: Money(80000),
        sampleCyclesCount: 3,
      ),
    ],
    currentHouseBalance: const Money(50000), // R$ 500,00
    totalProjectedExpenses: const Money(200000), // R$ 2.000,00
    netFundingRequired: const Money(150000), // R$ 1.500,00
    memberQuotes: const [
      MemberFundingQuote(
        memberId: 'u1',
        memberName: 'Alice',
        recommendedAmount: Money(75000), // R$ 750,00
        alreadyContributed: Money(30000), // R$ 300,00
        pendingAmount: Money(45000), // R$ 450,00
        ruleDescription: '50% (Renda)',
      ),
      MemberFundingQuote(
        memberId: 'u2',
        memberName: 'Bob',
        recommendedAmount: Money(75000), // R$ 750,00
        alreadyContributed: Money(75000), // R$ 750,00
        pendingAmount: Money.zero(),
        ruleDescription: '50% (Renda)',
      ),
    ],
  );

  testWidgets(
    'CycleFundingPlannerCard exibe valores projetados e cota dos membros',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: CycleFundingPlannerCard(estimate: testEstimate),
            ),
          ),
        ),
      );

      expect(find.text('Planejamento de Aportes'), findsOneWidget);
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('100% Aportado'), findsOneWidget);
      expect(find.text('Aportar'), findsOneWidget);

      // Abre o BottomSheet de memória de cálculo
      final detailsButton = find.byIcon(Icons.tune_rounded);
      expect(detailsButton, findsOneWidget);
      await tester.tap(detailsButton);
      await tester.pumpAndSettle();

      expect(find.text('Memória do Planejamento'), findsOneWidget);
      expect(find.text('Supermercado'), findsOneWidget);
      expect(find.text('Contas Fixas / Provisionadas'), findsOneWidget);
    },
  );
}
