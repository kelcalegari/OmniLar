import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/domain/value_objects/financial_cycle.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/entities/card_invoice.dart';
import '../../domain/entities/payment_method.dart';
import '../../domain/repositories/finance_repository.dart';
import '../cubit/finance_cubit.dart';

/// Registra em que dia a fatura de um cartão foi paga. As compras daquela
/// fatura passam a contar no ciclo desse dia, e não no do vencimento.
class CardInvoicePaymentSheet extends StatefulWidget {
  final PaymentMethod card;
  final FinanceRepository repository;
  final FinanceCubit financeCubit;
  final int cycleStartDay;

  const CardInvoicePaymentSheet({
    super.key,
    required this.card,
    required this.repository,
    required this.financeCubit,
    required this.cycleStartDay,
  });

  @override
  State<CardInvoicePaymentSheet> createState() => _CardInvoicePaymentSheetState();
}

class _CardInvoicePaymentSheetState extends State<CardInvoicePaymentSheet> {
  static final _dayFormat = DateFormat('dd/MM/yyyy');

  late final Future<List<CardInvoice>> _invoices =
      widget.repository.getOpenCardInvoices(widget.card.id);
  CardInvoice? _selected;
  DateTime _paidOn = DateTime.now();
  bool _saving = false;

  FinancialCycle _cycleOf(DateTime date) =>
      FinancialCycle.fromDate(date: date, cycleStartDay: widget.cycleStartDay);

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _paidOn,
      firstDate: DateTime(_paidOn.year - 1),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _paidOn = picked);
  }

  Future<void> _save(CardInvoice invoice) async {
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    final ok = await widget.financeCubit.payCardInvoice(
      paymentMethodId: invoice.paymentMethodId,
      invoiceDueDate: invoice.dueDate,
      paidAt: _paidOn,
    );
    if (!mounted) return;

    if (ok) {
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Pagamento da fatura registrado em ${_dayFormat.format(_paidOn)}. '
            'As compras contam no ciclo ${_cycleOf(_paidOn).label}.',
          ),
        ),
      );
    } else {
      setState(() => _saving = false);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            widget.financeCubit.state.errorMessage ?? 'Não foi possível registrar o pagamento.',
          ),
          backgroundColor: AppColors.debtRed,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: FutureBuilder<List<CardInvoice>>(
          future: _invoices,
          builder: (context, snapshot) {
            final invoices = snapshot.data ?? const <CardInvoice>[];
            final selected = _selected ?? invoices.firstOrNull;

            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Pagamento da fatura • ${widget.card.name}',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                const Text(
                  'As compras de uma fatura contam no ciclo do vencimento. '
                  'Se você pagou antes, registre o dia: elas passam a contar no ciclo em que foram pagas.',
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
                const SizedBox(height: 16),
                if (snapshot.connectionState != ConnectionState.done)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (snapshot.hasError)
                  Text(
                    'Não foi possível carregar as faturas: ${snapshot.error}',
                    style: const TextStyle(color: AppColors.debtRed),
                  )
                else if (invoices.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text('Nenhuma fatura em aberto para este cartão.'),
                  )
                else ...[
                  for (final invoice in invoices)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        invoice == selected
                            ? Icons.radio_button_checked_rounded
                            : Icons.radio_button_off_rounded,
                        color: invoice == selected ? AppColors.primary : Colors.grey,
                      ),
                      title: Text(
                        'Vence em ${_dayFormat.format(invoice.dueDate)} • ${invoice.total.formatted}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        '${invoice.purchasesCount} ${invoice.purchasesCount == 1 ? 'compra' : 'compras'} • '
                        'hoje conta no ciclo ${_cycleOf(invoice.dueDate).label}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      onTap: () => setState(() => _selected = invoice),
                    ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _saving ? null : _pickDate,
                    icon: const Icon(Icons.event_rounded, size: 18),
                    label: Text('Paga em ${_dayFormat.format(_paidOn)}'),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Com essa data, a fatura conta no ciclo ${_cycleOf(_paidOn).label}.',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _saving || selected == null ? null : () => _save(selected),
                    child: Text(_saving ? 'Registrando...' : 'Registrar pagamento'),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}
