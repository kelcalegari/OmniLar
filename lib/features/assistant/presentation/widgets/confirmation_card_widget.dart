import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/app_haptics.dart';
import 'package:omni_lar/features/assistant/domain/entities/assistant_message.dart';

class ConfirmationCardWidget extends StatelessWidget {
  final AssistantActionProposal proposal;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;
  final ValueChanged<AssistantActionProposal>? onEdit;

  const ConfirmationCardWidget({
    super.key,
    required this.proposal,
    required this.onConfirm,
    required this.onCancel,
    this.onEdit,
  });

  void _showEditDialog(BuildContext context) {
    final titleKey = proposal.arguments.containsKey('title') ? 'title' : 'name';
    final initialTitle = proposal.arguments[titleKey]?.toString() ?? '';
    final initialCents = proposal.arguments['cents'] as int?;
    final initialPm = proposal.arguments['paymentMethodName']?.toString() ?? '';
    final initialQty = proposal.arguments['quantity']?.toString() ?? '';

    final titleController = TextEditingController(text: initialTitle);
    final amountController = TextEditingController(
      text: initialCents != null ? (initialCents / 100).toStringAsFixed(2).replaceAll('.', ',') : '',
    );
    final pmController = TextEditingController(text: initialPm);
    final qtyController = TextEditingController(text: initialQty);

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.edit_note_rounded, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(
                'Editar Proposta',
                style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(
                    labelText: 'Título / Descrição',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
                if (initialCents != null) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: amountController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Valor em Reais (R\$)',
                      prefixText: 'R\$ ',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                ],
                if (proposal.arguments.containsKey('paymentMethodName') || proposal.toolName.contains('Expense')) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: pmController,
                    decoration: const InputDecoration(
                      labelText: 'Meio de Pagamento',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                ],
                if (proposal.arguments.containsKey('quantity')) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: qtyController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Quantidade',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                final updatedArgs = Map<String, dynamic>.from(proposal.arguments);
                final newTitle = titleController.text.trim();
                if (newTitle.isNotEmpty) {
                  updatedArgs[titleKey] = newTitle;
                }

                if (initialCents != null) {
                  final rawAmount = amountController.text.replaceAll(',', '.').trim();
                  final parsedVal = double.tryParse(rawAmount) ?? (initialCents / 100);
                  updatedArgs['cents'] = (parsedVal * 100).round();
                }

                if (pmController.text.trim().isNotEmpty) {
                  updatedArgs['paymentMethodName'] = pmController.text.trim();
                }

                if (qtyController.text.trim().isNotEmpty) {
                  updatedArgs['quantity'] = double.tryParse(qtyController.text.trim()) ?? 1.0;
                }

                // Reconstrói a descrição legível
                String newDesc = proposal.description;
                if (updatedArgs.containsKey('cents')) {
                  final cents = updatedArgs['cents'] as int;
                  final formattedMoney = 'R\$ ${(cents / 100).toStringAsFixed(2).replaceAll('.', ',')}';
                  final pm = updatedArgs['paymentMethodName']?.toString();
                  newDesc = '$newTitle: $formattedMoney${pm != null ? " • Meio de pagamento: $pm" : ""}';
                } else if (newTitle.isNotEmpty) {
                  newDesc = newTitle;
                }

                final updatedProposal = proposal.copyWith(
                  arguments: updatedArgs,
                  description: newDesc,
                );

                Navigator.pop(ctx);
                onEdit?.call(updatedProposal);
              },
              child: const Text('Salvar'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isExecuted = proposal.status == AssistantActionStatus.executed;
    final isCancelled = proposal.status == AssistantActionStatus.cancelled;

    return Container(
      margin: const EdgeInsets.only(top: 10, bottom: 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isExecuted
            ? AppColors.creditGreen.withValues(alpha: 0.1)
            : isCancelled
                ? Colors.grey.withValues(alpha: 0.1)
                : theme.cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isExecuted
              ? AppColors.creditGreen.withValues(alpha: 0.3)
              : isCancelled
                  ? theme.dividerColor
                  : AppColors.primary.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isExecuted
                    ? Icons.check_circle_rounded
                    : isCancelled
                        ? Icons.cancel_outlined
                        : Icons.assignment_outlined,
                size: 20,
                color: isExecuted
                    ? AppColors.creditGreen
                    : isCancelled
                        ? Colors.grey
                        : AppColors.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  proposal.title,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
              if (proposal.isHighRisk && !isExecuted && !isCancelled)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.debtRed.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'Ação de Risco',
                    style: TextStyle(color: AppColors.debtRed, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            proposal.description,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: isCancelled ? Colors.grey : null,
              decoration: isCancelled ? TextDecoration.lineThrough : null,
            ),
          ),
          if (proposal.arguments['paymentMethodName'] != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.credit_card_rounded, size: 14, color: AppColors.primary),
                  const SizedBox(width: 6),
                  Text(
                    'Meio de pagamento: ${proposal.arguments['paymentMethodName']}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.primary),
                  ),
                ],
              ),
            ),
          ],
          if (!isExecuted && !isCancelled) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () {
                    AppHaptics.light();
                    onCancel();
                  },
                  child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
                ),
                if (onEdit != null) ...[
                  const SizedBox(width: 4),
                  TextButton.icon(
                    onPressed: () {
                      AppHaptics.light();
                      _showEditDialog(context);
                    },
                    icon: const Icon(Icons.edit_outlined, size: 14),
                    label: const Text('Editar'),
                  ),
                ],
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: () {
                    AppHaptics.medium();
                    onConfirm();
                  },
                  icon: const Icon(Icons.check_rounded, size: 16),
                  label: const Text('Confirmar'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
          ] else if (isExecuted) ...[
            const SizedBox(height: 8),
            const Row(
              children: [
                Icon(Icons.done_all_rounded, size: 14, color: AppColors.creditGreen),
                SizedBox(width: 4),
                Text('Gravado com sucesso no app', style: TextStyle(color: AppColors.creditGreen, fontSize: 12)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
