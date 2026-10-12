import '../../../../core/domain/value_objects/money.dart';
import '../../domain/entities/house_expense.dart';
import '../../domain/entities/house_expense_item.dart';
import '../../domain/entities/split_rule.dart';

/// Serialização de despesas para a fila offline.

Map<String, dynamic>? _splitRuleToJson(SplitRule? rule) {
  if (rule == null) return null;
  return {
    'type': rule.type.name,
    'percentages': rule.percentages,
    'fixedAmounts': rule.fixedAmounts?.map((id, money) => MapEntry(id, money.cents)),
    'singleResponsibleMemberId': rule.singleResponsibleMemberId,
  };
}

SplitRule? _splitRuleFromJson(Map<String, dynamic>? json) {
  if (json == null) return null;
  switch (json['type'] as String?) {
    case 'fixed':
      final fixed = json['fixedAmounts'] as Map?;
      return SplitRule.fixed(
        fixed?.map((id, cents) => MapEntry(id as String, Money((cents as num).toInt()))),
      );
    case 'categoryOwner':
      return SplitRule.singleResponsible(json['singleResponsibleMemberId'] as String?);
    default:
      final percentages = json['percentages'] as Map?;
      return SplitRule.percentage(
        percentages?.map((id, percent) => MapEntry(id as String, (percent as num).toDouble())),
      );
  }
}

Map<String, dynamic> houseExpenseToJson(HouseExpense expense) => {
  'id': expense.id,
  'title': expense.title,
  'amountCents': expense.amount.cents,
  'date': expense.date.toIso8601String(),
  'dueDate': expense.dueDate?.toIso8601String(),
  'categoryId': expense.categoryId,
  'paidByMemberId': expense.paidByMemberId,
  'paymentMethodId': expense.paymentMethodId,
  'splitRule': _splitRuleToJson(expense.splitRule),
  'status': expense.status.name,
  'isRecurring': expense.isRecurring,
  'isVariable': expense.isVariable,
  'dueDay': expense.dueDay,
  'isActive': expense.isActive,
  'paidOutOfPocket': expense.paidOutOfPocket,
  'notes': expense.notes,
  'recurringSeriesId': expense.recurringSeriesId,
  'projectId': expense.projectId,
  'paidAt': expense.paidAt?.toIso8601String(),
  'items': [
    for (final item in expense.items)
      {
        'id': item.id,
        'expenseId': item.expenseId,
        'title': item.title,
        'amountCents': item.amount.cents,
        'categoryId': item.categoryId,
        'responsibleMemberId': item.responsibleMemberId,
        'splitRule': _splitRuleToJson(item.splitRule),
      },
  ],
};

HouseExpense houseExpenseFromJson(Map<String, dynamic> json) => HouseExpense(
  id: json['id'] as String,
  title: json['title'] as String,
  amount: Money((json['amountCents'] as num).toInt()),
  date: DateTime.parse(json['date'] as String),
  dueDate: json['dueDate'] != null ? DateTime.parse(json['dueDate'] as String) : null,
  categoryId: json['categoryId'] as String,
  paidByMemberId: json['paidByMemberId'] as String,
  paymentMethodId: json['paymentMethodId'] as String,
  splitRule:
      _splitRuleFromJson((json['splitRule'] as Map?)?.cast<String, dynamic>()) ??
      const SplitRule.percentage(null),
  status: json['status'] == ExpenseStatus.pending.name ? ExpenseStatus.pending : ExpenseStatus.paid,
  isRecurring: json['isRecurring'] as bool? ?? false,
  isVariable: json['isVariable'] as bool? ?? false,
  dueDay: (json['dueDay'] as num?)?.toInt(),
  isActive: json['isActive'] as bool? ?? true,
  paidOutOfPocket: json['paidOutOfPocket'] as bool? ?? false,
  notes: json['notes'] as String?,
  recurringSeriesId: json['recurringSeriesId'] as String?,
  projectId: json['projectId'] as String?,
  paidAt: json['paidAt'] != null ? DateTime.parse(json['paidAt'] as String) : null,
  items: [
    for (final raw in (json['items'] as List? ?? const []))
      HouseExpenseItem(
        id: (raw as Map)['id'] as String,
        expenseId: raw['expenseId'] as String,
        title: raw['title'] as String,
        amount: Money((raw['amountCents'] as num).toInt()),
        categoryId: raw['categoryId'] as String?,
        responsibleMemberId: raw['responsibleMemberId'] as String?,
        splitRule: _splitRuleFromJson((raw['splitRule'] as Map?)?.cast<String, dynamic>()),
      ),
  ],
);
