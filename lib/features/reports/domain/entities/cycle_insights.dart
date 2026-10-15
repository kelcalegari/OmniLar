import '../../../../core/domain/value_objects/financial_cycle.dart';
import '../../../../core/domain/value_objects/money.dart';

/// Quanto um morador (ou o Caixa da Casa, com [memberId] null) paga das
/// despesas do ciclo.
class PayerShare {
  final String? memberId;
  final String name;
  final Money amount;

  const PayerShare({
    required this.memberId,
    required this.name,
    required this.amount,
  });
}

/// Total do ciclo em uma forma de pagamento.
class MethodShare {
  final String paymentMethodId;
  final String name;
  final Money amount;

  const MethodShare({
    required this.paymentMethodId,
    required this.name,
    required this.amount,
  });
}

/// Posição de um morador nos empréstimos em aberto.
class LoanPosition {
  final String memberId;
  final String name;
  final Money toReceive;
  final Money toPay;

  /// O que ele já pagou dos empréstimos em que deve.
  final Money alreadyPaid;

  /// Parcelas vencidas e não pagas em que ele é quem deve.
  final int overdueInstallments;

  const LoanPosition({
    required this.memberId,
    required this.name,
    required this.toReceive,
    required this.toPay,
    required this.alreadyPaid,
    required this.overdueInstallments,
  });

  bool get isEmpty => toReceive.isZero && toPay.isZero && alreadyPaid.isZero;
}

/// Leitura do ciclo além dos totais: comparação com o ciclo anterior, quem
/// paga o quê e a posição dos empréstimos.
class CycleInsights {
  /// Total por categoria no ciclo anterior (id da categoria -> centavos).
  final Map<String, int> previousByCategory;

  /// O ciclo anterior foi lido (sem ele não há comparação).
  final bool hasPrevious;
  final Money previousTotal;

  final List<PayerShare> byPayer;
  final List<MethodShare> byMethod;

  /// Contas recorrentes e despesas avulsas do ciclo.
  final Money recurring;
  final Money oneOff;

  final List<LoanPosition> loanPositions;

  const CycleInsights({
    this.previousByCategory = const {},
    this.hasPrevious = false,
    this.previousTotal = const Money.zero(),
    this.byPayer = const [],
    this.byMethod = const [],
    this.recurring = const Money.zero(),
    this.oneOff = const Money.zero(),
    this.loanPositions = const [],
  });

  /// Variação de uma categoria em relação ao ciclo anterior, em %. Null quando
  /// não há com o que comparar.
  double? changeOf(String categoryId, int currentCents) {
    if (!hasPrevious) return null;
    final previous = previousByCategory[categoryId] ?? 0;
    if (previous <= 0) return null;
    return (currentCents - previous) * 100 / previous;
  }
}

/// Total de um ciclo, para a evolução.
class CycleTotal {
  final FinancialCycle cycle;
  final Money total;

  /// Total por categoria (id -> centavos).
  final Map<String, int> byCategory;

  const CycleTotal({
    required this.cycle,
    required this.total,
    this.byCategory = const {},
  });
}
