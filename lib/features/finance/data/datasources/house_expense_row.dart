import '../../../../core/domain/value_objects/money.dart';
import '../../domain/entities/house_expense.dart';
import '../../domain/entities/house_expense_item.dart';
import '../../domain/entities/split_rule.dart';

/// Despesa a partir de uma linha de `house_expenses` lida com
/// `house_expense_items(*)` e `split_rules(*)`.
HouseExpense houseExpenseFromRow(Map<String, dynamic> r) {
  final rawItems = r['house_expense_items'] as List<dynamic>? ?? [];
  final items = rawItems.map((item) {
    final respId = item['responsible_member_id'] as String?;
    return HouseExpenseItem(
      id: item['id'] as String,
      expenseId: item['expense_id'] as String,
      title: item['title'] as String,
      amount: Money((item['amount_cents'] as num).toInt()),
      categoryId: item['category_id'] as String?,
      responsibleMemberId: respId,
      splitRule: respId != null ? SplitRule.singleResponsible(respId) : null,
    );
  }).toList();

  final statusStr = r['status'] as String? ?? 'paid';
  final status = statusStr == 'pending' ? ExpenseStatus.pending : ExpenseStatus.paid;

  final splitTypeStr = r['split_type'] as String? ?? 'percentage';
  final rawSplitRules = r['split_rules'] as List<dynamic>? ?? [];

  SplitRule splitRule;
  if (splitTypeStr == 'category_owner') {
    final responsibleId = rawSplitRules.isNotEmpty
        ? rawSplitRules.first['member_id'] as String?
        : null;
    // Despesas antigas não têm a regra gravada: assume quem pagou
    splitRule = SplitRule.singleResponsible(responsibleId ?? r['paid_by_id'] as String?);
  } else if (splitTypeStr == 'fixed') {
    final fixedMap = <String, Money>{};
    for (final sr in rawSplitRules) {
      final mId = sr['member_id'] as String?;
      final fixedCents = (sr['fixed_amount_cents'] as num?)?.toInt() ?? 0;
      if (mId != null && fixedCents > 0) fixedMap[mId] = Money(fixedCents);
    }
    splitRule = SplitRule.fixed(fixedMap.isNotEmpty ? fixedMap : null);
  } else {
    final pctMap = <String, double>{};
    for (final sr in rawSplitRules) {
      final mId = sr['member_id'] as String?;
      final basisPoints = (sr['percentage_basis_points'] as num?)?.toInt();
      if (mId != null && basisPoints != null) {
        pctMap[mId] = basisPoints / 100.0;
      }
    }
    splitRule = SplitRule.percentage(pctMap.isNotEmpty ? pctMap : null);
  }

  return HouseExpense(
    id: r['id'] as String,
    title: r['title'] as String,
    amount: Money((r['amount_cents'] as num).toInt()),
    date: DateTime.parse(r['date'] as String? ?? r['created_at'] as String).toLocal(),
    dueDate: r['due_date'] != null ? DateTime.tryParse(r['due_date'] as String) : null,
    categoryId: r['category_id'] as String? ?? 'cat_geral',
    paidByMemberId: (r['paid_by_participant_id'] as String?) ?? (r['paid_by_id'] as String),
    paidByParticipantId: r['paid_by_participant_id'] as String?,
    paymentMethodId: r['payment_method_id'] as String? ?? 'pm_pix',
    splitRule: splitRule,
    status: status,
    isRecurring: r['is_recurring'] as bool? ?? false,
    isVariable: r['is_variable'] as bool? ?? false,
    dueDay: (r['due_day'] as num?)?.toInt(),
    isActive: r['is_active'] as bool? ?? true,
    settledAt: r['settled_at'] != null ? DateTime.tryParse(r['settled_at'] as String)?.toLocal() : null,
    paidAt: r['paid_at'] != null ? DateTime.tryParse(r['paid_at'] as String)?.toLocal() : null,
    paidOutOfPocket: r['paid_out_of_pocket'] as bool? ?? false,
    description: r['description'] as String?,
    notes: r['notes'] as String?,
    barcode: r['barcode'] as String?,
    createdBy: r['created_by'] as String?,
    items: items,
    recurringSeriesId: r['recurring_series_id'] as String?,
    projectId: r['project_id'] as String?,
    attachmentPath: r['attachment_path'] as String?,
    attachmentName: r['attachment_name'] as String?,
    attachmentContentType: r['attachment_content_type'] as String?,
    attachmentSizeBytes: (r['attachment_size_bytes'] as num?)?.toInt(),
    attachmentPurgedAt: r['attachment_purged_at'] != null ? DateTime.tryParse(r['attachment_purged_at'] as String)?.toLocal() : null,
    installmentPlanId: r['installment_plan_id'] as String?,
  );
}
