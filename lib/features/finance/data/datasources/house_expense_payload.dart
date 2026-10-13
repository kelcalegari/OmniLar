import '../../../../core/utils/uuid.dart';
import '../../domain/entities/house_expense.dart';
import '../../domain/entities/split_rule.dart';

String splitTypeToDb(SplitType type) {
  switch (type) {
    case SplitType.percentage:
      return 'percentage';
    case SplitType.fixed:
      return 'fixed';
    case SplitType.categoryOwner:
      return 'category_owner';
  }
}

/// Linhas de `split_rules` de uma despesa (sem o `expense_id`).
List<Map<String, dynamic>> splitRuleRows(HouseExpense expense) {
  final rule = expense.splitRule;
  final rows = <Map<String, dynamic>>[];

  if (rule.type == SplitType.percentage && rule.percentages != null) {
    final memberIds = rule.percentages!.keys.where(isUuid).toList();
    final allocations = rule.calculateAllocations(
      totalAmount: expense.amount,
      memberIds: memberIds,
    );
    for (final memberId in memberIds) {
      rows.add({
        'member_id': memberId,
        'percentage_basis_points': (rule.percentages![memberId]! * 100).round().clamp(0, 10000),
        'calculated_cents': allocations[memberId]?.cents ?? 0,
      });
    }
  } else if (rule.type == SplitType.fixed && rule.fixedAmounts != null) {
    for (final entry in rule.fixedAmounts!.entries) {
      if (!isUuid(entry.key)) continue;
      rows.add({
        'member_id': entry.key,
        'fixed_amount_cents': entry.value.cents,
        'calculated_cents': entry.value.cents,
      });
    }
  } else if (rule.type == SplitType.categoryOwner && isUuid(rule.singleResponsibleMemberId)) {
    rows.add({
      'member_id': rule.singleResponsibleMemberId,
      'percentage_basis_points': 10000,
      'calculated_cents': expense.amount.cents,
    });
  }
  return rows;
}

/// Despesa completa (linha, sub-itens e rateio) no formato da RPC
/// `create_house_expense`, que grava tudo em uma transação.
Map<String, dynamic> houseExpensePayload(
  HouseExpense expense, {
  required String houseId,
  required String? currentUserId,
  DateTime? dueDate,
}) {
  return {
    if (isUuid(expense.id)) 'id': expense.id,
    'house_id': houseId,
    'title': expense.title,
    'amount_cents': expense.amount.cents,
    if (isUuid(expense.categoryId)) 'category_id': expense.categoryId,
    if (isUuid(expense.paymentMethodId)) 'payment_method_id': expense.paymentMethodId,
    'paid_by_id': isUuid(expense.paidByMemberId)
        ? expense.paidByMemberId
        : (currentUserId ?? expense.paidByMemberId),
    'paid_out_of_pocket': expense.paidOutOfPocket,
    'due_date': (dueDate ?? expense.dueDate ?? expense.date).toIso8601String().split('T')[0],
    'date': expense.date.toUtc().toIso8601String(),
    'cycle_start_date': expense.date.toIso8601String().split('T')[0],
    'split_type': splitTypeToDb(expense.splitRule.type),
    'status': expense.isPaid ? 'paid' : 'pending',
    if (expense.isPaid && expense.paidAt != null)
      'paid_at': expense.paidAt!.toUtc().toIso8601String(),
    'is_recurring': expense.isRecurring,
    'is_variable': expense.isVariable,
    if (expense.dueDay != null) 'due_day': expense.dueDay,
    'is_active': expense.isActive,
    if (isUuid(expense.recurringSeriesId)) 'recurring_series_id': expense.recurringSeriesId,
    if (isUuid(expense.projectId)) 'project_id': expense.projectId,
    if (expense.notes != null) 'notes': expense.notes,
    'items': [
      for (final item in expense.items)
        {
          if (isUuid(item.id)) 'id': item.id,
          'title': item.title,
          'amount_cents': item.amount.cents,
          if (isUuid(item.categoryId)) 'category_id': item.categoryId,
          if (isUuid(item.responsibleMemberId)) 'responsible_member_id': item.responsibleMemberId,
          if (item.splitRule != null) 'split_type': splitTypeToDb(item.splitRule!.type),
        },
    ],
    'split_rules': splitRuleRows(expense),
  };
}
