import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../../../core/domain/value_objects/money.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/responsive.dart';
import '../../domain/entities/p2p_loan.dart';
import '../../domain/services/installment_loan_groups.dart';
import '../cubit/p2p_cubit.dart';
import '../cubit/p2p_state.dart';
import 'loan_card.dart';

/// As parcelas de uma compra parcelada no cartão da Casa em um card só.
/// Cada parcela continua sendo um empréstimo (sai do Caixa do ciclo em que a
/// fatura vence): o card abre a lista delas, e cada uma abre o seu painel.
class InstallmentGroupCard extends StatelessWidget {
  final InstallmentLoanGroup group;
  final bool isDebtor;
  final bool showBothParties;

  const InstallmentGroupCard({
    super.key,
    required this.group,
    required this.isDebtor,
    this.showBothParties = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = group.progressPercentage;
    final settled = group.isSettled;
    final next = group.nextOpen;
    final counterpartyLabel = loanCounterpartyLabel(
      context,
      group.first,
      isDebtor: isDebtor,
      showBothParties: showBothParties,
    );
    final accent = isDebtor ? AppColors.debtRed : AppColors.creditGreen;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: InkWell(
          onTap: () => showInstallmentGroupDetails(
            context,
            group,
            isDebtor: isDebtor,
            showBothParties: showBothParties,
          ),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.credit_card_rounded, color: accent, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            group.title,
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Compra parcelada em ${group.purchaseInstallments}×',
                            style: theme.textTheme.bodySmall?.copyWith(fontSize: 12),
                          ),
                          Text(
                            counterpartyLabel,
                            style: theme.textTheme.bodySmall?.copyWith(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          group.remainingAmount.format(),
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: accent),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Total: ${group.totalAmount.format()}',
                          style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    backgroundColor: theme.brightness == Brightness.dark
                        ? Colors.white10
                        : Colors.black.withValues(alpha: 0.06),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      settled ? AppColors.creditGreen : AppColors.primary,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    if (group.awaitingApproval || group.awaitingAcceptance) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          group.awaitingApproval ? 'Aguardando aprovação' : 'Aguardando aceite',
                          style: const TextStyle(color: Colors.orange, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: Text(
                        '${group.paidCount}/${group.siblings.length} parcelas pagas (${(progress * 100).toInt()}%)'
                        '${next == null ? '' : ' • próxima ${DateFormat('dd/MM').format(next.firstDueDate)}'}',
                        style: theme.textTheme.bodySmall?.copyWith(fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (settled)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          'Quitado ✅',
                          style: TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      )
                    else
                      const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Parcelas',
                            style: TextStyle(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w600),
                          ),
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

/// Lista as parcelas da compra; tocar numa abre o painel do empréstimo dela
/// (pagar, aceitar, renegociar continuam por parcela).
Future<void> showInstallmentGroupDetails(
  BuildContext context,
  InstallmentLoanGroup group, {
  required bool isDebtor,
  bool showBothParties = false,
}) {
  return showAdaptiveModal(
    context: context,
    maxWidth: 580,
    child: BlocBuilder<P2PCubit, P2PState>(
      builder: (sheetContext, state) {
        // Lê as parcelas do estado para refletir pagamentos sem reabrir
        final current = [
          for (final l in group.siblings) state.allLoans.where((x) => x.id == l.id).firstOrNull ?? l,
        ];
        return _InstallmentGroupSheet(
          title: group.title,
          purchaseInstallments: group.purchaseInstallments,
          loans: current,
          isDebtor: isDebtor,
          showBothParties: showBothParties,
        );
      },
    ),
  );
}

class _InstallmentGroupSheet extends StatelessWidget {
  final String title;
  final int purchaseInstallments;
  final List<P2PLoan> loans;
  final bool isDebtor;
  final bool showBothParties;

  const _InstallmentGroupSheet({
    required this.title,
    required this.purchaseInstallments,
    required this.loans,
    required this.isDebtor,
    required this.showBothParties,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateFmt = DateFormat('dd/MM/yyyy');
    final open = loans.fold<int>(0, (acc, l) => acc + l.remainingAmount.cents);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(
            'Compra parcelada em $purchaseInstallments× no cartão da Casa. Cada parcela sai do Caixa '
            'do ciclo em que a fatura vence, então é paga e acompanhada separadamente.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Text(
            'Em aberto: ${Money(open).format()}',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          for (final l in loans)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                radius: 16,
                backgroundColor: (_settled(l) ? AppColors.creditGreen : AppColors.primary).withValues(alpha: 0.15),
                child: Text(
                  '${InstallmentLoanGroup.numberOf(l)}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: _settled(l) ? AppColors.creditGreen : AppColors.primary,
                  ),
                ),
              ),
              title: Text('Parcela ${InstallmentLoanGroup.numberOf(l)}/$purchaseInstallments'),
              subtitle: Text(
                _settled(l)
                    ? (l.status == LoanStatus.forgiven ? 'Perdoada' : 'Paga')
                    : '${l.awaitingAcceptance ? 'Aguardando aceite • ' : ''}Vence em ${dateFmt.format(l.firstDueDate)}',
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    (_settled(l) ? l.totalAmount : l.remainingAmount).format(),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const Icon(Icons.chevron_right_rounded),
                ],
              ),
              onTap: () => showLoanDetails(context, l, isDebtor: isDebtor),
            ),
        ],
      ),
    );
  }

  static bool _settled(P2PLoan l) =>
      l.status == LoanStatus.paid || l.status == LoanStatus.forgiven || l.remainingAmount.cents == 0;
}
