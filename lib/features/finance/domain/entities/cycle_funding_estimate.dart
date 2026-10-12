import '../../../../core/domain/value_objects/money.dart';
import '../../../../core/domain/value_objects/financial_cycle.dart';

enum FundingEstimateMode {
  economical, // -10% sobre médias de variáveis (modo de economia)
  historicalAverage, // 100% da média histórica calculada
  comfortable, // +10% sobre médias de variáveis (com folga para imprevistos)
}

/// Estimativa de gastos projetados para uma categoria variável específica (ex: Mercado, Luz, etc.)
class CategoryFundingEstimate {
  final String categoryId;
  final String categoryName;
  final Money averageMonthlyAmount;
  final Money
  adjustedAmount; // Com base no modo (economical, average, comfortable) ou override
  final int sampleCyclesCount;
  final bool isOverridden;

  const CategoryFundingEstimate({
    required this.categoryId,
    required this.categoryName,
    required this.averageMonthlyAmount,
    required this.adjustedAmount,
    this.sampleCyclesCount = 1,
    this.isOverridden = false,
  });
}

/// Cota de aporte recomendada para cada membro no início do ciclo
class MemberFundingQuote {
  final String memberId;
  final String memberName;
  final Money recommendedAmount;
  final Money alreadyContributed;
  final Money pendingAmount;
  final String ruleDescription;

  const MemberFundingQuote({
    required this.memberId,
    required this.memberName,
    required this.recommendedAmount,
    required this.alreadyContributed,
    required this.pendingAmount,
    required this.ruleDescription,
  });

  bool get isFulfilled => pendingAmount.isZero;
}

/// Projeção completa de aportes necessários no início do ciclo financeiro
class CycleFundingEstimate {
  final FinancialCycle cycle;
  final FundingEstimateMode mode;
  final Money fixedCommittedExpenses; // Contas a vencer/fixas do ciclo
  final List<CategoryFundingEstimate>
  variableCategoryEstimates; // Mercado, etc.
  final Money currentHouseBalance; // Saldo em caixa do ciclo anterior
  final Money totalProjectedExpenses; // Fixas + Estimativas variáveis
  final Money netFundingRequired; // max(0, totalProjected - currentBalance)
  final List<MemberFundingQuote> memberQuotes;

  const CycleFundingEstimate({
    required this.cycle,
    required this.mode,
    required this.fixedCommittedExpenses,
    required this.variableCategoryEstimates,
    required this.currentHouseBalance,
    required this.totalProjectedExpenses,
    required this.netFundingRequired,
    required this.memberQuotes,
  });

  Money get totalVariablesEstimated => variableCategoryEstimates.fold(
    const Money.zero(),
    (total, e) => total + e.adjustedAmount,
  );
}
