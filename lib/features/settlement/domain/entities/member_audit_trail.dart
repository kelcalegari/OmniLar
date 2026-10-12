import '../../../../core/domain/value_objects/money.dart';

/// Registro de participação em uma despesa da casa no fechamento do ciclo.
class ExpenseShareAudit {
  final String expenseId;
  final String expenseTitle;
  final Money totalExpenseAmount;
  final Money allocatedAmount;
  final String ruleDescription;
  final DateTime date;
  final bool isPersonal;

  const ExpenseShareAudit({
    required this.expenseId,
    required this.expenseTitle,
    required this.totalExpenseAmount,
    required this.allocatedAmount,
    required this.ruleDescription,
    required this.date,
    this.isPersonal = false,
  });
}

/// Registro de despesa da casa paga com dinheiro ou cartão pessoal do membro.
class OutOfPocketAudit {
  final String expenseId;
  final String title;
  final Money amount;
  final DateTime date;
  final String? paymentMethod;

  const OutOfPocketAudit({
    required this.expenseId,
    required this.title,
    required this.amount,
    required this.date,
    this.paymentMethod,
  });
}

/// Registro de aporte já realizado pelo membro durante o ciclo.
class ContributionAudit {
  final String contributionId;
  final Money amount;
  final DateTime date;
  final String? paymentMethodId;

  const ContributionAudit({
    required this.contributionId,
    required this.amount,
    required this.date,
    this.paymentMethodId,
  });
}

/// Registro de parcela de empréstimo P2P que venceu e foi computada no ciclo.
class P2PInstallmentAudit {
  final String loanId;
  final String description;
  final String otherMemberId;
  final String otherMemberName;
  final int installmentNumber;
  final int totalInstallments;
  final Money amount;
  final DateTime dueDate;
  final bool
  isReceivable; // true = tem a receber (credor), false = tem a pagar (devedor)

  const P2PInstallmentAudit({
    required this.loanId,
    required this.description,
    required this.otherMemberId,
    required this.otherMemberName,
    required this.installmentNumber,
    required this.totalInstallments,
    required this.amount,
    required this.dueDate,
    required this.isReceivable,
  });
}

/// Memória de cálculo completa e auditável para um membro no fechamento do ciclo.
class MemberAuditTrail {
  final String memberId;
  final String memberName;
  final List<ExpenseShareAudit> expenseShares;
  final List<ContributionAudit> contributionsMade;
  final List<OutOfPocketAudit> outOfPocketExpenses;
  final List<P2PInstallmentAudit> p2pReceivables;
  final List<P2PInstallmentAudit> p2pPayables;
  final Money contributionDue;
  final Money contributionPaid;
  final Money outOfPocketTotal;
  final Money p2pLentTotal;
  final Money p2pBorrowedTotal;
  final Money netBalance;

  const MemberAuditTrail({
    required this.memberId,
    required this.memberName,
    required this.expenseShares,
    required this.contributionsMade,
    required this.outOfPocketExpenses,
    required this.p2pReceivables,
    required this.p2pPayables,
    required this.contributionDue,
    required this.contributionPaid,
    required this.outOfPocketTotal,
    required this.p2pLentTotal,
    required this.p2pBorrowedTotal,
    required this.netBalance,
  });

  /// Total de participação em gastos comuns/compartilhados da Casa
  Money get sharedHouseSharesTotal {
    int cents = 0;
    for (final s in expenseShares.where((s) => !s.isPersonal)) {
      cents += s.allocatedAmount.cents;
    }
    return Money(cents);
  }

  /// Total de itens pessoais exclusivos embutidos em contas da Casa
  Money get personalItemsSharesTotal {
    int cents = 0;
    for (final s in expenseShares.where((s) => s.isPersonal)) {
      cents += s.allocatedAmount.cents;
    }
    return Money(cents);
  }

  /// Aporte pendente a pagar para a Casa
  Money get pendingContribution {
    final diff = contributionDue.cents - contributionPaid.cents;
    return diff > 0 ? Money(diff) : const Money.zero();
  }

  /// Total de créditos (+ a receber)
  Money get totalCredits {
    return Money(outOfPocketTotal.cents + p2pLentTotal.cents);
  }

  /// Total de débitos (- a pagar)
  Money get totalDebits {
    return Money(pendingContribution.cents + p2pBorrowedTotal.cents);
  }

  /// Resumo em texto da fórmula matemática
  String get mathEquationSummary {
    final outStr = outOfPocketTotal.formatted;
    final pendStr = pendingContribution.formatted;
    final lentStr = p2pLentTotal.formatted;
    final borrowedStr = p2pBorrowedTotal.formatted;
    final netStr = netBalance.formatted;
    return '($outStr [reembolsos] - $pendStr [aporte pendente]) + ($lentStr [P2P a receber] - $borrowedStr [P2P a pagar]) = $netStr';
  }
}
