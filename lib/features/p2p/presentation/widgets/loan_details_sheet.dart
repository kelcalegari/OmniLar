import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/responsive.dart';
import '../../domain/entities/p2p_loan.dart';
import '../../domain/entities/p2p_installment.dart';
import '../cubit/p2p_cubit.dart';
import 'partial_payment_dialog.dart';
import 'renegotiate_loan_sheet.dart';

class LoanDetailsSheet extends StatelessWidget {
  final P2PLoan loan;
  final bool isDebtor; // Se o usuário logado é quem deve

  const LoanDetailsSheet({
    super.key,
    required this.loan,
    required this.isDebtor,
  });

  void _confirmForgive(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Perdoar Dívida? (RN03)'),
        content: Text(
          'Deseja perdoar o saldo restante de ${loan.remainingAmount.format()} de "${loan.title}"?\n\nEssa ação é definitiva e isenta o devedor de futuros pagamentos. O histórico permanece registrado com status "Perdoado".',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.creditGreen,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              context.read<P2PCubit>().forgiveLoan(loan.id);
              Navigator.pop(ctx);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Dívida perdoada com sucesso! 🎉')),
              );
            },
            child: const Text('Sim, Perdoar'),
          ),
        ],
      ),
    );
  }

  void _openPaymentDialog(BuildContext context, P2PInstallment installment) {
    PartialPaymentDialog.show(
      context: context,
      installment: installment,
      onConfirm: (amount) {
        context.read<P2PCubit>().payInstallment(installment.id, amount);
        Navigator.pop(context); // Fecha a sheet para recarregar ou ver o estado atualizado
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              amount.cents == installment.remainingAmount.cents
                  ? 'Parcela ${installment.number}/${installment.totalCount} quitada com sucesso! ✅'
                  : 'Pagamento parcial de ${amount.format()} registrado! Saldo atualizado. 🪙',
            ),
          ),
        );
      },
    );
  }

  void _openRenegotiateSheet(BuildContext context) {
    showAdaptiveModal(
      context: context,
      maxWidth: 540,
      child: RenegotiateLoanSheet(
        loan: loan,
        onConfirm: (newCount, newFirstDate) {
          context.read<P2PCubit>().renegotiateLoan(loan.id, newCount, newFirstDate);
          Navigator.pop(context); // Fecha os detalhes
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Empréstimo renegociado em $newCount parcelas! 🤝'),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isForgiven = loan.status == LoanStatus.forgiven;
    final isPaid = loan.status == LoanStatus.paid;
    final isRenegotiated = loan.status == LoanStatus.renegotiated;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Título e Status
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  loan.title,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
              if (isForgiven)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.creditGreen.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text('Perdoado 🎉', style: TextStyle(color: AppColors.creditGreen, fontWeight: FontWeight.bold)),
                )
              else if (isPaid)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text('Quitado ✅', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
                )
              else if (isRenegotiated)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text('Renegociado 🤝', style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.bold)),
                ),
            ],
          ),
          if (loan.description != null && loan.description!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(loan.description!, style: theme.textTheme.bodySmall),
          ],
          const SizedBox(height: 16),

          // Card de Resumo do Empréstimo
          Card(
            color: theme.brightness == Brightness.dark ? AppColors.surfaceDark : AppColors.backgroundLight,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Valor Total', style: theme.textTheme.bodySmall),
                      Text(loan.totalAmount.format(), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('Saldo Restante', style: theme.textTheme.bodySmall),
                      Text(
                        loan.remainingAmount.format(),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isDebtor ? AppColors.debtRed : AppColors.creditGreen,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Lista de Parcelas
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Parcelas (${loan.paidInstallmentsCount}/${loan.installmentsCount} pagas)',
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              if (!isPaid && !isForgiven && loan.remainingAmount.cents > 0)
                TextButton.icon(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: AppColors.accent,
                  ),
                  icon: const Icon(Icons.handshake_rounded, size: 16),
                  label: const Text('Renegociar (RN04)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  onPressed: () => _openRenegotiateSheet(context),
                ),
            ],
          ),
          const SizedBox(height: 8),

          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: loan.installments.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final inst = loan.installments[index];
                final isInstPaid = inst.isFullyPaid;
                final isInstPartial = inst.status == InstallmentStatus.partiallyPaid;
                final isInstCancelled = inst.isCancelled;
                final dateFmt = DateFormat('dd/MM/yyyy').format(inst.dueDate);

                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    radius: 16,
                    backgroundColor: isInstPaid
                        ? AppColors.creditGreen.withValues(alpha: 0.15)
                        : (isInstPartial
                            ? Colors.orange.withValues(alpha: 0.15)
                            : (inst.status == InstallmentStatus.overdue
                                ? AppColors.debtRed.withValues(alpha: 0.15)
                                : Colors.grey.withValues(alpha: 0.15))),
                    child: Icon(
                      isInstPaid
                          ? Icons.check_rounded
                          : (isInstPartial
                              ? Icons.pie_chart_outline_rounded
                              : (inst.status == InstallmentStatus.overdue ? Icons.priority_high_rounded : Icons.access_time_rounded)),
                      size: 16,
                      color: isInstPaid
                          ? AppColors.creditGreen
                          : (isInstPartial
                              ? Colors.orange
                              : (inst.status == InstallmentStatus.overdue ? AppColors.debtRed : Colors.grey)),
                    ),
                  ),
                  title: Text(
                    'Parcela ${inst.number}/${inst.totalCount}' + (isInstCancelled ? ' (Cancelada)' : ''),
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      decoration: isInstPaid || isInstCancelled ? TextDecoration.lineThrough : null,
                      color: isInstCancelled ? Colors.grey : null,
                    ),
                  ),
                  subtitle: isInstCancelled
                      ? const Text('Substituída na renegociação')
                      : isInstPartial
                          ? Text(
                              'Pago: ${inst.paidAmount.format()} | Resta: ${inst.remainingAmount.format()}',
                              style: const TextStyle(color: Colors.orange, fontSize: 12),
                            )
                          : Text('Vence em $dateFmt'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            inst.amount.format(),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: isInstPaid || isInstCancelled ? Colors.grey : null,
                            ),
                          ),
                          if (isInstPartial)
                            Text(
                              'Parcial (RN02)',
                              style: TextStyle(fontSize: 10, color: Colors.orange.shade800, fontWeight: FontWeight.bold),
                            ),
                        ],
                      ),
                      if (!isInstPaid && !isForgiven && !isInstCancelled && isDebtor) ...[
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.payment_rounded, color: AppColors.primary),
                          tooltip: 'Pagar ou abater parcela',
                          onPressed: () => _openPaymentDialog(context, inst),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),

          // Ações do Credor (Perdoar Dívida - RN03)
          if (!isDebtor && !isForgiven && !isPaid && loan.remainingAmount.cents > 0)
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.creditGreen,
                  side: const BorderSide(color: AppColors.creditGreen),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.volunteer_activism_rounded),
                label: const Text('Perdoar Dívida Restante (RN03)', style: TextStyle(fontWeight: FontWeight.bold)),
                onPressed: () => _confirmForgive(context),
              ),
            ),
        ],
      ),
    );
  }
}
