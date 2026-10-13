import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/money_input_field.dart';
import '../../../../core/widgets/recurrence_scope_dialog.dart';
import '../../../../core/domain/enums/recurrence.dart';
import '../../../../core/domain/value_objects/money.dart';
import '../../../finance/domain/entities/house_expense.dart';
import '../../../finance/domain/entities/category.dart';
import '../../../finance/domain/entities/payment_method.dart';
import '../../../finance/domain/entities/house_member.dart';
import '../../../finance/domain/entities/split_rule.dart';
import '../../../finance/presentation/cubit/finance_cubit.dart';
import '../../../finance/presentation/cubit/finance_state.dart';
import '../../../finance/presentation/pages/add_expense_page.dart';
import '../../../finance/presentation/widgets/audit_log_sheet.dart';

class ExpenseDetailDesktopPane extends StatefulWidget {
  final HouseExpense expense;
  final ExpenseCategory? category;
  final PaymentMethod? paymentMethod;
  final HouseMember? paidByMember;
  final List<HouseMember> members;
  final VoidCallback onClose;

  const ExpenseDetailDesktopPane({
    super.key,
    required this.expense,
    this.category,
    this.paymentMethod,
    this.paidByMember,
    required this.members,
    required this.onClose,
  });

  @override
  State<ExpenseDetailDesktopPane> createState() => _ExpenseDetailDesktopPaneState();
}

class _ExpenseDetailDesktopPaneState extends State<ExpenseDetailDesktopPane> {
  late Money _confirmedAmount;

  @override
  void initState() {
    super.initState();
    _confirmedAmount = widget.expense.amount;
  }

  @override
  void didUpdateWidget(covariant ExpenseDetailDesktopPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.expense.id != widget.expense.id) {
      _confirmedAmount = widget.expense.amount;
    }
  }

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
    if (widget.expense.isItemized) {
      return 'Composto (${widget.expense.items.length} itens)';
    }
    switch (widget.expense.splitRule.type) {
      case SplitType.categoryOwner:
        return 'Dono 100%';
      case SplitType.fixed:
        return 'Fixo / Balde Comum';
      case SplitType.percentage:
        final pcts = widget.expense.splitRule.percentages;
        if (pcts != null && pcts.isNotEmpty) {
          return pcts.values.map((v) => '${v.round()}%').join(' / ');
        }
        return 'Proporcional aos Rendimentos';
    }
  }

  Future<void> _handleDelete() async {
    final expense = widget.expense;
    RecurrenceScope scope = RecurrenceScope.thisInstanceOnly;
    if (expense.isRecurring) {
      final chosenScope = await showRecurrenceScopeDialog(
        context: context,
        itemTitle: expense.title,
        isDelete: true,
        isExpense: true,
      );
      if (chosenScope == null) return;
      scope = chosenScope;
    } else {
      final confirmed = await showDialog<bool>(
        context: context,
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

    if (mounted) {
      widget.onClose();
      await context.read<FinanceCubit>().deleteExpense(expense.id, scope: scope);
      if (mounted) {
        final state = context.read<FinanceCubit>().state;
        if (state.status == FinanceStatus.failure && state.errorMessage != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: AppColors.debtRed,
              content: Text(state.errorMessage!),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Despesa "${expense.title}" excluída.')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final expense = widget.expense;
    final catColor = _parseColor(widget.category?.colorHex);
    final dateFormatted = DateFormat('dd/MM/yyyy').format(expense.date);
    final dueDateFormatted = expense.dueDate != null ? DateFormat('dd/MM/yyyy').format(expense.dueDate!) : null;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppColors.primary.withValues(alpha: 0.3), width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top Bar: Fechar & Título
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: catColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    _getCategoryIcon(widget.category?.icon ?? ''),
                    color: catColor,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        expense.title,
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '${widget.category?.name ?? "Geral"} • Data: $dateFormatted',
                        style: const TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  tooltip: 'Fechar detalhes',
                  onPressed: widget.onClose,
                ),
              ],
            ),
            const Divider(height: 24),

            // Card de Valor & Status
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.cardColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Valor do Lançamento', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      const SizedBox(height: 4),
                      Text(
                        expense.amount.format(),
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: expense.isPending ? AppColors.folegoWarning : AppColors.creditGreen,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: (expense.isPending ? AppColors.folegoWarning : AppColors.creditGreen).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      expense.isPending ? (expense.isOverdue ? 'Atrasada' : 'A Vencer') : 'Paga',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: expense.isPending ? AppColors.folegoWarning : AppColors.creditGreen,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Metadados do Lançamento
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: theme.cardColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildMetaRow('Quem pagou / Responsável:', widget.paidByMember?.name ?? 'Membro'),
                  const SizedBox(height: 8),
                  _buildMetaRow('Forma de Pagamento:', widget.paymentMethod?.name ?? 'Pix'),
                  const SizedBox(height: 8),
                  _buildMetaRow('Modelo de Rateio:', _getSplitBadgeText()),
                  if (dueDateFormatted != null) ...[
                    const SizedBox(height: 8),
                    _buildMetaRow('Vencimento:', dueDateFormatted),
                  ],
                  if (expense.isRecurring) ...[
                    const SizedBox(height: 8),
                    _buildMetaRow('Recorrência:', expense.isVariable ? 'Mensal (Variável)' : 'Mensal (Fixa)'),
                  ],
                  if (expense.notes != null && expense.notes!.isNotEmpty) ...[
                    const Divider(height: 16),
                    Text('Notas: ${expense.notes!}', style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
                  ],
                ],
              ),
            ),

            if (expense.isItemized) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.cardColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.account_tree_outlined, size: 14, color: AppColors.primary),
                        SizedBox(width: 6),
                        Text(
                          'Itens Discriminados:',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primary),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ...expense.items.map((it) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
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

            const Spacer(),

            // Ações Rápidas do Desktop
            if (expense.isPending) ...[
              if (expense.isVariable) ...[
                MoneyInputField(
                  label: 'Confirmar Valor Real',
                  initialValue: _confirmedAmount,
                  primaryColor: AppColors.primary,
                  onChanged: (money) => setState(() => _confirmedAmount = money),
                ),
                const SizedBox(height: 8),
              ],
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.creditGreen,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.check_rounded, size: 18),
                label: const Text('Confirmar Pagamento', style: TextStyle(fontWeight: FontWeight.bold)),
                onPressed: () {
                  context.read<FinanceCubit>().markExpenseAsPaid(expense.id, actualAmount: _confirmedAmount);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Pagamento de "${expense.title}" confirmado! 🎉')),
                  );
                },
              ),
              const SizedBox(height: 8),
            ],

            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text('Editar', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => AddExpensePage(expenseToEdit: expense)),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.debtRed,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.delete_outline_rounded, size: 16),
                    label: const Text('Excluir', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    onPressed: _handleDelete,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Center(
              child: TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: Colors.grey),
                icon: const Icon(Icons.history_edu_rounded, size: 15),
                label: const Text('Ver Histórico de Auditoria', style: TextStyle(fontSize: 12)),
                onPressed: () {
                  showAuditLogSheet(
                    context: context,
                    entityId: expense.id,
                    title: 'Auditoria: ${expense.title}',
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetaRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      ],
    );
  }
}
