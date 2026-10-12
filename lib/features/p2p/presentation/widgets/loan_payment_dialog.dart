import 'package:flutter/material.dart';
import '../../../../core/domain/value_objects/money.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/money_input_field.dart';
import '../../domain/entities/p2p_loan.dart';

/// Abatimento livre de um empréstimo parcelado: o valor informado é distribuído
/// das parcelas mais antigas para as mais novas (antecipa quantas couberem).
class LoanPaymentDialog extends StatefulWidget {
  final P2PLoan loan;
  final void Function(Money amount) onConfirm;

  const LoanPaymentDialog({
    super.key,
    required this.loan,
    required this.onConfirm,
  });

  static Future<void> show({
    required BuildContext context,
    required P2PLoan loan,
    required void Function(Money amount) onConfirm,
  }) {
    return showDialog(
      context: context,
      builder: (_) => LoanPaymentDialog(loan: loan, onConfirm: onConfirm),
    );
  }

  @override
  State<LoanPaymentDialog> createState() => _LoanPaymentDialogState();
}

class _LoanPaymentDialogState extends State<LoanPaymentDialog> {
  late final int _remainingCents;
  late final int _nextInstallmentCents;
  late int _centsToPay;

  @override
  void initState() {
    super.initState();
    _remainingCents = widget.loan.remainingAmount.cents;
    final open = widget.loan.openInstallments;
    _nextInstallmentCents = open.isNotEmpty ? open.first.remainingAmount.cents : _remainingCents;
    _centsToPay = _nextInstallmentCents;
  }

  /// Quantas parcelas ficam totalmente quitadas com o valor informado.
  int get _installmentsCovered {
    int left = _centsToPay;
    int covered = 0;
    for (final inst in widget.loan.openInstallments) {
      if (left < inst.remainingAmount.cents) break;
      left -= inst.remainingAmount.cents;
      covered++;
    }
    return covered;
  }

  void _submit() {
    if (_centsToPay <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe um valor maior que zero')),
      );
      return;
    }

    if (_centsToPay > _remainingCents) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('O valor não pode exceder o saldo devedor (${Money(_remainingCents).format()})'),
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
    final isFull = _centsToPay == _remainingCents;
    final covered = _installmentsCovered;

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
            child: const Icon(Icons.fast_forward_rounded, color: AppColors.primary, size: 22),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Antecipar ou Abater',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
                  const Text('Saldo Devedor:', style: TextStyle(fontWeight: FontWeight.w500)),
                  Text(
                    Money(_remainingCents).format(),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.debtRed),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            MoneyInputField(
              label: 'Quanto deseja pagar agora?',
              initialValue: Money(_centsToPay),
              onChanged: (amount) => setState(() => _centsToPay = amount.cents),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                if (_nextInstallmentCents < _remainingCents)
                  ActionChip(
                    label: Text('Próxima parcela (${Money(_nextInstallmentCents).format()})'),
                    backgroundColor:
                        _centsToPay == _nextInstallmentCents ? AppColors.primary.withValues(alpha: 0.15) : null,
                    onPressed: () => setState(() => _centsToPay = _nextInstallmentCents),
                  ),
                ActionChip(
                  label: const Text('Quitar tudo'),
                  backgroundColor: isFull ? AppColors.primary.withValues(alpha: 0.15) : null,
                  onPressed: () => setState(() => _centsToPay = _remainingCents),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              isFull
                  ? 'O empréstimo será totalmente quitado com esta confirmação.'
                  : covered > 0
                      ? 'Quita $covered ${covered == 1 ? 'parcela' : 'parcelas'}, começando pelas mais antigas. '
                          'Resta ${Money(_remainingCents - _centsToPay).format()} em aberto.'
                      : 'Abate da parcela mais antiga. Resta ${Money(_remainingCents - _centsToPay).format()} em aberto.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: isFull ? AppColors.creditGreen : Colors.orange.shade800,
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
