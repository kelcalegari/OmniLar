import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/app_haptics.dart';
import 'package:omni_lar/features/assistant/domain/entities/assistant_message.dart';

class ConfirmationCardWidget extends StatelessWidget {
  final AssistantActionProposal proposal;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  const ConfirmationCardWidget({
    super.key,
    required this.proposal,
    required this.onConfirm,
    required this.onCancel,
  });

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
