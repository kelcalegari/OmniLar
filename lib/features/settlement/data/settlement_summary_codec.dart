import '../../../core/domain/value_objects/financial_cycle.dart';
import '../../../core/domain/value_objects/money.dart';
import '../domain/entities/member_audit_trail.dart';
import '../domain/entities/member_net_balance.dart';
import '../domain/entities/settlement_summary.dart';
import '../domain/entities/super_pix_transfer.dart';

/// Retrato do fechamento gravado junto com o ciclo fechado, para que ele possa
/// ser reaberto na tela com saldos, transferências e memória de cálculo, sem
/// recalcular com dados que podem ter mudado depois.
const int settlementSnapshotVersion = 1;

String? _date(DateTime? d) => d?.toIso8601String();
DateTime _parseDate(Object? v) => DateTime.parse(v as String);
Money _money(Object? v) => Money((v as num?)?.toInt() ?? 0);
List<Map<String, dynamic>> _list(Object? v) =>
    (v as List<dynamic>? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();

Map<String, dynamic> settlementSummaryToJson(SettlementSummary s) => {
      'v': settlementSnapshotVersion,
      'total_house_expenses_cents': s.totalHouseExpenses.cents,
      'total_contributions_cents': s.totalContributions.cents,
      'total_p2p_cleared_cents': s.totalP2PCleared.cents,
      'house_treasury_balance_cents': s.houseTreasuryBalance.cents,
      'bucket_deficit_cents': s.bucketDeficit.cents,
      'deficit_covered_by_vault_cents': s.deficitCoveredByVault.cents,
      'opening_balance_cents': s.openingBalance.cents,
      'vault_returns_cents': s.vaultReturns.cents,
      'surplus_refunded_cents': s.surplusRefunded.cents,
      'house_loan_receipts_cents': s.houseLoanReceipts.cents,
      'member_balances': [
        for (final m in s.memberBalances)
          {
            'member_id': m.memberId,
            'member_name': m.memberName,
            'contribution_due_cents': m.contributionDue.cents,
            'contribution_paid_cents': m.contributionPaid.cents,
            'out_of_pocket_cents': m.outOfPocketExpenses.cents,
            'p2p_lent_cents': m.p2pLentDue.cents,
            'p2p_borrowed_cents': m.p2pBorrowedDue.cents,
            'contribution_refund_cents': m.contributionRefund.cents,
          },
      ],
      'transfers': [
        for (final t in s.transfers)
          {
            'id': t.id,
            'from_member_id': t.fromMemberId,
            'from_member_name': t.fromMemberName,
            'to_member_id': t.toMemberId,
            'to_member_name': t.toMemberName,
            'amount_cents': t.amount.cents,
            'description': t.description,
            'pix_key': t.pixKey,
            'explanation': t.explanation,
          },
      ],
      'audit_trails': [for (final a in s.auditTrails.values) _auditToJson(a)],
    };

Map<String, dynamic> _auditToJson(MemberAuditTrail a) => {
      'member_id': a.memberId,
      'member_name': a.memberName,
      'contribution_due_cents': a.contributionDue.cents,
      'contribution_paid_cents': a.contributionPaid.cents,
      'out_of_pocket_total_cents': a.outOfPocketTotal.cents,
      'p2p_lent_total_cents': a.p2pLentTotal.cents,
      'p2p_borrowed_total_cents': a.p2pBorrowedTotal.cents,
      'net_balance_cents': a.netBalance.cents,
      'contribution_refund_cents': a.contributionRefund.cents,
      'expense_shares': [
        for (final e in a.expenseShares)
          {
            'expense_id': e.expenseId,
            'title': e.expenseTitle,
            'total_cents': e.totalExpenseAmount.cents,
            'allocated_cents': e.allocatedAmount.cents,
            'rule': e.ruleDescription,
            'date': _date(e.date),
            'is_personal': e.isPersonal,
          },
      ],
      'contributions_made': [
        for (final c in a.contributionsMade)
          {
            'contribution_id': c.contributionId,
            'amount_cents': c.amount.cents,
            'date': _date(c.date),
            'payment_method_id': c.paymentMethodId,
          },
      ],
      'out_of_pocket': [
        for (final o in a.outOfPocketExpenses)
          {
            'expense_id': o.expenseId,
            'title': o.title,
            'amount_cents': o.amount.cents,
            'date': _date(o.date),
            'payment_method': o.paymentMethod,
          },
      ],
      'p2p_receivables': [for (final p in a.p2pReceivables) _p2pToJson(p)],
      'p2p_payables': [for (final p in a.p2pPayables) _p2pToJson(p)],
    };

Map<String, dynamic> _p2pToJson(P2PInstallmentAudit p) => {
      'loan_id': p.loanId,
      'description': p.description,
      'other_member_id': p.otherMemberId,
      'other_member_name': p.otherMemberName,
      'installment_number': p.installmentNumber,
      'total_installments': p.totalInstallments,
      'amount_cents': p.amount.cents,
      'due_date': _date(p.dueDate),
      'is_receivable': p.isReceivable,
    };

P2PInstallmentAudit _p2pFromJson(Map<String, dynamic> j) => P2PInstallmentAudit(
      loanId: j['loan_id'] as String,
      description: j['description'] as String? ?? '',
      otherMemberId: j['other_member_id'] as String? ?? '',
      otherMemberName: j['other_member_name'] as String? ?? '',
      installmentNumber: (j['installment_number'] as num?)?.toInt() ?? 1,
      totalInstallments: (j['total_installments'] as num?)?.toInt() ?? 1,
      amount: _money(j['amount_cents']),
      dueDate: _parseDate(j['due_date']),
      isReceivable: j['is_receivable'] as bool? ?? false,
    );

MemberAuditTrail _auditFromJson(Map<String, dynamic> j) => MemberAuditTrail(
      memberId: j['member_id'] as String,
      memberName: j['member_name'] as String? ?? '',
      expenseShares: [
        for (final e in _list(j['expense_shares']))
          ExpenseShareAudit(
            expenseId: e['expense_id'] as String,
            expenseTitle: e['title'] as String? ?? '',
            totalExpenseAmount: _money(e['total_cents']),
            allocatedAmount: _money(e['allocated_cents']),
            ruleDescription: e['rule'] as String? ?? '',
            date: _parseDate(e['date']),
            isPersonal: e['is_personal'] as bool? ?? false,
          ),
      ],
      contributionsMade: [
        for (final c in _list(j['contributions_made']))
          ContributionAudit(
            contributionId: c['contribution_id'] as String,
            amount: _money(c['amount_cents']),
            date: _parseDate(c['date']),
            paymentMethodId: c['payment_method_id'] as String?,
          ),
      ],
      outOfPocketExpenses: [
        for (final o in _list(j['out_of_pocket']))
          OutOfPocketAudit(
            expenseId: o['expense_id'] as String,
            title: o['title'] as String? ?? '',
            amount: _money(o['amount_cents']),
            date: _parseDate(o['date']),
            paymentMethod: o['payment_method'] as String?,
          ),
      ],
      p2pReceivables: [for (final p in _list(j['p2p_receivables'])) _p2pFromJson(p)],
      p2pPayables: [for (final p in _list(j['p2p_payables'])) _p2pFromJson(p)],
      contributionDue: _money(j['contribution_due_cents']),
      contributionPaid: _money(j['contribution_paid_cents']),
      outOfPocketTotal: _money(j['out_of_pocket_total_cents']),
      p2pLentTotal: _money(j['p2p_lent_total_cents']),
      p2pBorrowedTotal: _money(j['p2p_borrowed_total_cents']),
      netBalance: _money(j['net_balance_cents']),
      contributionRefund: _money(j['contribution_refund_cents']),
    );

/// Reconstrói o fechamento gravado. Devolve null quando o retrato não existe,
/// é de uma versão desconhecida ou está corrompido (a tela cai no resumo simples).
SettlementSummary? settlementSummaryFromJson(
  Object? json, {
  required FinancialCycle cycle,
  DateTime? settledAt,
}) {
  if (json is! Map || json['v'] != settlementSnapshotVersion) return null;
  try {
    final j = Map<String, dynamic>.from(json);
    final audits = [for (final a in _list(j['audit_trails'])) _auditFromJson(a)];
    return SettlementSummary(
      cycle: cycle,
      memberBalances: [
        for (final m in _list(j['member_balances']))
          MemberNetBalance(
            memberId: m['member_id'] as String,
            memberName: m['member_name'] as String? ?? '',
            contributionDue: _money(m['contribution_due_cents']),
            contributionPaid: _money(m['contribution_paid_cents']),
            outOfPocketExpenses: _money(m['out_of_pocket_cents']),
            p2pLentDue: _money(m['p2p_lent_cents']),
            p2pBorrowedDue: _money(m['p2p_borrowed_cents']),
            contributionRefund: _money(m['contribution_refund_cents']),
          ),
      ],
      transfers: [
        for (final t in _list(j['transfers']))
          SuperPixTransfer(
            id: t['id'] as String,
            fromMemberId: t['from_member_id'] as String,
            fromMemberName: t['from_member_name'] as String? ?? '',
            toMemberId: t['to_member_id'] as String,
            toMemberName: t['to_member_name'] as String? ?? '',
            amount: _money(t['amount_cents']),
            description: t['description'] as String? ?? '',
            status: TransferStatus.confirmed,
            pixKey: t['pix_key'] as String?,
            explanation: t['explanation'] as String?,
          ),
      ],
      totalHouseExpenses: _money(j['total_house_expenses_cents']),
      totalContributions: _money(j['total_contributions_cents']),
      totalP2PCleared: _money(j['total_p2p_cleared_cents']),
      houseTreasuryBalance: _money(j['house_treasury_balance_cents']),
      status: SettlementStatus.settled,
      settledAt: settledAt,
      auditTrails: {for (final a in audits) a.memberId: a},
      bucketDeficit: _money(j['bucket_deficit_cents']),
      deficitCoveredByVault: _money(j['deficit_covered_by_vault_cents']),
      openingBalance: _money(j['opening_balance_cents']),
      vaultReturns: _money(j['vault_returns_cents']),
      surplusRefunded: _money(j['surplus_refunded_cents']),
      houseLoanReceipts: _money(j['house_loan_receipts_cents']),
    );
  } catch (_) {
    return null;
  }
}
