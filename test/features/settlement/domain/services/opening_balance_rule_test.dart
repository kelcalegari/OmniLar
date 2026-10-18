import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/domain/value_objects/financial_cycle.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/features/finance/domain/entities/category.dart';
import 'package:omni_lar/features/finance/domain/entities/cycle_funding_estimate.dart';
import 'package:omni_lar/features/finance/domain/entities/house_expense.dart';
import 'package:omni_lar/features/finance/domain/entities/house_member.dart';
import 'package:omni_lar/features/finance/domain/entities/house_settings.dart';
import 'package:omni_lar/features/finance/domain/entities/split_rule.dart';
import 'package:omni_lar/features/finance/domain/services/cycle_funding_estimator.dart';
import 'package:omni_lar/features/settlement/domain/entities/settlement_summary.dart';
import 'package:omni_lar/features/settlement/domain/services/global_clearing_engine.dart';

void main() {
  const engine = GlobalClearingEngine();
  const estimator = CycleFundingEstimator();
  final cycle = FinancialCycle.fromDate(date: DateTime(2026, 10, 12), cycleStartDay: 7);

  HouseExpense expense(String id, int cents, {String category = 'c', DateTime? date}) => HouseExpense(
        id: id,
        title: 'Conta $id',
        amount: Money(cents),
        date: date ?? DateTime(2026, 10, 12),
        categoryId: category,
        paidByMemberId: 'ana',
        paymentMethodId: 'pm_caixa',
        splitRule: const SplitRule.percentage(null),
      );

  int due(SettlementSummary s, String id) =>
      s.memberBalances.firstWhere((b) => b.memberId == id).contributionDue.cents;

  group('Fechamento com divisão por despesa (R\$ 3.000, sobra de R\$ 300, 50/50)', () {
    const members = [
      HouseMember(id: 'ana', name: 'Ana', defaultSplitPercent: 50),
      HouseMember(id: 'bia', name: 'Bia', defaultSplitPercent: 50),
    ];

    SettlementSummary compute(OpeningBalanceRule? rule, {int vaultReturns = 0}) => engine.computeSettlement(
          cycle: cycle,
          members: members,
          expenses: [expense('e1', 300000)],
          contributions: const [],
          loans: const [],
          openingBalance: Money(30000 + vaultReturns),
          vaultReturns: Money(vaultReturns),
          openingBalanceRule: rule,
        );

    test('Sem escolha da casa, cobra a parte inteira (como antes)', () {
      final s = compute(null);
      expect(due(s, 'ana'), 150000);
      expect(due(s, 'bia'), 150000);
    });

    test('Abater os aportes: cada um deve R\$ 1.350', () {
      final s = compute(OpeningBalanceRule.reduceQuotas);
      expect(due(s, 'ana'), 135000);
      expect(due(s, 'bia'), 135000);
      final audit = s.auditTrails['ana']!.expenseShares.where((e) => e.expenseId == 'opening_balance');
      expect(audit.single.allocatedAmount.cents, -15000);
    });

    test('Guardar como folga: cada um deve R\$ 1.500', () {
      final s = compute(OpeningBalanceRule.keep);
      expect(due(s, 'ana'), 150000);
      expect(due(s, 'bia'), 150000);
    });

    test('O que voltou das caixinhas não abate os aportes', () {
      final s = compute(OpeningBalanceRule.reduceQuotas, vaultReturns: 20000);
      expect(due(s, 'ana'), 135000);
      expect(due(s, 'bia'), 135000);
    });

    test('Sobra maior que as contas não deixa aporte negativo', () {
      final s = engine.computeSettlement(
        cycle: cycle,
        members: members,
        expenses: [expense('e1', 10000)],
        contributions: const [],
        loans: const [],
        openingBalance: const Money(30000),
        openingBalanceRule: OpeningBalanceRule.reduceQuotas,
      );
      expect(due(s, 'ana'), 0);
      expect(due(s, 'bia'), 0);
    });
  });

  group('Fechamento com valor fixo (balde de R\$ 2.000: Ana 1.200, Bia 800)', () {
    const members = [
      HouseMember(id: 'ana', name: 'Ana', defaultFixedAmountCents: 120000),
      HouseMember(id: 'bia', name: 'Bia', defaultFixedAmountCents: 80000),
    ];
    final targets = {for (final m in members) m.id: Money(m.defaultFixedAmountCents!)};

    SettlementSummary compute(OpeningBalanceRule? rule, int expenseCents) => engine.computeSettlement(
          cycle: cycle,
          members: members,
          expenses: [expense('e1', expenseCents)],
          contributions: const [],
          loans: const [],
          customContributionTargets: targets,
          openingBalance: const Money(30000),
          openingBalanceRule: rule,
        );

    test('Cobrir só o excedente (padrão): a sobra paga o que passou do balde', () {
      for (final rule in [null, OpeningBalanceRule.coverExcess]) {
        final s = compute(rule, 210000);
        expect(due(s, 'ana'), 120000);
        expect(due(s, 'bia'), 80000);
      }
    });

    test('Guardar como folga: o excedente é rateado mesmo com sobra', () {
      final s = compute(OpeningBalanceRule.keep, 210000);
      expect(due(s, 'ana'), 120000 + 6000);
      expect(due(s, 'bia'), 80000 + 4000);
    });

    test('Abater os aportes: o resto da sobra reduz o valor fixo na proporção', () {
      // Excedente de R$ 100 coberto pela sobra; os R$ 200 restantes abatem 60/40
      final s = compute(OpeningBalanceRule.reduceQuotas, 210000);
      expect(due(s, 'ana'), 120000 - 12000);
      expect(due(s, 'bia'), 80000 - 8000);
    });
  });

  group('Planejador de aportes', () {
    const members = [
      HouseMember(id: 'ana', name: 'Ana', defaultSplitPercent: 50),
      HouseMember(id: 'bia', name: 'Bia', defaultSplitPercent: 50),
    ];
    const mercado = ExpenseCategory(id: 'mercado', name: 'Mercado', icon: 'cart', colorHex: '#000000');

    int quote(CycleFundingEstimate e, String id) =>
        e.memberQuotes.firstWhere((q) => q.memberId == id).recommendedAmount.cents;

    CycleFundingEstimate estimate({
      OpeningBalanceRule? rule,
      List<List<HouseExpense>>? byCycle,
      FundingEstimateMode mode = FundingEstimateMode.historicalAverage,
      int adjustPercent = 10,
    }) =>
        estimator.calculateEstimate(
          cycle: cycle,
          members: members,
          categories: const [mercado],
          currentCycleExpenses: [expense('e1', 300000)],
          historicalExpenses: const [],
          historicalExpensesByCycle: byCycle ?? const [],
          currentCycleContributions: const [],
          currentHouseBalance: const Money(30000),
          openingBalanceRule: rule,
          mode: mode,
          adjustPercent: adjustPercent,
        );

    test('A cota segue a mesma regra do fechamento', () {
      expect(quote(estimate(), 'ana'), 135000);
      expect(quote(estimate(rule: OpeningBalanceRule.reduceQuotas), 'ana'), 135000);
      expect(quote(estimate(rule: OpeningBalanceRule.keep), 'ana'), 150000);
      expect(estimate(rule: OpeningBalanceRule.keep).netFundingRequired.cents, 300000);
    });

    test('Média dos ciclos em que houve gasto, como o alerta de categoria', () {
      final e = estimate(byCycle: [
        [expense('h1', 60000, category: 'mercado')],
        const [],
        [expense('h2', 40000, category: 'mercado')],
      ]);
      final cat = e.variableCategoryEstimates.single;
      expect(cat.sampleCyclesCount, 2);
      expect(cat.averageMonthlyAmount.cents, 50000);
    });

    test('Percentual dos modos vem da casa', () {
      final e = estimate(
        byCycle: [
          [expense('h1', 50000, category: 'mercado')],
        ],
        mode: FundingEstimateMode.comfortable,
        adjustPercent: 20,
      );
      expect(e.variableCategoryEstimates.single.adjustedAmount.cents, 60000);
    });
  });

  group('HouseSettings', () {
    test('Lê as colunas da casa e cai nos padrões com valor estranho', () {
      final s = HouseSettings.fromJson({
        'opening_balance_rule': 'reduce_quotas',
        'planner_history_cycles': 6,
        'planner_mode': 'comfortable',
        'planner_adjust_percent': 99,
        'planner_category_overrides': {'mercado': 80000},
      });
      expect(s.openingBalanceRule, OpeningBalanceRule.reduceQuotas);
      expect(s.historyCycles, 6);
      expect(s.plannerMode, FundingEstimateMode.comfortable);
      expect(s.adjustPercent, HouseSettings.defaultAdjustPercent);
      expect(s.categoryOverrides['mercado']!.cents, 80000);
      expect(HouseSettings.fromJson(null), const HouseSettings());
    });
  });
}
