import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/services/cycle_expense_grouping.dart';

/// Fatura de um cartão na lista de gastos do ciclo: mostra o total e, aberta,
/// as compras dela. Não muda as despesas; só as junta na tela.
class CardInvoiceGroupTile extends StatelessWidget {
  final CardInvoiceEntry invoice;
  final bool expanded;
  final VoidCallback onToggle;

  /// Abre o registro do pagamento da fatura.
  final VoidCallback? onRegisterPayment;

  /// As compras da fatura, já montadas por quem usa o cartão.
  final List<Widget> children;

  const CardInvoiceGroupTile({
    super.key,
    required this.invoice,
    required this.expanded,
    required this.onToggle,
    required this.children,
    this.onRegisterPayment,
  });

  static final _day = DateFormat('dd/MM');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final paidAt = invoice.paidAt;
    final count = invoice.purchases.length;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.35)),
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
                        color: Colors.orange.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.credit_card_rounded, color: Colors.orange, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Fatura ${invoice.card.name}',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'vence ${_day.format(invoice.dueDate)} • $count compras',
                            style: theme.textTheme.bodySmall?.copyWith(fontSize: 11, color: Colors.grey),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            paidAt == null
                                ? 'Pagamento não registrado'
                                : 'Paga em ${_day.format(paidAt)}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: paidAt == null ? AppColors.folegoWarning : AppColors.creditGreen,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      invoice.total.format(),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    Icon(
                      expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                      color: Colors.grey,
                    ),
                  ],
                ),
              ),
            ),
            if (expanded) ...[
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ...children,
                    if (paidAt == null && onRegisterPayment != null)
                      Align(
                        alignment: Alignment.centerRight,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: TextButton.icon(
                            icon: const Icon(Icons.receipt_long_outlined, size: 18, color: AppColors.primary),
                            label: const Text('Registrar pagamento da fatura'),
                            onPressed: onRegisterPayment,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
