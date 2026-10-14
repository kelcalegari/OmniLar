import '../../../../core/utils/clipboard_helper.dart';
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

  /// Código do boleto da fatura, para copiar e pagar no app do banco.
  final String? barcode;

  const CardInvoiceGroupTile({
    super.key,
    required this.invoice,
    required this.expanded,
    required this.onToggle,
    required this.children,
    this.onRegisterPayment,
    this.barcode,
  });

  static final _day = DateFormat('dd/MM');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final paidAt = invoice.paidAt;
    final overdue = invoice.isOverdue(DateTime.now());
    final count = invoice.purchases.length;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: paidAt != null
              ? Colors.orange.withValues(alpha: 0.35)
              : (overdue ? AppColors.debtRed : AppColors.folegoWarning).withValues(alpha: 0.5),
          width: paidAt != null ? 1 : 1.5,
        ),
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
                            'vence ${_day.format(invoice.dueDate)} • $count ${count == 1 ? 'compra' : 'compras'}',
                            style: theme.textTheme.bodySmall?.copyWith(fontSize: 11, color: Colors.grey),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            paidAt != null
                                ? 'Paga em ${_day.format(paidAt)}'
                                : (overdue ? 'Atrasada' : 'Em aberto'),
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: paidAt != null
                                  ? AppColors.creditGreen
                                  : (overdue ? AppColors.debtRed : AppColors.folegoWarning),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (paidAt == null && barcode != null)
                      IconButton(
                        key: Key('copy_invoice_code_${invoice.key}'),
                        tooltip: 'Copiar código do boleto',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.copy_rounded, size: 18),
                        onPressed: () => copyWithFeedback(
                          context,
                          barcode!,
                          onCopied: const SnackBar(content: Text('Código do boleto da fatura copiado.')),
                        ),
                      ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          invoice.total.format(),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: paidAt != null
                                ? null
                                : (overdue ? AppColors.debtRed : AppColors.folegoWarning),
                          ),
                        ),
                        if (paidAt == null && onRegisterPayment != null) ...[
                          const SizedBox(height: 4),
                          InkWell(
                            onTap: onRegisterPayment,
                            borderRadius: BorderRadius.circular(6),
                            child: Container(
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
                            ),
                          ),
                        ],
                      ],
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
                    if (onRegisterPayment != null)
                      Align(
                        alignment: Alignment.centerRight,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: TextButton.icon(
                            icon: const Icon(Icons.receipt_long_outlined, size: 18, color: AppColors.primary),
                            label: Text(paidAt == null ? 'Pagar a fatura' : 'Ver ou desfazer o pagamento'),
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
