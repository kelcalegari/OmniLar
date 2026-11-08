import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/entities/payment_method.dart';
import '../../domain/services/cycle_expense_grouping.dart';

/// Nota paga com mais de um meio de pagamento (0124) na lista de gastos do
/// ciclo: uma linha só, com o total e os meios; aberta, mostra cada parte.
/// Não muda as despesas; só as junta na tela.
class PaymentNoteTile extends StatelessWidget {
  final PaymentNoteEntry note;
  final Map<String, PaymentMethod> methods;
  final bool expanded;
  final VoidCallback onToggle;

  /// As partes, já montadas por quem usa a nota.
  final List<Widget> children;

  const PaymentNoteTile({
    super.key,
    required this.note,
    required this.methods,
    required this.expanded,
    required this.onToggle,
    required this.children,
  });

  static final _day = DateFormat('dd/MM');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final summary = [
      for (final part in note.parts)
        '${methods[part.paymentMethodId]?.name ?? 'Pix'} ${part.amount.format()}',
    ].join(' + ');

    return Container(
      key: Key('payment_note_${note.groupId}'),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.call_split_rounded,
                        color: AppColors.primary,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            note.title,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${_day.format(note.date)} • $summary${note.hasHiddenParts ? ' • o resto em outros ciclos' : ''}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 11,
                              color: Colors.grey,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          note.total.format(),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        Icon(
                          expanded
                              ? Icons.expand_less_rounded
                              : Icons.expand_more_rounded,
                          size: 20,
                          color: Colors.grey,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (expanded)
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 4),
                child: Column(children: children),
              ),
          ],
        ),
      ),
    );
  }
}
