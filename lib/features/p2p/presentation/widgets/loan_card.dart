import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/responsive.dart';
import '../../domain/entities/p2p_loan.dart';
import 'loan_details_sheet.dart';

class LoanCard extends StatelessWidget {
  final P2PLoan loan;
  final bool isDebtor; // true se eu devo, false se me devem

  const LoanCard({
    super.key,
    required this.loan,
    required this.isDebtor,
  });

  void _showDetails(BuildContext context) {
    showAdaptiveModal(
      context: context,
      maxWidth: 580,
      child: LoanDetailsSheet(loan: loan, isDebtor: isDebtor),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPaid = loan.status == LoanStatus.paid;
    final isForgiven = loan.status == LoanStatus.forgiven;

    final progress = loan.progressPercentage;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: InkWell(
          onTap: () => _showDetails(context),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Linha Superior: Ícone + Título + Valor Restante
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: (isDebtor ? AppColors.debtRed : AppColors.creditGreen).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        isDebtor ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                        color: isDebtor ? AppColors.debtRed : AppColors.creditGreen,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            loan.title,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            isDebtor ? 'Credor: Carlos' : 'Devedor: Marina',
                            style: theme.textTheme.bodySmall?.copyWith(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          loan.remainingAmount.format(),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: isDebtor ? AppColors.debtRed : AppColors.creditGreen,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Total: ${loan.totalAmount.format()}',
                          style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Barra de Progresso
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    backgroundColor: theme.brightness == Brightness.dark
                        ? Colors.white10
                        : Colors.black.withValues(alpha: 0.06),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      isPaid || isForgiven ? AppColors.creditGreen : AppColors.primary,
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // Rodapé: Parcelas Pagas e Status
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${loan.paidInstallmentsCount}/${loan.installmentsCount} parcelas pagas (${(progress * 100).toInt()}%)',
                      style: theme.textTheme.bodySmall?.copyWith(fontSize: 12),
                    ),
                    if (isForgiven)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.creditGreen.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text('Perdoado 🎉', style: TextStyle(color: AppColors.creditGreen, fontSize: 11, fontWeight: FontWeight.bold)),
                      )
                    else if (isPaid)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text('Quitado ✅', style: TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.bold)),
                      )
                    else
                      const Row(
                        children: [
                          Text('Ver parcelas', style: TextStyle(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w600)),
                          Icon(Icons.chevron_right_rounded, size: 16, color: AppColors.primary),
                        ],
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
