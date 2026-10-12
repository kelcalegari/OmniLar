import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/domain/value_objects/financial_cycle.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/features/finance/domain/entities/category.dart';
import 'package:omni_lar/features/finance/domain/entities/contribution.dart';
import 'package:omni_lar/features/finance/domain/entities/cycle_funding_estimate.dart';
import 'package:omni_lar/features/finance/domain/entities/house_expense.dart';
import 'package:omni_lar/features/finance/domain/entities/house_member.dart';
import 'package:omni_lar/features/finance/domain/entities/split_rule.dart';
import 'package:omni_lar/features/finance/domain/services/cycle_funding_estimator.dart';

void main() {
  group('CycleFundingEstimator - Cálculo de Aporte no Início do Ciclo', () {
    const estimator = CycleFundingEstimator();

    final currentCycle = FinancialCycle(
      start: DateTime(2026, 10, 5),
      end: DateTime(2026, 11, 4),
    );

    final members = [
      const HouseMember(
        id: 'm_kelvynn',
        name: 'Kelvynn',
        role: 'owner',
        defaultSplitPercent: 50,
      ),
      const HouseMember(
        id: 'm_cris',
        name: 'Cris',
        role: 'member',
        defaultSplitPercent: 50,
      ),
    ];

    final List<ExpenseCategory> categories = [
      const ExpenseCategory(
        id: 'cat_moradia',
        name: 'Moradia e Contas',
        icon: 'home',
        colorHex: '#4A90E2',
      ),
      const ExpenseCategory(
        id: 'cat_mercado',
        name: 'Supermercado e Feira',
        icon: 'shopping_cart',
        colorHex: '#50E3C2',
      ),
      const ExpenseCategory(
        id: 'cat_energia',
        name: 'Luz e Energia',
        icon: 'bolt',
        colorHex: '#F5A623',
      ),
    ];

    const defaultSplit = SplitRule.percentage({'m_kelvynn': 50, 'm_cris': 50});

    // Despesas a vencer no ciclo atual (ex: Aluguel R$ 2.000 + Internet R$ 120 = R$ 2.120)
    final List<HouseExpense> currentCycleExpenses = [
      HouseExpense(
        id: 'e_aluguel',
        title: 'Aluguel do Lar',
        amount: const Money(200000), // R$ 2.000,00
        date: DateTime(2026, 10, 10),
        paidByMemberId: 'm_kelvynn',
        paidOutOfPocket: false,
        paymentMethodId: 'pm_caixa',
        dueDate: DateTime(2026, 10, 10),
        categoryId: 'cat_moradia',
        splitRule: defaultSplit,
        status: ExpenseStatus.pending,
      ),
      HouseExpense(
        id: 'e_internet',
        title: 'Internet Fibra',
        amount: const Money(12000), // R$ 120,00
        date: DateTime(2026, 10, 25),
        paidByMemberId: 'm_cris',
        paidOutOfPocket: false,
        paymentMethodId: 'pm_caixa',
        dueDate: DateTime(2026, 10, 25),
        categoryId: 'cat_moradia',
        splitRule: defaultSplit,
        status: ExpenseStatus.pending,
      ),
    ];

    // Histórico de mercado dos últimos 2 meses: Mês 1 (R$ 1.400) + Mês 2 (R$ 1.600) -> Média = R$ 1.500
    final List<HouseExpense> historicalExpenses = [
      HouseExpense(
        id: 'h_mercado_1',
        title: 'Supermercado Mensal Ago',
        amount: const Money(140000),
        date: DateTime(2026, 8, 12),
        paidByMemberId: 'm_kelvynn',
        paidOutOfPocket: false,
        paymentMethodId: 'pm_caixa',
        categoryId: 'cat_mercado',
        splitRule: defaultSplit,
        status: ExpenseStatus.paid,
      ),
      HouseExpense(
        id: 'h_mercado_2',
        title: 'Supermercado Mensal Set',
        amount: const Money(160000),
        date: DateTime(2026, 9, 15),
        paidByMemberId: 'm_cris',
        paidOutOfPocket: false,
        paymentMethodId: 'pm_caixa',
        categoryId: 'cat_mercado',
        splitRule: defaultSplit,
        status: ExpenseStatus.paid,
      ),
    ];

    test('Projeção padrão com média histórica de Mercado', () {
      final estimate = estimator.calculateEstimate(
        cycle: currentCycle,
        members: members,
        categories: categories,
        currentCycleExpenses: currentCycleExpenses,
        historicalExpenses: historicalExpenses,
        currentCycleContributions: [],
        currentHouseBalance: const Money.zero(),
        mode: FundingEstimateMode.historicalAverage,
      );

      // 1. Contas fixas: 2000 + 120 = R$ 2.120,00
      expect(estimate.fixedCommittedExpenses.cents, equals(212000));

      // 2. Média histórica de mercado: (1400 + 1600) / 2 = R$ 1.500,00
      final mercadoEstimate = estimate.variableCategoryEstimates.firstWhere(
        (e) => e.categoryId == 'cat_mercado',
      );
      expect(mercadoEstimate.averageMonthlyAmount.cents, equals(150000));
      expect(mercadoEstimate.adjustedAmount.cents, equals(150000));

      // 3. Total projetado: 2.120 + 1.500 = R$ 3.620,00
      expect(estimate.totalProjectedExpenses.cents, equals(362000));
      expect(estimate.netFundingRequired.cents, equals(362000));

      // 4. Cotas recomendadas (50/50): R$ 1.810,00 para cada
      expect(estimate.memberQuotes.length, equals(2));
      final qKelvynn = estimate.memberQuotes.firstWhere(
        (q) => q.memberId == 'm_kelvynn',
      );
      final qCris = estimate.memberQuotes.firstWhere(
        (q) => q.memberId == 'm_cris',
      );

      expect(qKelvynn.recommendedAmount.cents, equals(181000));
      expect(qCris.recommendedAmount.cents, equals(181000));
      expect(qKelvynn.pendingAmount.cents, equals(181000));
    });

    test(
      'Modo Econômico (-10% no mercado) e Modo Confortável (+10% no mercado)',
      () {
        final economicEstimate = estimator.calculateEstimate(
          cycle: currentCycle,
          members: members,
          categories: categories,
          currentCycleExpenses: currentCycleExpenses,
          historicalExpenses: historicalExpenses,
          currentCycleContributions: [],
          mode: FundingEstimateMode.economical,
        );

        // Mercado: R$ 1.500 * 0.90 = R$ 1.350,00
        final ecoMercado = economicEstimate.variableCategoryEstimates
            .firstWhere((e) => e.categoryId == 'cat_mercado');
        expect(ecoMercado.adjustedAmount.cents, equals(135000));
        // Total: 2120 + 1350 = R$ 3.470,00
        expect(economicEstimate.totalProjectedExpenses.cents, equals(347000));

        final comfortableEstimate = estimator.calculateEstimate(
          cycle: currentCycle,
          members: members,
          categories: categories,
          currentCycleExpenses: currentCycleExpenses,
          historicalExpenses: historicalExpenses,
          currentCycleContributions: [],
          mode: FundingEstimateMode.comfortable,
        );

        // Mercado: R$ 1.500 * 1.10 = R$ 1.650,00
        final comfMercado = comfortableEstimate.variableCategoryEstimates
            .firstWhere((e) => e.categoryId == 'cat_mercado');
        expect(comfMercado.adjustedAmount.cents, equals(165000));
        // Total: 2120 + 1650 = R$ 3.770,00
        expect(
          comfortableEstimate.totalProjectedExpenses.cents,
          equals(377000),
        );
      },
    );

    test(
      'Abate sobra de caixa do ciclo anterior e desconta aportes já feitos',
      () {
        // Sobra de R$ 300 em caixa
        // Kelvynn já aportou R$ 500
        final estimate = estimator.calculateEstimate(
          cycle: currentCycle,
          members: members,
          categories: categories,
          currentCycleExpenses: currentCycleExpenses,
          historicalExpenses: historicalExpenses,
          currentHouseBalance: const Money(30000), // R$ 300,00
          currentCycleContributions: [
            Contribution(
              id: 'c_kelvynn',
              memberId: 'm_kelvynn',
              amount: const Money(50000), // R$ 500,00
              date: DateTime(2026, 10, 6),
            ),
          ],
        );

        // Total projetado: 3.620 - 300 (sobra) = R$ 3.320,00 necessários
        expect(estimate.netFundingRequired.cents, equals(332000));

        // Cota de cada um: R$ 1.660,00
        final qKelvynn = estimate.memberQuotes.firstWhere(
          (q) => q.memberId == 'm_kelvynn',
        );
        expect(qKelvynn.recommendedAmount.cents, equals(166000));
        expect(qKelvynn.alreadyContributed.cents, equals(50000));
        // Falta aportar: 1.660 - 500 = R$ 1.160,00
        expect(qKelvynn.pendingAmount.cents, equals(116000));
      },
    );

    test('Permite override customizado pelo usuário para Mercado', () {
      final estimate = estimator.calculateEstimate(
        cycle: currentCycle,
        members: members,
        categories: categories,
        currentCycleExpenses: currentCycleExpenses,
        historicalExpenses: historicalExpenses,
        currentCycleContributions: [],
        customCategoryOverrides: {
          'cat_mercado': const Money(
            120000,
          ), // Casal decidiu fixar em R$ 1.200,00
        },
      );

      final mercadoEstimate = estimate.variableCategoryEstimates.firstWhere(
        (e) => e.categoryId == 'cat_mercado',
      );
      expect(mercadoEstimate.adjustedAmount.cents, equals(120000));
      expect(mercadoEstimate.isOverridden, isTrue);
      // Total: 2.120 + 1.200 = R$ 3.320,00
      expect(estimate.totalProjectedExpenses.cents, equals(332000));
    });
  });
}
