import 'package:equatable/equatable.dart';
import '../../../../core/domain/value_objects/money.dart';
import '../../../../core/domain/value_objects/financial_cycle.dart';
import 'folego_params.dart';
import 'opening_inflows.dart';

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

  /// Resgates de caixinha devolvidos ao Caixa deste ciclo (já somados ao
  /// fôlego). Cobrem falta de caixa: não abatem o que cada morador deve aportar.
  final Money vaultReturns;

  /// Empréstimos que o Caixa liberou neste ciclo (já descontados do fôlego).
  final Money houseLoansFunded;

  /// O dinheiro do início do ciclo separado por origem (sobra, empréstimos
  /// pagos de volta, resgates por caixinha). Nulo quando não se sabe.
  final OpeningInflows? openingInflows;

  const FinancialCycleSummary({
    required this.cycle,
    required this.totalContributions,
    required this.totalExpensesPaid,
    required this.committedFutureExpenses,
    required this.folego,
    required this.memberContributions,
    required this.memberExpensesPaid,
    this.vaultReturns = const Money.zero(),
    this.houseLoansFunded = const Money.zero(),
    this.openingInflows,
  });

  /// Alias para despesas pagas no ciclo
  Money get totalSpent => totalExpensesPaid;

  /// Alias para aportes realizados no ciclo
  Money get totalContributed => totalContributions;

  /// Sobra que o ciclo anterior deixou no Caixa (nunca negativa). O fôlego já
  /// desconta as contas e soma os aportes do ciclo, então não serve sozinho.
  Money get openingBalance {
    final cents = folego.cents +
        totalExpensesPaid.cents +
        committedFutureExpenses.cents +
        houseLoansFunded.cents -
        totalContributions.cents;
    return Money(cents > 0 ? cents : 0);
  }

  /// Sobra do ciclo anterior sem o que voltou das caixinhas: o que pode abater
  /// os aportes do ciclo.
  Money get rolledOverBalance {
    final cents = openingBalance.cents - vaultReturns.cents;
    return Money(cents > 0 ? cents : 0);
  }

  /// Status de saúde do fôlego
  FolegoStatus get status => statusWith(const FolegoParams());

  /// Status com os limites da casa (padrão: atenção abaixo de 15% dos aportes).
  FolegoStatus statusWith(FolegoParams params) {
    if (folego.isNegative) return FolegoStatus.danger;
    if (folego.cents * 100 < totalContributions.cents * params.warningPercent) {
      return FolegoStatus.warning;
    }
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
        vaultReturns,
        houseLoansFunded,
        openingInflows,
      ];
}
