import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../../../core/domain/value_objects/money.dart';
import '../../../../core/domain/enums/recurrence.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/responsive.dart';
import '../../../../core/widgets/money_input_field.dart';
import '../../../../core/widgets/recurrence_scope_dialog.dart';
import '../../domain/entities/house_expense.dart';
import '../../domain/entities/category.dart';
import '../../domain/entities/payment_method.dart';
import '../../domain/entities/house_member.dart';
import '../../domain/entities/split_rule.dart';
import '../cubit/finance_cubit.dart';

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
    if (expense.isItemized) {
      return 'Composto (${expense.items.length})';
    }
    switch (expense.splitRule.type) {
      case SplitType.categoryOwner:
        return 'Dono 100%';
      case SplitType.fixed:
        return 'Fixo';
      case SplitType.percentage:
        return '60/40';
    }
  }

  void _showConfirmPaymentModal(BuildContext context) {
    Money confirmedAmount = expense.amount;

    showAdaptiveModal(
      context: context,
      maxWidth: 500,
      child: StatefulBuilder(
        builder: (modalContext, setModalState) {
          return Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.creditGreen.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.check_circle_outline, color: AppColors.creditGreen),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Confirmar Pagamento',
                            style: Theme.of(modalContext).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            expense.title,
                            style: const TextStyle(color: Colors.grey, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (expense.isOverdue) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: AppColors.debtRed.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.debtRed.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded, size: 18, color: AppColors.debtRed),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Conta vencida há ${expense.daysOverdue} dia${expense.daysOverdue == 1 ? "" : "s"}. Ao pagar, seu Fôlego Financeiro será atualizado.',
                            style: const TextStyle(fontSize: 12, color: AppColors.debtRed, fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (expense.isVariable) ...[
                  const Text(
                    'Esta é uma conta com valor variável. Confirme ou ajuste o valor real da fatura:',
                    style: TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  MoneyInputField(
                    label: 'Valor Real Pago',
                    initialValue: confirmedAmount,
                    primaryColor: AppColors.primary,
                    onChanged: (money) {
                      setModalState(() {
                        confirmedAmount = money;
                      });
                    },
                  ),
                ] else ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Theme.of(modalContext).cardColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Valor da Conta:', style: TextStyle(fontWeight: FontWeight.w600)),
                        Text(
                          expense.amount.format(),
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ],

                if (expense.isItemized) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(modalContext).cardColor,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.receipt_long_outlined, size: 14, color: AppColors.primary),
                            SizedBox(width: 4),
                            Text(
                              'Discriminação do Boleto:',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primary),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        ...expense.items.map((it) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(it.title, style: const TextStyle(fontSize: 12)),
                                  Text(it.amount.format(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            )),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 20),
                SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.creditGreen,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () {
                      context.read<FinanceCubit>().markExpenseAsPaid(
                            expense.id,
                            actualAmount: confirmedAmount,
                          );
                      Navigator.pop(modalContext);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Pagamento de "${expense.title}" confirmado! 🎉')),
                      );
                    },
                    child: const Text('Confirmar Pagamento', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: AppColors.debtRed),
                    icon: const Icon(Icons.delete_outline_rounded, size: 16),
                    label: const Text('Excluir esta conta', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    onPressed: () async {
                      RecurrenceScope scope = RecurrenceScope.thisInstanceOnly;
                      if (expense.isRecurring) {
                        final chosenScope = await showRecurrenceScopeDialog(
                          context: modalContext,
                          itemTitle: expense.title,
                          isDelete: true,
                          isExpense: true,
                        );
                        if (chosenScope == null) return;
                        scope = chosenScope;
                      } else {
                        final confirmed = await showDialog<bool>(
                          context: modalContext,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Excluir Despesa'),
                            content: Text('Tem certeza que deseja excluir "${expense.title}"?'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('Cancelar'),
                              ),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(backgroundColor: AppColors.debtRed, foregroundColor: Colors.white),
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('Excluir'),
                              ),
                            ],
                          ),
                        );
                        if (confirmed != true) return;
                      }

                      if (modalContext.mounted) Navigator.pop(modalContext);
                      if (context.mounted) {
                        await context.read<FinanceCubit>().deleteExpense(expense.id, scope: scope);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Despesa "${expense.title}" excluída.')),
                        );
                      }
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPending = expense.isPending;
    final isOverdue = expense.isOverdue;
    final catColor = _parseColor(category?.colorHex);
    final dateFormatted = DateFormat('dd/MM').format(expense.dueDate ?? expense.date);

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: isPending ? () => _showConfirmPaymentModal(context) : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: theme.cardTheme.color,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isOverdue
                ? AppColors.debtRed.withValues(alpha: 0.6)
                : (isPending
                    ? AppColors.folegoWarning.withValues(alpha: 0.4)
                    : (theme.brightness == Brightness.dark ? AppColors.borderDark : AppColors.borderLight)),
            width: (isOverdue || isPending) ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
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
                          if (expense.isRecurring) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.repeat_rounded, size: 10, color: AppColors.primary),
                                  const SizedBox(width: 2),
                                  Text(
                                    expense.isVariable ? 'Variável' : 'Fixa',
                                    style: const TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          if (expense.isItemized) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.accent.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.account_tree_outlined, size: 10, color: AppColors.accent),
                                  const SizedBox(width: 2),
                                  Text(
                                    '${expense.items.length} itens',
                                    style: const TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.accent,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          if (isPending) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: isOverdue
                                    ? AppColors.debtRed.withValues(alpha: 0.15)
                                    : AppColors.folegoWarning.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (isOverdue) ...[
                                    const Icon(Icons.warning_amber_rounded, size: 10, color: AppColors.debtRed),
                                    const SizedBox(width: 2),
                                  ],
                                  Text(
                                    isOverdue ? 'Atrasada (${expense.daysOverdue}d)' : 'A vencer',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: isOverdue ? AppColors.debtRed : AppColors.folegoWarning,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              '$dateFormatted • ${paidByMember?.name ?? "Membro"}${paymentMethod != null ? " • ${paymentMethod!.name}" : ""}',
                              style: theme.textTheme.bodySmall?.copyWith(fontSize: 12),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),

                // Valor e Badge de Rateio / Ação de pagamento
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      expense.amount.format(),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: isOverdue
                            ? AppColors.debtRed
                            : (isPending ? AppColors.folegoWarning : null),
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (isPending)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.creditGreen.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: AppColors.creditGreen.withValues(alpha: 0.3)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check_rounded, size: 11, color: AppColors.creditGreen),
                            SizedBox(width: 2),
                            Text(
                              'Pagar',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: AppColors.creditGreen,
                              ),
                            ),
                          ],
                        ),
                      )
                    else
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
            if (expense.isItemized) _buildItemizedBreakdown(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildItemizedBreakdown(ThemeData theme) {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.brightness == Brightness.dark
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: theme.dividerColor.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.account_tree_outlined, size: 12, color: AppColors.primary),
              const SizedBox(width: 4),
              Text(
                'Sub-itens discriminados:',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: expense.items.map((item) {
              final isSingleResponsible = item.responsibleMemberId != null;
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isSingleResponsible
                      ? AppColors.primary.withValues(alpha: 0.08)
                      : theme.cardColor,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isSingleResponsible
                        ? AppColors.primary.withValues(alpha: 0.3)
                        : theme.dividerColor.withValues(alpha: 0.5),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        item.title,
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      item.amount.format(),
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                    if (isSingleResponsible) ...[
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: const Text(
                          '100%',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
