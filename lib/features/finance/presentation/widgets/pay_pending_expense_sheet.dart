import 'bill_code_field.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/domain/value_objects/money.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/money_input_field.dart';
import '../../domain/entities/house_expense.dart';
import '../../domain/entities/house_member.dart';
import '../../domain/entities/payment_method.dart';
import '../../domain/services/credit_card_invoice_calculator.dart';
import '../../domain/services/expense_launch_defaults.dart';
import '../cubit/finance_cubit.dart';

/// Registra o pagamento de uma conta pendente: dia, valor (se variável) e o
/// meio de pagamento. Quem pagou sai do meio: da casa, a casa; de um morador,
/// o morador, que é reembolsado no fechamento; cartão, a conta entra na fatura.
class PayPendingExpenseSheet extends StatefulWidget {
  final HouseExpense expense;
  final FinanceCubit financeCubit;

  const PayPendingExpenseSheet({super.key, required this.expense, required this.financeCubit});

  @override
  State<PayPendingExpenseSheet> createState() => _PayPendingExpenseSheetState();
}

class _PayPendingExpenseSheetState extends State<PayPendingExpenseSheet> {
  static final _day = DateFormat('dd/MM/yyyy');

  late Money _amount = widget.expense.amount;

  /// Código do boleto como está agora (pode ser informado nesta tela).
  late String? _barcode = widget.expense.barcode;
  DateTime _paidOn = DateTime.now();
  late String? _methodId = _initialMethodId();
  bool _busy = false;

  List<PaymentMethod> get _methods => widget.financeCubit.state.paymentMethods;
  List<HouseMember> get _members => widget.financeCubit.state.members;

  /// O meio que a conta já tinha; sem ele, a conta da casa.
  String? _initialMethodId() {
    final methods = _methods;
    if (methods.any((m) => m.id == widget.expense.paymentMethodId)) return widget.expense.paymentMethodId;
    return ExpenseLaunchDefaults.houseAccount(methods)?.id ?? methods.firstOrNull?.id;
  }

  PaymentMethod? get _method => _methods.where((m) => m.id == _methodId).firstOrNull;

  String _who(PaymentMethod? method) {
    if (method == null) return '';
    final ownerId = method.ownerMemberId;
    final waits = !widget.expense.isRecurring &&
        ExpenseLaunchDefaults.waitsForInvoice(method, projectId: widget.expense.projectId);
    if (waits) {
      final due = CreditCardInvoiceCalculator.calculateInvoiceDueDate(
        purchaseDate: _paidOn,
        closingDay: method.closingDay!,
        dueDay: method.dueDay!,
      );
      return 'Entra na fatura de ${method.name} que vence em ${_day.format(due)} e fica em aberto até a fatura ser paga.';
    }
    if (ownerId == null || !ExpenseLaunchDefaults.paidOutOfPocket(method)) {
      return 'Paga pela casa: sai do caixa, sem reembolso.';
    }
    final name = _members.where((m) => m.id == ownerId).firstOrNull?.name.split(' ').first ?? 'o responsável';
    return 'Paga por $name, que é reembolsado no fechamento do ciclo.';
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _paidOn,
      firstDate: DateTime(_paidOn.year - 1),
      lastDate: DateTime.now(),
      helpText: 'Dia do pagamento',
    );
    if (picked != null) setState(() => _paidOn = DateTime(picked.year, picked.month, picked.day, 12));
  }

  /// Guarda o código na conta já, sem esperar o pagamento.
  Future<bool> _saveBarcode(String? line) async {
    final cubit = widget.financeCubit;
    final current = cubit.state.expenses.where((e) => e.id == widget.expense.id).firstOrNull ?? widget.expense;
    final ok = await cubit.updateExpense(current.copyWith(barcode: line, clearBarcode: line == null));
    if (!ok) return false;
    if (mounted) setState(() => _barcode = line);
    return true;
  }

  Future<void> _confirm() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final ok = await widget.financeCubit.payPendingExpense(
      widget.expense.copyWith(barcode: _barcode, clearBarcode: _barcode == null),
      paidOn: _paidOn,
      method: _method,
      amount: _amount,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) {
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: AppColors.debtRed,
          content: Text(widget.financeCubit.state.errorMessage ?? 'Não foi possível registrar o pagamento.'),
        ),
      );
      return;
    }
    navigator.pop();
    messenger.showSnackBar(SnackBar(content: Text('Pagamento de "${widget.expense.title}" registrado.')));
  }

  @override
  Widget build(BuildContext context) {
    final expense = widget.expense;
    final cycle = widget.financeCubit.cycleSchedule.cycleFor(_paidOn);
    final method = _method;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Pagar: ${expense.title}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            if (expense.dueDate != null)
              Text(
                'Vence em ${_day.format(expense.dueDate!)}${expense.isOverdue ? ' (atrasada ${expense.daysOverdue}d)' : ''}',
                style: TextStyle(fontSize: 13, color: expense.isOverdue ? AppColors.debtRed : Colors.grey),
              ),
            const SizedBox(height: 12),
            BillCodeField(
              code: _barcode,
              enabled: !_busy,
              onSave: _saveBarcode,
            ),
            const SizedBox(height: 16),
            if (expense.isVariable)
              MoneyInputField(
                label: 'Valor pago',
                initialValue: _amount,
                primaryColor: AppColors.primary,
                onChanged: (value) => setState(() => _amount = value),
              )
            else
              Text('Valor: ${expense.amount.format()}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.event_rounded, size: 18),
              label: Text('Pago em ${_day.format(_paidOn)}'),
              onPressed: _busy ? null : _pickDate,
            ),
            const SizedBox(height: 12),
            const Text('Meio de pagamento', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            DropdownButton<String>(
              key: const Key('pay_method'),
              isExpanded: true,
              value: _methodId,
              onChanged: _busy ? null : (id) => setState(() => _methodId = id),
              items: [
                for (final m in _methods)
                  DropdownMenuItem(
                    value: m.id,
                    child: Text(
                      m.ownerMemberId == null
                          ? '${m.name} (da casa)'
                          : '${m.name} (${_members.where((x) => x.id == m.ownerMemberId).firstOrNull?.name.split(' ').first ?? 'morador'})',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
            Text(_who(method), style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 8),
            Text(
              'Com essa data, a conta conta no ciclo ${cycle.label}.',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const Key('pay_confirm'),
              icon: const Icon(Icons.check_rounded),
              label: Text(_busy ? 'Aguarde...' : 'Registrar pagamento'),
              onPressed: _busy || method == null || _amount.cents <= 0 ? null : _confirm,
            ),
          ],
        ),
      ),
    );
  }
}
