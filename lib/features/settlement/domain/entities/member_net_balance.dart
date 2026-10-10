import '../../../../core/domain/value_objects/money.dart';

class MemberNetBalance {
  final String memberId;
  final String memberName;
  final Money contributionDue;
  final Money contributionPaid;
  final Money outOfPocketExpenses; // Crédito que a Casa deve ao membro
  final Money p2pLentDue; // Total de parcelas P2P que outros devem a ele no ciclo
  final Money p2pBorrowedDue; // Total de parcelas P2P que ele deve a outros no ciclo

  const MemberNetBalance({
    required this.memberId,
    required this.memberName,
    required this.contributionDue,
    required this.contributionPaid,
    required this.outOfPocketExpenses,
    required this.p2pLentDue,
    required this.p2pBorrowedDue,
  });

  /// Aporte ainda pendente de pagamento para a Casa
  Money get pendingContribution {
    final diff = contributionDue.cents - contributionPaid.cents;
    return diff > 0 ? Money(diff) : const Money.zero();
  }

  /// Saldo líquido do membro para o fechamento:
  /// Positivo (+) = Credor líquido (tem a receber)
  /// Negativo (-) = Devedor líquido (tem a pagar)
  ///
  /// Fórmula:
  /// Despesas da Casa pagas do bolso próprio (reembolso a receber)
  /// - Aporte pendente a pagar para a Casa
  /// + Empréstimos P2P a receber de outros membros
  /// - Empréstimos P2P a pagar para outros membros
  Money get netBalance {
    final houseNet = outOfPocketExpenses.cents - pendingContribution.cents;
    final p2pNet = p2pLentDue.cents - p2pBorrowedDue.cents;
    return Money(houseNet + p2pNet);
  }

  bool get isDebtor => netBalance.cents < 0;
  bool get isCreditor => netBalance.cents > 0;
  bool get isSettled => netBalance.cents == 0;
}
