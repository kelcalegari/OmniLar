import 'package:flutter/material.dart';
import '../../../../core/domain/value_objects/money.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/entities/p2p_installment.dart';

class PartialPaymentDialog extends StatefulWidget {
  final P2PInstallment installment;
  final void Function(Money amount) onConfirm;

  const PartialPaymentDialog({
    super.key,
    required this.installment,
    required this.onConfirm,
  });

  static Future<void> show({
    required BuildContext context,
    required P2PInstallment installment,
    required void Function(Money amount) onConfirm,
  }) {
    return showDialog(
      context: context,
      builder: (_) => PartialPaymentDialog(
        installment: installment,
        onConfirm: onConfirm,
      ),
    );
  }

  @override
  State<PartialPaymentDialog> createState() => _PartialPaymentDialogState();
}

class _PartialPaymentDialogState extends State<PartialPaymentDialog> {
  final _amountController = TextEditingController();
  int _centsToPay = 0;
  bool _isFullPayment = true;

  @override
  void initState() {
    super.initState();
    _centsToPay = widget.installment.remainingAmount.cents;
    _amountController.text = (widget.installment.remainingAmount.cents / 100).toStringAsFixed(2).replaceAll('.', ',');
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  void _onAmountChanged(String val) {
    setState(() {
      _centsToPay = Money.parse(val).cents;
      _isFullPayment = _centsToPay == widget.installment.remainingAmount.cents;
    });
  }

  void _setFullPayment() {
    setState(() {
      _centsToPay = widget.installment.remainingAmount.cents;
      _isFullPayment = true;
      _amountController.text = (widget.installment.remainingAmount.cents / 100).toStringAsFixed(2).replaceAll('.', ',');
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
            'O valor não pode exceder o saldo restante da parcela (${widget.installment.remainingAmount.format()})',
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
              'Pagar Parcela ${widget.installment.number}/${widget.installment.totalCount}',
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
            const Text(
              'Quanto deseja pagar agora?',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                prefixText: 'R\$ ',
                hintText: '0,00',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                suffixIcon: !_isFullPayment
                    ? TextButton(
                        onPressed: _setFullPayment,
                        child: const Text('Total', style: TextStyle(fontWeight: FontWeight.bold)),
                      )
                    : null,
              ),
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
                        _amountController.text = (half / 100).toStringAsFixed(2).replaceAll('.', ',');
                      });
                    },
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _centsToPay < remaining.cents
                  ? '💡 Pagamento Parcial (RN02): A parcela continuará ativa com saldo restante de ${Money(remaining.cents - _centsToPay).format()}.'
                  : '✅ Esta parcela será 100% quitada.',
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
