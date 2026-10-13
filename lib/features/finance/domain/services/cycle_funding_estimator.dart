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
    // A conta é a do ciclo inteiro, como no fechamento: tudo o que o ciclo custa
    // (o que já foi pago e o que ainda vence), menos a sobra que veio do ciclo
    // anterior. O que cada um já aportou só é abatido da cota dele, no fim.
    final houseExpenses = currentCycleExpenses
        .where((e) => !e.isProjectExpense)
        .toList();

    // 1. Estimativa das categorias variáveis (Mercado, Luz, etc.). O que já foi
    // lançado nelas neste ciclo conta dentro da estimativa, não por cima dela.
    final historicalEstimates = _computeVariableCategoryEstimates(
      categories: categories,
      historicalExpenses: historicalExpenses,
      mode: mode,
      customOverrides: customCategoryOverrides,
    );
    final variableCategoryIds = historicalEstimates.map((v) => v.categoryId).toSet();
    final launchedByCategory = <String, int>{};
    for (final e in houseExpenses) {
      if (variableCategoryIds.contains(e.categoryId) && !_isFixedBill(e)) {
        launchedByCategory[e.categoryId] =
            (launchedByCategory[e.categoryId] ?? 0) + e.amount.cents;
      }
    }
    int variableRemainderCents = 0;
    final variableCategoryEstimates = <CategoryFundingEstimate>[];
    for (final v in historicalEstimates) {
      final launched = launchedByCategory[v.categoryId] ?? 0;
      final projected = launched > v.adjustedAmount.cents ? launched : v.adjustedAmount.cents;
      variableRemainderCents += projected - launched;
      variableCategoryEstimates.add(
        CategoryFundingEstimate(
          categoryId: v.categoryId,
          categoryName: v.categoryName,
          averageMonthlyAmount: v.averageMonthlyAmount,
          adjustedAmount: Money(projected),
          sampleCyclesCount: v.sampleCyclesCount,
          isOverridden: v.isOverridden,
        ),
      );
    }

    // 2. Contas do ciclo fora das categorias variáveis (pagas e a vencer)
    final fixedCommittedExpenses = Money(
      houseExpenses
          .where((e) => !variableCategoryIds.contains(e.categoryId) || _isFixedBill(e))
          .fold<int>(0, (acc, e) => acc + e.amount.cents),
    );

    // 3. Total projetado para o ciclo
    final totalVariablesCents = variableCategoryEstimates.fold<int>(
      0,
      (acc, v) => acc + v.adjustedAmount.cents,
    );
    final totalProjectedCents =
        fixedCommittedExpenses.cents + totalVariablesCents;
    final totalProjectedExpenses = Money(totalProjectedCents);

    // 4. Necessidade de aportes no ciclo (abatendo a sobra do ciclo anterior)
    final netFundingCents = (totalProjectedCents - currentHouseBalance.cents)
        .clamp(0, totalProjectedCents);
    final netFundingRequired = Money(netFundingCents);

    // 5. Repartição das cotas recomendadas entre os membros
    final memberQuotes = _calculateMemberQuotes(
      members: members,
      houseExpenses: houseExpenses,
      variableRemainder: Money(variableRemainderCents),
      openingBalance: currentHouseBalance,
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

  /// Conta recorrente de valor fixo (internet, condomínio): é conta fixa mesmo
  /// quando a categoria dela é de consumo variável.
  bool _isFixedBill(HouseExpense e) => e.isRecurring && !e.isVariable;

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
          .where((e) => e.categoryId == cat.id && !_isFixedBill(e))
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
    required List<HouseExpense> houseExpenses,
    required Money variableRemainder,
    required Money openingBalance,
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
      // Cada despesa lançada entra pelo rateio dela (como no fechamento); o que
      // ainda é só estimativa e a sobra do ciclo anterior, pelo percentual padrão.
      final defaultRule = SplitRule.percentage(defaultPercentages);
      final grossCents = <String, int>{for (final id in memberIds) id: 0};
      void add(Map<String, Money> allocations) {
        for (final entry in allocations.entries) {
          grossCents[entry.key] = (grossCents[entry.key] ?? 0) + entry.value.cents;
        }
      }

      SplitRule effective(SplitRule rule) =>
          rule.type == SplitType.percentage &&
              (rule.percentages == null || rule.percentages!.isEmpty)
          ? defaultRule
          : rule;

      for (final expense in houseExpenses) {
        if (expense.items.isEmpty) {
          add(effective(expense.splitRule).calculateAllocations(
            totalAmount: expense.amount,
            memberIds: memberIds,
          ));
          continue;
        }
        for (final item in expense.items) {
          final itemRule = item.splitRule ??
              (item.responsibleMemberId != null
                  ? SplitRule.singleResponsible(item.responsibleMemberId)
                  : effective(expense.splitRule));
          add(itemRule.calculateAllocations(
            totalAmount: item.amount,
            memberIds: memberIds,
          ));
        }
      }
      add(defaultRule.calculateAllocations(
        totalAmount: variableRemainder,
        memberIds: memberIds,
      ));
      final openingShares = defaultRule.calculateAllocations(
        totalAmount: openingBalance.isPositive ? openingBalance : const Money.zero(),
        memberIds: memberIds,
      );

      for (final id in memberIds) {
        final cents = (grossCents[id] ?? 0) - (openingShares[id]?.cents ?? 0);
        recommendedMap[id] = Money(cents > 0 ? cents : 0);
      }

      for (final entry in recommendedMap.entries.toList()) {
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

      // Conta da casa paga do próprio bolso vale como aporte: o fechamento
      // reembolsa esse valor abatendo do que o morador deve.
      final outOfPocketCents = houseExpenses
          .where(
            (e) =>
                e.paidByMemberId == member.id &&
                e.isPaid &&
                e.paidOutOfPocket &&
                e.settledAt == null &&
                e.paymentMethodId != 'pm_caixa',
          )
          .fold<int>(0, (acc, e) => acc + e.amount.cents);

      final pendingCents =
          (recommended.cents - alreadyContributedCents - outOfPocketCents).clamp(
        0,
        recommended.cents,
      );
      final pendingAmount = Money(pendingCents);

      return MemberFundingQuote(
        memberId: member.id,
        memberName: member.name,
        recommendedAmount: recommended,
        alreadyContributed: alreadyContributed,
        paidOutOfPocket: Money(outOfPocketCents),
        pendingAmount: pendingAmount,
        ruleDescription: ruleDescMap[member.id] ?? 'Cota do ciclo',
      );
    }).toList();
  }
}
