import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/entities/house_expense.dart';
import '../../domain/entities/category.dart';
import '../../domain/entities/payment_method.dart';
import '../../domain/entities/house_member.dart';
import '../../domain/entities/split_rule.dart';

class ExpenseTimelineItem extends StatelessWidget {
  final HouseExpense expense;
  final ExpenseCategory? category;
  final PaymentMethod? paymentMethod;
  final HouseMember? paidByMember;

  const ExpenseTimelineItem({
    super.key,
    required this.expense,
    this.category,
    this.paymentMethod,
    this.paidByMember,
  });

  IconData _getCategoryIcon(String iconName) {
    switch (iconName) {
      case 'shopping_cart_outlined':
        return Icons.shopping_cart_outlined;
      case 'home_outlined':
        return Icons.home_outlined;
      case 'bolt_outlined':
        return Icons.bolt_outlined;
      case 'directions_car_outlined':
        return Icons.directions_car_outlined;
      case 'restaurant_outlined':
        return Icons.restaurant_outlined;
      default:
        return Icons.receipt_long_outlined;
    }
  }

  Color _parseColor(String? colorHex) {
    if (colorHex == null || colorHex.isEmpty) return AppColors.primary;
    final buffer = StringBuffer();
    if (colorHex.length == 6 || colorHex.length == 7) buffer.write('ff');
    buffer.write(colorHex.replaceFirst('#', ''));
    return Color(int.parse(buffer.toString(), radix: 16));
  }

  String _getSplitBadgeText() {
    switch (expense.splitRule.type) {
      case SplitType.categoryOwner:
        return 'Dono 100%';
      case SplitType.fixed:
        return 'Fixo';
      case SplitType.percentage:
        return '60/40';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPending = expense.isPending;
    final catColor = _parseColor(category?.colorHex);
    final dateFormatted = DateFormat('dd/MM').format(expense.dueDate ?? expense.date);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isPending
              ? AppColors.folegoWarning.withValues(alpha: 0.4)
              : (theme.brightness == Brightness.dark ? AppColors.borderDark : AppColors.borderLight),
          width: isPending ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          // Ícone da Categoria
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: catColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              _getCategoryIcon(category?.icon ?? ''),
              color: catColor,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),

          // Informações da Despesa
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        expense.title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isPending) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.folegoWarning.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'A vencer',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: AppColors.folegoWarning,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      '$dateFormatted • ${paidByMember?.name ?? "Membro"}',
                      style: theme.textTheme.bodySmall?.copyWith(fontSize: 12),
                    ),
                    if (paymentMethod != null) ...[
                      Text(' • ', style: theme.textTheme.bodySmall),
                      Flexible(
                        child: Text(
                          paymentMethod!.name,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 12,
                            color: paymentMethod!.isBenefit ? AppColors.primary : null,
                            fontWeight: paymentMethod!.isBenefit ? FontWeight.w600 : null,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // Valor e Badge de Rateio
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                expense.amount.format(),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: isPending ? AppColors.folegoWarning : null,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.brightness == Brightness.dark
                      ? Colors.white10
                      : Colors.black.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _getSplitBadgeText(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: theme.textTheme.bodySmall?.color,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
