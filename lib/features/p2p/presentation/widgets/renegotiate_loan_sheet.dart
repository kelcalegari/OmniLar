import 'package:flutter/material.dart';
import '../../../../core/domain/value_objects/money.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/entities/p2p_loan.dart';
import '../../domain/services/p2p_calculator.dart';

class RenegotiateLoanSheet extends StatefulWidget {
  final P2PLoan loan;
  final void Function(int newInstallmentsCount, DateTime newFirstDueDate) onConfirm;

  const RenegotiateLoanSheet({
    super.key,
    required this.loan,
    required this.onConfirm,
  });

  @override
  State<RenegotiateLoanSheet> createState() => _RenegotiateLoanSheetState();
}

class _RenegotiateLoanSheetState extends State<RenegotiateLoanSheet> {
  int _installmentsCount = 3;
  DateTime _firstDueDate = DateTime.now().add(const Duration(days: 30));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final remainingAmount = widget.loan.remainingAmount;
    final simulatedInstallments = P2PCalculator.generateInstallments(
      loanId: widget.loan.id,
      totalAmount: remainingAmount,
      installmentsCount: _installmentsCount,
      firstDueDate: _firstDueDate,
    );

    return SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.handshake_rounded, color: AppColors.accent, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Propor Novo Parcelamento',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        widget.loan.title,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: theme.brightness == Brightness.dark ? Colors.white10 : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Saldo Restante a Refinanciar:'),
                  Text(
                    remainingAmount.format(),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.debtRed),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Novo Número de Parcelas',
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Row(
              children: [1, 2, 3, 4, 6, 10, 12].map((count) {
                final isSelected = _installmentsCount == count;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: ChoiceChip(
                      label: Text('${count}x', style: const TextStyle(fontSize: 12)),
                      selected: isSelected,
                      selectedColor: AppColors.accent.withValues(alpha: 0.2),
                      onSelected: (selected) {
                        if (selected) {
                          setState(() {
                            _installmentsCount = count;
                          });
                        }
                      },
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            Text(
              'Primeiro Vencimento',
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.calendar_today_rounded, size: 18),
              label: Text(
                '${_firstDueDate.day.toString().padLeft(2, '0')}/${_firstDueDate.month.toString().padLeft(2, '0')}/${_firstDueDate.year}',
              ),
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _firstDueDate,
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (picked != null) {
                  setState(() {
                    _firstDueDate = picked;
                  });
                }
              },
            ),
            const SizedBox(height: 20),
            Text(
              'Prévia do Novo Cronograma de Pagamento',
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: theme.dividerColor),
                borderRadius: BorderRadius.circular(12),
              ),
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: simulatedInstallments.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, idx) {
                  final inst = simulatedInstallments[idx];
                  return ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      radius: 12,
                      backgroundColor: AppColors.accent.withValues(alpha: 0.15),
                      child: Text(
                        '${inst.number}',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.accent),
                      ),
                    ),
                    title: Text('Parcela ${inst.number} de ${inst.totalCount}'),
                    subtitle: Text(
                      '${inst.dueDate.day.toString().padLeft(2, '0')}/${inst.dueDate.month.toString().padLeft(2, '0')}/${inst.dueDate.year}',
                    ),
                    trailing: Text(
                      inst.amount.format(),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'As parcelas anteriores não pagas serão substituídas por este novo cronograma acordado.',
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.check_circle_outline_rounded),
                label: const Text('Confirmar Renegociação', style: TextStyle(fontWeight: FontWeight.bold)),
                onPressed: () {
                  widget.onConfirm(_installmentsCount, _firstDueDate);
                  Navigator.pop(context);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
