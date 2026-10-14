import '../../../../core/domain/value_objects/cycle_schedule.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/domain/value_objects/financial_cycle.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/entities/card_invoice.dart';
import '../../domain/entities/payment_method.dart';
import '../../domain/repositories/finance_repository.dart';
import '../cubit/finance_cubit.dart';

/// Registra (ou desfaz) o dia em que a fatura de um cartão foi paga. As compras
/// daquela fatura contam no ciclo desse dia, e não no do vencimento.
class CardInvoicePaymentSheet extends StatefulWidget {
  final PaymentMethod card;
  final FinanceRepository repository;
  final FinanceCubit financeCubit;
  /// Calendário de ciclos da casa (sabe das trocas do dia de início).
  final CycleSchedule cycleSchedule;

  /// Informa se o ciclo já foi fechado: mexer em fatura de ciclo fechado
  /// tiraria as compras de um acerto já feito ou as cobraria duas vezes.
  final Future<bool> Function(FinancialCycle cycle) isCycleClosed;

  /// Vencimento da fatura que já vem escolhida (a aberta pela Casa).
  final DateTime? initialDueDate;

  /// Nomes dos moradores, para dizer de quem é o bolso.
  final Map<String, String> memberNames;

  const CardInvoicePaymentSheet({
    super.key,
    required this.card,
    required this.repository,
    required this.financeCubit,
    required this.cycleSchedule,
    required this.isCycleClosed,
    this.initialDueDate,
    this.memberNames = const {},
  });

  @override
  State<CardInvoicePaymentSheet> createState() => _CardInvoicePaymentSheetState();
}

class _CardInvoicePaymentSheetState extends State<CardInvoicePaymentSheet> {
  static final _dayFormat = DateFormat('dd/MM/yyyy');

  late Future<({List<CardInvoice> open, List<CardInvoice> paid})> _invoices = _load();
  CardInvoice? _selected;
  DateTime _paidOn = DateTime.now();
  bool _busy = false;

  /// A fatura saiu do Caixa da Casa (cartão sem dono sempre sai do Caixa).
  late bool _paidByHouse = widget.card.ownerMemberId == null;

  Future<({List<CardInvoice> open, List<CardInvoice> paid})> _load() async {
    final open = await widget.repository.getOpenCardInvoices(widget.card.id);
    final paid = await widget.repository.getPaidCardInvoices(widget.card.id);
    return (open: open, paid: paid);
  }

  FinancialCycle _cycleOf(DateTime date) => widget.cycleSchedule.cycleFor(date);

  /// Primeiro ciclo já fechado entre [dates], ou null se todos estão abertos.
  Future<FinancialCycle?> _firstClosedCycle(List<DateTime> dates) async {
    for (final cycle in dates.map(_cycleOf).toSet()) {
      if (await widget.isCycleClosed(cycle)) return cycle;
    }
    return null;
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.debtRed),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _paidOn,
      firstDate: DateTime(_paidOn.year - 1),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _paidOn = picked);
  }

  Future<void> _run({
    required List<DateTime> affectedDates,
    required Future<bool> Function() action,
    required String successMessage,
    required bool closeOnSuccess,
  }) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    try {
      final closedCycle = await _firstClosedCycle(affectedDates);
      if (!mounted) return;
      if (closedCycle != null) {
        _showError(
          'O ciclo ${closedCycle.label} já foi fechado. Reabra esse ciclo no '
          'Fechamento para alterar o pagamento desta fatura.',
        );
        return;
      }

      final ok = await action();
      if (!mounted) return;
      if (!ok) {
        _showError(
          widget.financeCubit.state.errorMessage ?? 'Não foi possível concluir a operação.',
        );
        return;
      }

      messenger.showSnackBar(SnackBar(content: Text(successMessage)));
      if (closeOnSuccess) {
        navigator.pop();
      } else {
        setState(() {
          _selected = null;
          _invoices = _load();
        });
      }
    } catch (e) {
      if (mounted) _showError('Não foi possível verificar o ciclo: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save(CardInvoice invoice) => _run(
    // Nem o ciclo de onde as compras saem nem o de destino podem estar fechados
    affectedDates: [invoice.dueDate, _paidOn],
    action: () => widget.financeCubit.payCardInvoice(
      paymentMethodId: invoice.paymentMethodId,
      invoiceDueDate: invoice.dueDate,
      paidAt: _paidOn,
      paidByHouse: _paidByHouse,
    ),
    successMessage:
        'Pagamento da fatura registrado em ${_dayFormat.format(_paidOn)}. '
        'As compras contam no ciclo ${_cycleOf(_paidOn).label}.',
    closeOnSuccess: true,
  );

  Future<void> _undo(CardInvoice invoice) => _run(
    affectedDates: [invoice.dueDate, invoice.paidAt!],
    action: () => widget.financeCubit.undoCardInvoicePayment(
      paymentMethodId: invoice.paymentMethodId,
      invoiceDueDate: invoice.dueDate,
    ),
    successMessage:
        'Pagamento desfeito. As compras voltam a contar no ciclo '
        '${_cycleOf(invoice.dueDate).label}.',
    closeOnSuccess: false,
  );

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: FutureBuilder<({List<CardInvoice> open, List<CardInvoice> paid})>(
          future: _invoices,
          builder: (context, snapshot) {
            final open = snapshot.data?.open ?? const <CardInvoice>[];
            final paid = snapshot.data?.paid ?? const <CardInvoice>[];
            final initial = widget.initialDueDate;
            final selected = _selected ??
                (initial == null
                    ? null
                    : open
                        .where((i) =>
                            i.dueDate.year == initial.year &&
                            i.dueDate.month == initial.month &&
                            i.dueDate.day == initial.day)
                        .firstOrNull) ??
                open.firstOrNull;
            final owner = widget.memberNames[widget.card.ownerMemberId] ?? 'titular';

            return SingleChildScrollView(
              child: Column(
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
                  else ...[
                    if (open.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text('Nenhuma fatura em aberto para este cartão.'),
                      )
                    else ...[
                      for (final invoice in open)
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
                          onTap: _busy ? null : () => setState(() => _selected = invoice),
                        ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _pickDate,
                        icon: const Icon(Icons.event_rounded, size: 18),
                        label: Text('Paga em ${_dayFormat.format(_paidOn)}'),
                      ),
                      if (widget.card.ownerMemberId != null) ...[
                        const SizedBox(height: 12),
                        const Text('Com que dinheiro?', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                        RadioGroup<bool>(
                          groupValue: _paidByHouse,
                          onChanged: (value) {
                            if (!_busy && value != null) setState(() => _paidByHouse = value);
                          },
                          child: Column(
                            children: [
                              RadioListTile<bool>(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                value: false,
                                title: Text('Do bolso de $owner'),
                                subtitle: const Text('É reembolsado no fechamento do ciclo'),
                              ),
                              const RadioListTile<bool>(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                value: true,
                                title: Text('Caixa da Casa'),
                                subtitle: Text('Sai do caixa, sem reembolso. Em fatura importada, os gastos pessoais e os de outros moradores viram dívida com o Caixa.'),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Text(
                        'Com essa data, a fatura conta no ciclo ${_cycleOf(_paidOn).label}.',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: _busy || selected == null ? null : () => _save(selected),
                        child: Text(_busy ? 'Aguarde...' : 'Registrar pagamento'),
                      ),
                    ],
                    if (paid.isNotEmpty) ...[
                      const Divider(height: 32),
                      const Text(
                        'Pagamentos registrados',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      for (final invoice in paid)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            'Vence em ${_dayFormat.format(invoice.dueDate)} • ${invoice.total.formatted}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            'Paga em ${_dayFormat.format(invoice.paidAt!)} • '
                            'conta no ciclo ${_cycleOf(invoice.paidAt!).label}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          trailing: TextButton(
                            onPressed: _busy ? null : () => _undo(invoice),
                            child: const Text('Desfazer'),
                          ),
                        ),
                    ],
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
