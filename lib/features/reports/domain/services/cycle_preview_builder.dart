import '../../../../core/domain/value_objects/money.dart';
import '../../../finance/domain/entities/card_invoice.dart';
import '../../../finance/domain/entities/cycle_funding_estimate.dart';
import '../../../finance/domain/entities/house_expense.dart';
import '../../../finance/domain/entities/house_member.dart';
import '../../../finance/domain/entities/payment_method.dart';
import '../../../finance/domain/entities/split_rule.dart';
import '../../../finance/domain/services/exclusive_charges.dart';
import '../../../p2p/domain/entities/p2p_loan.dart';
import '../../../settlement/domain/entities/member_audit_trail.dart';
import '../../../settlement/domain/entities/settlement_summary.dart';
import '../../../settlement/domain/services/open_invoice_choices.dart';
import '../entities/cycle_preview.dart';

/// Monta a prévia do fechamento a partir do mesmo resumo do Hub de
/// Liquidação. Não refaz a conta do fechamento: só acrescenta quem paga cada
/// fatura e conta em aberto e a projeção do que ainda falta lançar.
class CyclePreviewBuilder {
  const CyclePreviewBuilder();

  CyclePreview build({
    required SettlementSummary summary,
    required List<HouseMember> members,
    required List<HouseExpense> expenses,
    required List<PaymentMethod> paymentMethods,
    CycleFundingEstimate? estimate,
    Map<String, String> invoiceCodes = const {},
    required DateTime today,
  }) {
    final cycle = summary.cycle;
    final isSettled = summary.status == SettlementStatus.settled;
    final day = DateTime(today.year, today.month, today.day);
    final houseExpenses = expenses.where((e) => !e.isProjectExpense).toList();

    final assumed = isSettled
        ? const <AssumedPayment>[]
        : _assumedPayments(houseExpenses, paymentMethods, invoiceCodes, day);

    // Projeção: só para ciclo aberto que ainda não terminou
    var projectedExtra = const Money.zero();
    if (!isSettled && !cycle.endDate.isBefore(day) && estimate != null) {
      final launched = houseExpenses.fold<int>(
        0,
        (acc, e) => acc + e.amount.cents,
      );
      final extra = estimate.totalProjectedExpenses.cents - launched;
      if (extra > 0) projectedExtra = Money(extra);
    }

    final usesFixed = members.any((m) => (m.defaultFixedAmountCents ?? 0) > 0);
    final memberIds = members.map((m) => m.id).toList();

    // Rateio por percentual: a estimativa entra pelo percentual padrão
    var extraShares = const <String, Money>{};
    if (!usesFixed && projectedExtra.isPositive) {
      extraShares = SplitRule.percentage(
        {for (final m in members) m.id: m.defaultSplitPercent},
      ).calculateAllocations(totalAmount: projectedExtra, memberIds: memberIds);
    }

    // Aportes fixos: a estimativa só mexe no balde
    var projectedOverflow = const Money.zero();
    if (usesFixed && !isSettled) {
      final bucket = members.fold<int>(
        0,
        (acc, m) => acc + (m.defaultFixedAmountCents ?? 0),
      );
      final exclusive = exclusiveChargesByMember(
        houseExpenses,
        memberIds,
      ).values.fold<int>(0, (acc, c) => acc + c);
      final total = houseExpenses.fold<int>(
        0,
        (acc, e) => acc + e.amount.cents,
      );
      final overflow =
          total -
          exclusive +
          projectedExtra.cents -
          bucket -
          // Só a sobra anterior cobre o excedente; o que voltou das caixinhas não
          (summary.openingBalance.cents - summary.vaultReturns.cents);
      if (overflow > 0) projectedOverflow = Money(overflow);
    }

    final names = {for (final m in members) m.id: m.name};
    final previews = <MemberCyclePreview>[
      for (final b in summary.memberBalances)
        MemberCyclePreview(
          memberId: b.memberId,
          memberName: names[b.memberId] ?? b.memberName,
          contributionDue: b.contributionDue,
          contributionPaid: b.contributionPaid,
          outOfPocket: b.outOfPocketExpenses,
          contributionRefund: b.contributionRefund,
          p2pToPay: b.p2pBorrowedDue,
          p2pToReceive: b.p2pLentDue,
          net: b.netBalance,
          transfersOut: summary.transfers
              .where((t) => t.fromMemberId == b.memberId)
              .toList(),
          transfersIn: summary.transfers
              .where((t) => t.toMemberId == b.memberId)
              .toList(),
          installmentsToPay: _named(
            summary.auditTrails[b.memberId]?.p2pPayables,
          ),
          installmentsToReceive: _named(
            summary.auditTrails[b.memberId]?.p2pReceivables,
          ),
          assumedPayments: assumed
              .where((a) => a.payerMemberId == b.memberId)
              .toList(),
          projectedExtraShare: extraShares[b.memberId] ?? const Money.zero(),
        ),
    ];

    return CyclePreview(
      cycle: cycle,
      isSettled: isSettled,
      settledAt: summary.settledAt,
      members: previews,
      assumedPayments: assumed,
      projectedExtra: projectedExtra,
      usesFixedContributions: usesFixed,
      bucketOverflow: isSettled ? const Money.zero() : summary.bucketDeficit,
      projectedBucketOverflow: projectedOverflow,
    );
  }

  /// Faturas e contas em aberto com quem paga cada uma pela escolha padrão
  /// do fechamento.
  List<AssumedPayment> _assumedPayments(
    List<HouseExpense> expenses,
    List<PaymentMethod> paymentMethods,
    Map<String, String> invoiceCodes,
    DateTime today,
  ) {
    final methods = {for (final m in paymentMethods) m.id: m};
    final result = <AssumedPayment>[
      for (final invoice in openInvoicesOf(expenses, paymentMethods))
        AssumedPayment(
          title: 'Fatura ${invoice.card.name}',
          dueDate: invoice.dueDate,
          amount: invoice.total,
          payerMemberId:
              defaultOpenInvoiceChoice(invoice.card) ==
                  OpenInvoiceChoice.paidByHolder
              ? invoice.card.ownerMemberId
              : null,
          isInvoice: true,
          isOverdue: invoice.dueDate.isBefore(today),
          barcode:
              invoiceCodes[CardInvoiceCode.keyOf(
                invoice.card.id,
                invoice.dueDate,
              )],
        ),
      for (final bill in openBillsOf(expenses, paymentMethods))
        AssumedPayment(
          title: bill.title,
          dueDate: bill.effectiveDueDate,
          amount: bill.amount,
          payerMemberId:
              methods[defaultBillMethodId(bill, paymentMethods)]?.ownerMemberId,
          isInvoice: false,
          isOverdue: bill.effectiveDueDate.isBefore(today),
          barcode: bill.barcode,
        ),
    ]..sort((a, b) => a.dueDate.compareTo(b.dueDate));
    return result;
  }

  /// O motor não conhece o Caixa como morador: dá nome a ele nas parcelas.
  List<P2PInstallmentAudit> _named(List<P2PInstallmentAudit>? audits) => [
    for (final a in audits ?? const <P2PInstallmentAudit>[])
      a.otherMemberId == P2PLoan.houseLenderId
          ? P2PInstallmentAudit(
              loanId: a.loanId,
              description: a.description,
              otherMemberId: a.otherMemberId,
              otherMemberName: 'Caixa da Casa',
              installmentNumber: a.installmentNumber,
              totalInstallments: a.totalInstallments,
              amount: a.amount,
              dueDate: a.dueDate,
              isReceivable: a.isReceivable,
            )
          : a,
  ];
}
