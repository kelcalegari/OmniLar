import '../../../../core/domain/value_objects/money.dart';
import '../../../finance/domain/entities/card_invoice_breakdown.dart';
import '../entities/imported_statement_line.dart';
import 'import_session.dart';

/// Para onde a compra foi, pelo que a importação gravou dela.
InvoicePartKind invoicePartKindOf({
  required LineDestination destination,
  required LineOutcome outcome,
  String? expenseId,
  String? loanId,
}) {
  if (outcome == LineOutcome.skipped) return InvoicePartKind.skipped;
  if (loanId != null) return InvoicePartKind.loan;
  switch (destination) {
    case LineDestination.cardOwnerPersonal:
      return InvoicePartKind.personal;
    case LineDestination.thirdParty:
      return InvoicePartKind.thirdParty;
    case LineDestination.house:
    case LineDestination.splitP2P:
    case LineDestination.ignored:
      return expenseId != null ? InvoicePartKind.house : InvoicePartKind.ignored;
  }
}

/// Linha da fatura inteira a partir do registro de uma importação, ou null
/// quando não entra na soma (pagamento da fatura anterior, entrada).
InvoiceFileLine? invoiceFileLineOf(ImportLineRecord record, {String? payerId}) {
  final line = record.line;
  final isRefund = line.kind == StatementLineKind.refund;
  if (!line.isPurchase && !isRefund) return null;
  final kind = invoicePartKindOf(
    destination: line.destination,
    outcome: record.outcome,
    expenseId: record.expenseId,
    loanId: record.loanId,
  );
  return InvoiceFileLine(
    amount: line.amount,
    isRefund: isRefund,
    kind: kind,
    memberId: kind == InvoicePartKind.personal ? payerId : line.assignedMemberId,
    signature: line.signature,
    expenseId: record.expenseId,
    loanId: record.loanId,
  );
}

/// Linha da fatura inteira a partir de uma linha gravada em `import_lines`.
InvoiceFileLine? invoiceFileLineFromRow(Map<String, dynamic> row, {String? payerId}) {
  final lineKind = row['kind'] as String? ?? 'purchase';
  if (lineKind != 'purchase' && lineKind != 'refund') return null;
  final destination = switch (row['split_destination'] as String?) {
    'p2p_loan' => LineDestination.splitP2P,
    'personal' || 'personal_ignored' => LineDestination.cardOwnerPersonal,
    'ignored' => LineDestination.ignored,
    'third_party' => LineDestination.thirdParty,
    _ => LineDestination.house,
  };
  final outcome = LineOutcome.values.where((o) => o.name == row['decision']).firstOrNull ?? LineOutcome.ignored;
  final expenseId = row['expense_id'] as String?;
  final loanId = row['loan_id'] as String?;
  final kind = invoicePartKindOf(destination: destination, outcome: outcome, expenseId: expenseId, loanId: loanId);
  return InvoiceFileLine(
    amount: Money((row['amount_cents'] as num).toInt()),
    isRefund: lineKind == 'refund',
    kind: kind,
    memberId: kind == InvoicePartKind.personal ? payerId : row['assigned_member_id'] as String?,
    signature: row['signature'] as String?,
    expenseId: expenseId,
    loanId: loanId,
  );
}
