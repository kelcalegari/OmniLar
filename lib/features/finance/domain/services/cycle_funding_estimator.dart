import '../../../../core/domain/value_objects/money.dart';
import '../../../../core/domain/value_objects/financial_cycle.dart';
import '../entities/category.dart';
import '../entities/contribution.dart';
import '../entities/cycle_funding_estimate.dart';
import '../entities/house_expense.dart';
import '../entities/house_member.dart';
import '../entities/split_rule.dart';

/// Motor determinístico de cálculo de aportes recomendados no início do ciclo financeiro.
class CycleFundingEstimator {
  const CycleFundingEstimator();

  /// Calcula a projeção de gastos do ciclo e as cotas de aporte recomendadas por morador.
  CycleFundingEstimate calculateEstimate({
    required FinancialCycle cycle,
    required List<HouseMember> members,
    required List<ExpenseCategory> categories,
    required List<HouseExpense> currentCycleExpenses,
    required List<HouseExpense> historicalExpenses,
    required List<Contribution> currentCycleContributions,
    Money currentHouseBalance = const Money.zero(),
    FundingEstimateMode mode = FundingEstimateMode.historicalAverage,
    Map<String, Money>? customCategoryOverrides,
  }) {
    // 1. Contas provisionadas a vencer no ciclo atual (excluindo despesas já pagas ou despesas de projetos)
    final houseExpenses = currentCycleExpenses
        .where((e) => !e.isProjectExpense)
        .toList();
    final committedCents = houseExpenses
        .where((e) => e.isPending || !e.isPaid)
        .fold<int>(0, (acc, e) => acc + e.amount.cents);
    final fixedCommittedExpenses = Money(committedCents);

    // 2. Estimativa de categorias variáveis (Mercado, Luz, etc.)
    final variableCategoryEstimates = _computeVariableCategoryEstimates(
      categories: categories,
      historicalExpenses: historicalExpenses,
      mode: mode,
      customOverrides: customCategoryOverrides,
    );

    final totalVariablesCents = variableCategoryEstimates.fold<int>(
      0,
      (acc, v) => acc + v.adjustedAmount.cents,
    );

    // 3. Total projetado para o ciclo
    final totalProjectedCents =
        fixedCommittedExpenses.cents + totalVariablesCents;
    final totalProjectedExpenses = Money(totalProjectedCents);

    // 4. Necessidade líquida de novos aportes (abatendo sobra em caixa existente)
    final netFundingCents = (totalProjectedCents - currentHouseBalance.cents)
        .clamp(0, totalProjectedCents);
    final netFundingRequired = Money(netFundingCents);

    // 5. Repartição das cotas recomendadas entre os membros
    final memberQuotes = _calculateMemberQuotes(
      members: members,
      netFundingRequired: netFundingRequired,
      contributions: currentCycleContributions,
    );

    return CycleFundingEstimate(
      cycle: cycle,
      mode: mode,
      fixedCommittedExpenses: fixedCommittedExpenses,
      variableCategoryEstimates: variableCategoryEstimates,
      currentHouseBalance: currentHouseBalance,
      totalProjectedExpenses: totalProjectedExpenses,
      netFundingRequired: netFundingRequired,
      memberQuotes: memberQuotes,
    );
  }

  /// Calcula estimativas históricas para categorias variáveis (como Mercado e Contas de Consumo)
  List<CategoryFundingEstimate> _computeVariableCategoryEstimates({
    required List<ExpenseCategory> categories,
    required List<HouseExpense> historicalExpenses,
    required FundingEstimateMode mode,
    Map<String, Money>? customOverrides,
  }) {
    final List<CategoryFundingEstimate> estimates = [];

    // Prioriza categorias de consumo variável mais comuns no orçamento familiar
    final isVariableCategory = (ExpenseCategory cat) {
      final n = cat.name.toLowerCase();
      final id = cat.id.toLowerCase();
      return n.contains('mercado') ||
          n.contains('alimenta') ||
          n.contains('feira') ||
          n.contains('supermercado') ||
          n.contains('luz') ||
          n.contains('energia') ||
          n.contains('água') ||
          n.contains('agua') ||
          n.contains('gás') ||
          n.contains('gas') ||
          id.contains('mercado');
    };

    final variableCategories = categories.where(isVariableCategory).toList();

    // Se nenhuma categoria tiver nome padrão de mercado, analisa as categorias que tiveram histórico
    final targetCategories = variableCategories.isNotEmpty
        ? variableCategories
        : categories.take(3).toList();

    final multiplier = switch (mode) {
      FundingEstimateMode.economical => 0.90, // -10% de economia
      FundingEstimateMode.historicalAverage => 1.00, // 100% da média
      FundingEstimateMode.comfortable => 1.10, // +10% de folga
    };

    for (final cat in targetCategories) {
      final catExpenses = historicalExpenses
          .where((e) => e.categoryId == cat.id)
          .toList();

      int averageCents = 0;
      int cyclesCount = 1;

      if (catExpenses.isNotEmpty) {
        // Encontra quantos ciclos distintos aparecem no histórico
        final months = catExpenses
            .map((e) => '${e.date.year}-${e.date.month}')
            .toSet();
        cyclesCount = months.isNotEmpty ? months.length : 1;
        final totalHistoricalCents = catExpenses.fold<int>(
          0,
          (acc, e) => acc + e.amount.cents,
        );
        averageCents = (totalHistoricalCents / cyclesCount).round();
      }

      final averageAmount = Money(averageCents);

      // Aplica override manual se fornecido, ou aplica multiplicador do modo
      final Money adjustedAmount;
      final bool isOverridden;

      if (customOverrides != null && customOverrides.containsKey(cat.id)) {
        adjustedAmount = customOverrides[cat.id]!;
        isOverridden = true;
      } else {
        adjustedAmount = Money((averageCents * multiplier).round());
        isOverridden = false;
      }

      estimates.add(
        CategoryFundingEstimate(
          categoryId: cat.id,
          categoryName: cat.name,
          averageMonthlyAmount: averageAmount,
          adjustedAmount: adjustedAmount,
          sampleCyclesCount: cyclesCount,
          isOverridden: isOverridden,
        ),
      );
    }

    return estimates;
  }

  /// Calcula a cota sugerida para cada membro com base no modelo de rateio configurado
  List<MemberFundingQuote> _calculateMemberQuotes({
    required List<HouseMember> members,
    required Money netFundingRequired,
    required List<Contribution> contributions,
  }) {
    if (members.isEmpty) return const [];

    final memberIds = members.map((m) => m.id).toList();
    final defaultPercentages = <String, double>{
      for (final m in members) m.id: m.defaultSplitPercent,
    };

    final hasFixedAmount = members.any(
      (m) => (m.defaultFixedAmountCents ?? 0) > 0,
    );

    final Map<String, Money> recommendedMap = {};
    final Map<String, String> ruleDescMap = {};

    if (hasFixedAmount) {
      for (final m in members) {
        final fixedCents = m.defaultFixedAmountCents ?? 0;
        recommendedMap[m.id] = Money(fixedCents);
        ruleDescMap[m.id] = 'Valor fixo definido no perfil';
      }
    } else {
      // Divisão proporcional por maior resto sem perda de centavos
      final splitRule = SplitRule.percentage(defaultPercentages);
      final allocations = splitRule.calculateAllocations(
        totalAmount: netFundingRequired,
        memberIds: memberIds,
      );

      for (final entry in allocations.entries) {
        recommendedMap[entry.key] = entry.value;
        final pct = defaultPercentages[entry.key] ?? 50.0;
        final pctFormatted = pct.truncateToDouble() == pct
            ? pct.toInt().toString()
            : pct.toStringAsFixed(1);
        ruleDescMap[entry.key] = '$pctFormatted% da meta do ciclo';
      }
    }

    return members.map((member) {
      final recommended = recommendedMap[member.id] ?? const Money.zero();
      final alreadyContributedCents = contributions
          .where((c) => c.memberId == member.id)
          .fold<int>(0, (acc, c) => acc + c.amount.cents);
      final alreadyContributed = Money(alreadyContributedCents);

      final pendingCents = (recommended.cents - alreadyContributedCents).clamp(
        0,
        recommended.cents,
      );
      final pendingAmount = Money(pendingCents);

      return MemberFundingQuote(
        memberId: member.id,
        memberName: member.name,
        recommendedAmount: recommended,
        alreadyContributed: alreadyContributed,
        pendingAmount: pendingAmount,
        ruleDescription: ruleDescMap[member.id] ?? 'Cota do ciclo',
      );
    }).toList();
  }
}
