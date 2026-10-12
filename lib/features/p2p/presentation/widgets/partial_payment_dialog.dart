import 'package:flutter/material.dart';
import '../../../../core/domain/value_objects/money.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/money_input_field.dart';
import '../../domain/entities/p2p_installment.dart';

class PartialPaymentDialog extends StatefulWidget {
  final P2PInstallment installment;
  final void Function(Money amount) onConfirm;

  /// Empréstimo sem prazo: o texto fala em "abater saldo" em vez de "pagar parcela".
  final bool isOpenEnded;

  const PartialPaymentDialog({
    super.key,
    required this.installment,
    required this.onConfirm,
    this.isOpenEnded = false,
  });

  static Future<void> show({
    required BuildContext context,
    required P2PInstallment installment,
    required void Function(Money amount) onConfirm,
    bool isOpenEnded = false,
  }) {
    return showDialog(
      context: context,
      builder: (_) => PartialPaymentDialog(
        installment: installment,
        onConfirm: onConfirm,
        isOpenEnded: isOpenEnded,
      ),
    );
  }

  @override
  State<PartialPaymentDialog> createState() => _PartialPaymentDialogState();
}

class _PartialPaymentDialogState extends State<PartialPaymentDialog> {
  int _centsToPay = 0;
  bool _isFullPayment = true;

  @override
  void initState() {
    super.initState();
    _centsToPay = widget.installment.remainingAmount.cents;
  }

  void _onAmountChanged(Money amount) {
    setState(() {
      _centsToPay = amount.cents;
      _isFullPayment = _centsToPay == widget.installment.remainingAmount.cents;
    });
  }

  void _setFullPayment() {
    setState(() {
      _centsToPay = widget.installment.remainingAmount.cents;
      _isFullPayment = true;
    });
  }

  void _submit() {
    if (_centsToPay <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe um valor maior que zero')),
      );
      return;
    }

    if (_centsToPay > widget.installment.remainingAmount.cents) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.isOpenEnded
                ? 'O valor não pode exceder o saldo devedor (${widget.installment.remainingAmount.format()})'
                : 'O valor não pode exceder o saldo restante da parcela (${widget.installment.remainingAmount.format()})',
          ),
        ),
      );
      return;
    }

    widget.onConfirm(Money(_centsToPay));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final remaining = widget.installment.remainingAmount;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.payments_rounded, color: AppColors.primary, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              widget.isOpenEnded
                  ? 'Abater do Saldo Devedor'
                  : 'Pagar Parcela ${widget.installment.number}/${widget.installment.totalCount}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.brightness == Brightness.dark ? Colors.white10 : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Saldo Restante:', style: TextStyle(fontWeight: FontWeight.w500)),
                  Text(
                    remaining.format(),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.debtRed),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            MoneyInputField(
              label: 'Quanto deseja pagar agora?',
              initialValue: Money(_centsToPay),
              onChanged: _onAmountChanged,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                ActionChip(
                  label: const Text('Quitar total'),
                  backgroundColor: _isFullPayment ? AppColors.primary.withValues(alpha: 0.15) : null,
                  onPressed: _setFullPayment,
                ),
                if (remaining.cents >= 2000)
                  ActionChip(
                    label: Text(Money(remaining.cents ~/ 2).format()),
                    onPressed: () {
                      final half = remaining.cents ~/ 2;
                      setState(() {
                        _centsToPay = half;
                        _isFullPayment = false;
                      });
                    },
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _centsToPay < remaining.cents
                  ? (widget.isOpenEnded
                      ? 'O saldo de ${Money(remaining.cents - _centsToPay).format()} continua em aberto, sem vencimento.'
                      : 'O valor restante de ${Money(remaining.cents - _centsToPay).format()} continuará em aberto nesta parcela.')
                  : (widget.isOpenEnded
                      ? 'O empréstimo será totalmente quitado com esta confirmação.'
                      : 'Esta parcela será totalmente quitada com esta confirmação.'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: _centsToPay < remaining.cents ? Colors.orange.shade800 : AppColors.creditGreen,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: _submit,
          child: const Text('Confirmar Pagamento'),
        ),
      ],
    );
  }
}
