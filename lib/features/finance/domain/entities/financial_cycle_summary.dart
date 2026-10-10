import 'package:equatable/equatable.dart';
import '../../../../core/domain/value_objects/money.dart';
import '../../../../core/domain/value_objects/financial_cycle.dart';

enum FolegoStatus {
  positive, // Saudável (Verde)
  warning, // Atenção (Amarelo/Laranja)
  danger, // Crítico / Negativo (Vermelho)
}

class FinancialCycleSummary extends Equatable {
  final FinancialCycle cycle;
  final Money totalContributions; // Total que entrou no caixa da casa
  final Money totalExpensesPaid; // Despesas já pagas no ciclo
  final Money committedFutureExpenses; // Contas a vencer antes do fim do ciclo
  final Money folego; // Saldo livre do caixa = totalContributions - (totalExpensesPaid + committedFutureExpenses)
  final Map<String, Money> memberContributions; // memberId -> total aportado
  final Map<String, Money> memberExpensesPaid; // memberId -> total que o membro pagou do bolso

  const FinancialCycleSummary({
    required this.cycle,
    required this.totalContributions,
    required this.totalExpensesPaid,
    required this.committedFutureExpenses,
    required this.folego,
    required this.memberContributions,
    required this.memberExpensesPaid,
  });

  /// Alias para despesas pagas no ciclo
  Money get totalSpent => totalExpensesPaid;

  /// Alias para aportes realizados no ciclo
  Money get totalContributed => totalContributions;

  /// Status de saúde do fôlego
  FolegoStatus get status {
    if (folego.isNegative) return FolegoStatus.danger;
    if (folego.cents < (totalContributions.cents * 0.15)) return FolegoStatus.warning;
    return FolegoStatus.positive;
  }

  /// Porcentagem de comprometimento do orçamento do ciclo
  double get commitmentPercentage {
    if (totalContributions.isZero) return 0.0;
    final committed = totalExpensesPaid + committedFutureExpenses;
    return (committed.cents / totalContributions.cents).clamp(0.0, 1.0);
  }

  @override
  List<Object?> get props => [
        cycle,
        totalContributions,
        totalExpensesPaid,
        committedFutureExpenses,
        folego,
        memberContributions,
        memberExpensesPaid,
      ];
}
