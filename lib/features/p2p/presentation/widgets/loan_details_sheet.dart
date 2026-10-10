import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/entities/p2p_loan.dart';
import '../../domain/entities/p2p_installment.dart';
import '../cubit/p2p_cubit.dart';

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
        title: const Text('Perdoar Dívida?'),
        content: Text(
          'Deseja perdoar o saldo restante de ${loan.remainingAmount.format()} de "${loan.title}"?\n\nEssa ação é definitiva e isenta o devedor de futuros pagamentos.',
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

  void _payInstallment(BuildContext context, P2PInstallment installment) {
    context.read<P2PCubit>().payInstallment(installment.id, installment.remainingAmount);
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Parcela ${installment.number}/${installment.totalCount} paga com sucesso! ✅')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isForgiven = loan.status == LoanStatus.forgiven;
    final isPaid = loan.status == LoanStatus.paid;

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
          Text(
            'Parcelas (${loan.paidInstallmentsCount}/${loan.installmentsCount} pagas)',
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
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
                final dateFmt = DateFormat('dd/MM/yyyy').format(inst.dueDate);

                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    radius: 16,
                    backgroundColor: isInstPaid
                        ? AppColors.creditGreen.withValues(alpha: 0.15)
                        : (inst.status == InstallmentStatus.overdue
                            ? AppColors.debtRed.withValues(alpha: 0.15)
                            : Colors.grey.withValues(alpha: 0.15)),
                    child: Icon(
                      isInstPaid
                          ? Icons.check_rounded
                          : (inst.status == InstallmentStatus.overdue ? Icons.priority_high_rounded : Icons.access_time_rounded),
                      size: 16,
                      color: isInstPaid
                          ? AppColors.creditGreen
                          : (inst.status == InstallmentStatus.overdue ? AppColors.debtRed : Colors.grey),
                    ),
                  ),
                  title: Text(
                    'Parcela ${inst.number}/${inst.totalCount}',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      decoration: isInstPaid ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  subtitle: Text('Vence em $dateFmt'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        inst.amount.format(),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isInstPaid ? Colors.grey : null,
                        ),
                      ),
                      if (!isInstPaid && !isForgiven && isDebtor) ...[
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.payment_rounded, color: AppColors.primary),
                          tooltip: 'Pagar parcela',
                          onPressed: () => _payInstallment(context, inst),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),

          // Ações do Credor (Perdoar Dívida)
          if (!isDebtor && !isForgiven && !isPaid)
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
                label: const Text('Perdoar Dívida Restante', style: TextStyle(fontWeight: FontWeight.bold)),
                onPressed: () => _confirmForgive(context),
              ),
            ),
        ],
      ),
    );
  }
}
