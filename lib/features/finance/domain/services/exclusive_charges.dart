import '../entities/house_expense.dart';
import '../entities/house_expense_item.dart';
import '../entities/split_rule.dart';

/// Regra de um sub-item quando ele é de um responsável só; null se entra no
/// rateio da casa. Vale, nesta ordem: a regra do próprio sub-item, o
/// responsável marcado nele e o responsável único da despesa (categoria com dono).
SplitRule? exclusiveItemRule(HouseExpense expense, HouseExpenseItem item) {
  final ownRule = item.splitRule;
  if (ownRule != null && ownRule.type == SplitType.categoryOwner) return ownRule;
  if (item.responsibleMemberId != null) {
    return SplitRule.singleResponsible(item.responsibleMemberId);
  }
  if (ownRule == null &&
      expense.splitRule.type == SplitType.categoryOwner &&
      expense.splitRule.singleResponsibleMemberId != null) {
    return expense.splitRule;
  }
  return null;
}

/// Quanto cada morador deve sozinho, em centavos: despesas e sub-itens de
/// responsável único. No modelo de aportes fixos isso é cobrado por cima do
/// aporte, sem consumir o balde.
Map<String, int> exclusiveChargesByMember(
  List<HouseExpense> expenses,
  List<String> memberIds,
) {
  final charges = <String, int>{};
  void add(String? memberId, int cents) {
    if (memberId == null || cents <= 0 || !memberIds.contains(memberId)) return;
    charges[memberId] = (charges[memberId] ?? 0) + cents;
  }

  for (final expense in expenses) {
    if (expense.isProjectExpense) continue;
    if (expense.items.isEmpty) {
      if (expense.splitRule.type == SplitType.categoryOwner) {
        add(expense.splitRule.singleResponsibleMemberId, expense.amount.cents);
      }
      continue;
    }
    for (final item in expense.items) {
      final rule = exclusiveItemRule(expense, item);
      if (rule == null) continue;
      final allocations = rule.calculateAllocations(
        totalAmount: item.amount,
        memberIds: memberIds,
      );
      for (final entry in allocations.entries) {
        add(entry.key, entry.value.cents);
      }
    }
  }
  return charges;
}
