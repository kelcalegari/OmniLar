import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../core/domain/value_objects/money.dart';
import '../../../../core/security/biometric_auth_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/responsive.dart';
import '../../domain/entities/p2p_loan.dart';
import '../../domain/entities/p2p_installment.dart';
import '../../domain/entities/p2p_payment_record.dart';
import '../../domain/repositories/p2p_repository.dart';
import '../../../auth/domain/repositories/auth_repository.dart';
import '../../../finance/domain/entities/house_member.dart';
import '../../../finance/domain/entities/savings_vault.dart';
import '../../../finance/presentation/cubit/finance_cubit.dart';
import '../../../reconciliation/domain/repositories/import_repository.dart';
import '../cubit/p2p_cubit.dart';
import 'loan_payment_dialog.dart';
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

  /// Aguarda a ação no servidor e só então confirma ao usuário. O painel continua
  /// aberto e se atualiza sozinho, a menos que [closeOnSuccess] seja true.
  Future<void> _runAction(
    BuildContext context,
    Future<bool> Function(P2PCubit cubit) action, {
    required String successMessage,
    bool closeOnSuccess = false,
  }) async {
    final cubit = context.read<P2PCubit>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    final ok = await action(cubit);
    if (ok) {
      if (closeOnSuccess && context.mounted) navigator.pop(); // Fecha o painel
      messenger.showSnackBar(SnackBar(content: Text(successMessage)));
      return;
    }

    final message = cubit.state.errorMessage ?? 'Não foi possível concluir a operação.';
    if (context.mounted) {
      // Diálogo, e não snackbar: o painel aberto cobriria a mensagem de erro.
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Não foi possível concluir'),
          content: Text(message),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
          ],
        ),
      );
    } else {
      messenger.showSnackBar(SnackBar(content: Text(message), backgroundColor: AppColors.debtRed));
    }
  }

  /// Quem pode registrar pagamento: o devedor, o credor (dar baixa no que recebeu)
  /// ou um administrador quando o credor é o Caixa da Casa.
  bool _canRegisterPayment(BuildContext context) {
    if (isDebtor) return true;
    final currentUserId = context.read<P2PCubit>().state.currentUserId;
    if (currentUserId.isEmpty) return false;
    if (loan.lenderMemberId == currentUserId) return true;
    if (loan.isHouseLender) {
      try {
        final me = context.read<FinanceCubit>().state.members.where((m) => m.id == currentUserId).firstOrNull;
        return me != null && (me.role == 'owner' || me.role == 'admin');
      } catch (_) {}
    }
    return false;
  }

  /// Quem pode excluir: quem emprestou ou um administrador da casa (no acordo
  /// com o Caixa, só o administrador), e só enquanto nada foi pago. O devedor
  /// não apaga a própria dívida. Sem identificar o usuário (modo demo), nada é escondido.
  bool _canDelete(BuildContext context) {
    if (loan.totalPaidAmount.cents > 0) return false;
    final currentUserId = context.read<P2PCubit>().state.currentUserId;
    if (currentUserId.isEmpty) return true;
    if (!loan.isHouseLender && loan.lenderMemberId == currentUserId) return true;
    try {
      final members = context.read<FinanceCubit>().state.members;
      final me = members.where((m) => m.id == currentUserId).firstOrNull;
      if (me == null) return members.isEmpty;
      return me.role == 'owner' || me.role == 'admin';
    } catch (_) {
      return true;
    }
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir Empréstimo?'),
        content: Text(
          'Deseja excluir permanentemente o empréstimo "${loan.title}"?\n\nEsta ação apagará todas as parcelas associadas e atualizará os saldos.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.debtRed,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _runAction(
                context,
                (cubit) => cubit.deleteLoan(loan.id),
                successMessage: 'Empréstimo excluído com sucesso.',
                closeOnSuccess: true,
              );
            },
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
  }

  void _confirmForgive(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Perdoar Restante da Dívida?'),
        content: Text(
          'Deseja perdoar o saldo restante de ${loan.remainingAmount.format()} de "${loan.title}"?\n\nEsta ação isenta a outra pessoa de novos pagamentos deste empréstimo e mantém o histórico preservado.',
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
            onPressed: () async {
              Navigator.pop(ctx);

              final authService = sl<BiometricAuthService>();
              final authenticated = await authService.authenticate(
                reason: 'Confirme sua identidade para perdoar este empréstimo.',
              );

              if (!authenticated) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Autenticação não confirmada. Perdão de dívida cancelado.'),
                      backgroundColor: AppColors.debtRed,
                    ),
                  );
                }
                return;
              }

              if (context.mounted) {
                await _runAction(
                  context,
                  (cubit) => cubit.forgiveLoan(loan.id),
                  successMessage: 'Dívida perdoada com sucesso! 🎉',
                );
              }
            },
            child: const Text('Sim, Perdoar'),
          ),
        ],
      ),
    );
  }

  /// Acordo com o Lar pago fora do fechamento: o valor é guardado em uma
  /// Caixinha. Devolve a escolhida, null quando não se aplica (credor é um
  /// morador, reposição que já tem Caixinha de origem ou casa sem Caixinhas).
  /// [proceed] é false quando o usuário desistiu.
  Future<({bool proceed, String? vaultId})> _pickDestinationVault(BuildContext context) async {
    if (!loan.isHouseLender || loan.repayToVaultId != null) {
      return (proceed: true, vaultId: null);
    }
    var vaults = <SavingsVault>[];
    try {
      vaults = context.read<FinanceCubit>().state.savingsVaults;
    } catch (_) {}
    if (vaults.isEmpty) return (proceed: true, vaultId: null);

    var selectedId = vaults
            .where((v) => v.name == 'Reserva da Casa')
            .firstOrNull
            ?.id ??
        vaults.first.id;
    final chosen = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Guardar em qual Caixinha?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Este acordo é com o Caixa da Casa. O valor pago agora, fora do fechamento, fica guardado na Caixinha escolhida.',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: selectedId,
                decoration: const InputDecoration(
                  labelText: 'Caixinha',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final v in vaults)
                    DropdownMenuItem(value: v.id, child: Text(v.name)),
                ],
                onChanged: (val) {
                  if (val != null) setDialogState(() => selectedId = val);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, selectedId),
              child: const Text('Continuar'),
            ),
          ],
        ),
      ),
    );
    return (proceed: chosen != null, vaultId: chosen);
  }

  /// O saldo da Caixinha mudou junto com o pagamento: atualiza o painel financeiro.
  void _refreshFinance(BuildContext context) {
    try {
      context.read<FinanceCubit>().loadCycleData();
    } catch (_) {}
  }

  Future<void> _openPaymentDialog(BuildContext context, P2PInstallment installment) async {
    final destination = await _pickDestinationVault(context);
    if (!destination.proceed || !context.mounted) return;
    PartialPaymentDialog.show(
      context: context,
      installment: installment,
      isOpenEnded: loan.isOpenEnded,
      onConfirm: (amount) async {
        await _runAction(
          context,
          (cubit) => cubit.payInstallment(
            installment.id,
            amount,
            vaultId: destination.vaultId,
          ),
          successMessage: loan.isOpenEnded
              ? (amount.cents == installment.remainingAmount.cents
                  ? 'Empréstimo quitado! ✅'
                  : 'Abatimento de ${amount.format()} registrado! Saldo atualizado. 🪙')
              : amount.cents == installment.remainingAmount.cents
                  ? 'Parcela ${installment.number}/${installment.totalCount} quitada com sucesso! ✅'
                  : 'Pagamento parcial de ${amount.format()} registrado! Saldo atualizado. 🪙',
        );
        if (context.mounted) _refreshFinance(context);
      },
    );
  }

  /// Abatimento livre no empréstimo parcelado (antecipa das parcelas mais antigas para as mais novas).
  Future<void> _openLoanPaymentDialog(BuildContext context) async {
    final destination = await _pickDestinationVault(context);
    if (!destination.proceed || !context.mounted) return;
    LoanPaymentDialog.show(
      context: context,
      loan: loan,
      onConfirm: (amount) async {
        await _runAction(
          context,
          (cubit) => cubit.payLoan(loan.id, amount, vaultId: destination.vaultId),
          successMessage: amount.cents == loan.remainingAmount.cents
              ? 'Empréstimo quitado! ✅'
              : 'Pagamento de ${amount.format()} registrado! Saldo atualizado. 🪙',
        );
        if (context.mounted) _refreshFinance(context);
      },
    );
  }

  /// Aviso de como o empréstimo parcelado é cobrado, com a opção de tirá-lo do ciclo.
  Widget _buildCycleChargePanel(BuildContext context, {required bool canChange}) {
    final inCycle = loan.settleInCycle;
    return Container(
      padding: const EdgeInsets.only(left: 12, right: 4, top: 4, bottom: 4),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            inCycle ? Icons.event_repeat_rounded : Icons.event_busy_rounded,
            size: 18,
            color: AppColors.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                inCycle
                    ? 'Cobrado no Fechamento do Ciclo: cada parcela entra no ciclo em que vence. Dá para antecipar quando quiser.'
                    : 'Fora do Fechamento do Ciclo: as datas são só lembrete e o pagamento é sempre manual.',
                style: const TextStyle(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          if (canChange)
            Switch(
              value: inCycle,
              onChanged: (value) => _runAction(
                context,
                (cubit) => cubit.setSettleInCycle(loan.id, value),
                successMessage: value
                    ? 'As parcelas voltam a ser cobradas no Fechamento do Ciclo.'
                    : 'Empréstimo fora do Fechamento do Ciclo: o pagamento passa a ser manual.',
              ),
            ),
        ],
      ),
    );
  }

  void _openRenegotiateSheet(BuildContext context) {
    showAdaptiveModal(
      context: context,
      maxWidth: 540,
      child: RenegotiateLoanSheet(
        loan: loan,
        onConfirm: (newCount, newFirstDate) async {
          final authService = sl<BiometricAuthService>();
          final authenticated = await authService.authenticate(
            reason: 'Confirme sua identidade para renegociar os termos do empréstimo.',
          );

          if (!authenticated) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Autenticação não confirmada. Renegociação cancelada.'),
                  backgroundColor: AppColors.debtRed,
                ),
              );
            }
            return;
          }

          if (context.mounted) {
            await _runAction(
              context,
              (cubit) => cubit.renegotiateLoan(loan.id, newCount, newFirstDate),
              successMessage: 'Empréstimo renegociado em $newCount parcelas! 🤝',
            );
          }
        },
      ),
    );
  }

  /// Painel do empréstimo sem prazo: saldo devedor, progresso e botão de abatimento livre.
  Widget _buildOpenEndedPanel(
    BuildContext context,
    ThemeData theme, {
    required bool isPaid,
    required bool isForgiven,
  }) {
    final openInstallment = loan.installments
        .where((i) => !i.isFullyPaid && !i.isCancelled && !i.isForgiven)
        .firstOrNull;
    final canPay = _canRegisterPayment(context) && !isPaid && !isForgiven && openInstallment != null;
    final canDefineInstallments = !isPaid && !isForgiven && loan.remainingAmount.cents > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Row(
            children: [
              Icon(Icons.all_inclusive_rounded, size: 18, color: AppColors.primary),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Sem vencimento: abata o valor que puder, quando puder. Não entra no Fechamento do Ciclo.',
                  style: TextStyle(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Já abatido: ${loan.totalPaidAmount.format()}',
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold, color: AppColors.creditGreen),
            ),
            Text(
              '${(loan.progressPercentage * 100).toInt()}%',
              style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: loan.progressPercentage,
            minHeight: 8,
            backgroundColor: theme.brightness == Brightness.dark
                ? Colors.white10
                : Colors.black.withValues(alpha: 0.06),
            valueColor: const AlwaysStoppedAnimation<Color>(AppColors.creditGreen),
          ),
        ),
        const SizedBox(height: 16),
        if (canPay)
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.payments_rounded),
              label: Text(
                isDebtor ? 'Abater valor' : 'Registrar abatimento recebido',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              onPressed: () => _openPaymentDialog(context, openInstallment),
            ),
          ),
        if (canDefineInstallments) ...[
          const SizedBox(height: 8),
          Center(
            child: TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: AppColors.accent),
              icon: const Icon(Icons.handshake_rounded, size: 16),
              label: const Text(
                'Combinar parcelas para o saldo',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
              onPressed: () => _openRenegotiateSheet(context),
            ),
          ),
        ],
        const SizedBox(height: 8),
        // A chave muda a cada abatimento para o histórico ser recarregado.
        _PaymentHistory(key: ValueKey('${loan.id}_${loan.totalPaidAmount.cents}'), loan: loan),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isForgiven = loan.status == LoanStatus.forgiven;
    final isPaid = loan.status == LoanStatus.paid;
    final isRenegotiated = loan.status == LoanStatus.renegotiated;
    final canRegisterPayment = _canRegisterPayment(context);

    final isDemo = sl<AuthRepository>().isDemoMode;
    List<HouseMember> members = [];
    try {
      members = context.read<FinanceCubit>().state.members;
    } catch (_) {}

    String resolveName(String memberId) {
      if (memberId == P2PLoan.houseLenderId) return 'Caixa da Casa';
      if (isDemo) {
        if (memberId == 'member_carlos') return 'Carlos';
        if (memberId == 'member_marina') return 'Marina';
      }
      final m = members.where((x) => x.id == memberId).firstOrNull;
      if (m != null) return m.name;
      if (memberId == sl<AuthRepository>().currentUser?.id) return 'Você';
      return 'Membro';
    }

    final lenderName = resolveName(loan.lenderMemberId);
    final borrowerName = resolveName(loan.borrowerMemberId);

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

          if (loan.awaitingAcceptance) ...[
            _AcceptanceBanner(loan: loan, borrowerName: borrowerName),
            const SizedBox(height: 12),
          ],

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
              else if (loan.isOpenEnded)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text('Sem prazo', style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.bold)),
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
              if (_canDelete(context)) ...[
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, color: AppColors.debtRed, size: 22),
                  tooltip: 'Excluir Empréstimo',
                  onPressed: () => _confirmDelete(context),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          // Informação de Credor e Devedor
          Row(
            children: [
              Text(
                'Credor: $lenderName',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.creditGreen),
              ),
              const Text('  ➔  ', style: TextStyle(fontSize: 12, color: Colors.grey)),
              Text(
                'Devedor: $borrowerName',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.debtRed),
              ),
            ],
          ),
          if (loan.houseFunding != null) ...[
            const SizedBox(height: 4),
            Text(
              loan.houseFunding == HouseLoanFunding.cycle
                  ? 'Saiu do Caixa do ciclo em ${DateFormat('dd/MM/yyyy').format(loan.fundedOn!)}'
                  : 'Saiu de uma caixinha em ${DateFormat('dd/MM/yyyy').format(loan.fundedOn!)}: os pagamentos voltam para ela',
              key: const Key('loan_house_funding_info'),
              style: theme.textTheme.bodySmall,
            ),
          ],
          _LoanPurchases(loan: loan),
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

          if (loan.isOpenEnded)
            Flexible(
              child: SingleChildScrollView(
                child: _buildOpenEndedPanel(context, theme, isPaid: isPaid, isForgiven: isForgiven),
              ),
            )
          else ...[
          if (!isPaid && !isForgiven && loan.remainingAmount.cents > 0) ...[
            _buildCycleChargePanel(context, canChange: canRegisterPayment),
            const SizedBox(height: 12),
          ],
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
                  label: const Text('Novo parcelamento', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
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
                    'Parcela ${inst.number}/${inst.totalCount}${isInstCancelled ? ' (Cancelada)' : ''}',
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
                          : isInstPaid
                              ? Text('Vencimento: $dateFmt')
                              : Text(
                                  inst.status == InstallmentStatus.overdue
                                      ? 'Atrasada desde $dateFmt${loan.entersCycleSettlement ? ' · entra no próximo fechamento' : ''}'
                                      : 'Vence em $dateFmt${loan.entersCycleSettlement ? ' · cobrada no fechamento' : ''}',
                                ),
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
                              'Parcial',
                              style: TextStyle(fontSize: 10, color: Colors.orange.shade800, fontWeight: FontWeight.bold),
                            ),
                        ],
                      ),
                      if (!isInstPaid && !isForgiven && !isInstCancelled && canRegisterPayment) ...[
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
          if (canRegisterPayment && !isPaid && !isForgiven && loan.remainingAmount.cents > 0) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.fast_forward_rounded),
                label: Text(
                  isDebtor ? 'Antecipar ou abater valor' : 'Registrar pagamento recebido',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                onPressed: () => _openLoanPaymentDialog(context),
              ),
            ),
          ],
          ],
          const SizedBox(height: 16),

          // Ações do Credor (Perdoar Dívida)
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
                label: const Text('Perdoar restante da dívida', style: TextStyle(fontWeight: FontWeight.bold)),
                onPressed: () => _confirmForgive(context),
              ),
            ),
        ],
      ),
    );
  }
}

/// Histórico de abatimentos de um empréstimo sem prazo.
class _PaymentHistory extends StatefulWidget {
  final P2PLoan loan;

  const _PaymentHistory({super.key, required this.loan});

  @override
  State<_PaymentHistory> createState() => _PaymentHistoryState();
}

class _PaymentHistoryState extends State<_PaymentHistory> {
  late final Future<List<P2PPaymentRecord>> _future;

  @override
  void initState() {
    super.initState();
    _future = sl<P2PRepository>().getLoanPayments(widget.loan.id);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateFmt = DateFormat('dd/MM/yyyy');

    return FutureBuilder<List<P2PPaymentRecord>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
          );
        }
        if (snapshot.hasError) {
          return Text('Não foi possível carregar o histórico de abatimentos.', style: theme.textTheme.bodySmall);
        }

        final records = snapshot.data ?? const <P2PPaymentRecord>[];
        // Abatimentos informados no cadastro (anteriores ao app) não têm registro individual.
        final recordedCents = records.fold<int>(0, (acc, r) => acc + r.amount.cents);
        final priorCents = widget.loan.totalPaidAmount.cents - recordedCents;

        if (records.isEmpty && priorCents <= 0) {
          return Text('Nenhum abatimento registrado ainda.', style: theme.textTheme.bodySmall);
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Histórico de abatimentos',
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            for (final r in records)
              _row(theme, dateFmt.format(r.paidAt), r.amount),
            if (priorCents > 0) _row(theme, 'Antes do registro', Money(priorCents)),
          ],
        );
      },
    );
  }

  Widget _row(ThemeData theme, String label, Money amount) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: theme.textTheme.bodySmall),
          Text(
            amount.format(),
            style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.creditGreen),
          ),
        ],
      ),
    );
  }
}

/// Empréstimo lançado por outra pessoa e ainda não aceito (migration 0082):
/// o devedor aceita ou recusa; os outros veem que falta o aceite.
class _AcceptanceBanner extends StatelessWidget {
  final P2PLoan loan;
  final String borrowerName;

  const _AcceptanceBanner({required this.loan, required this.borrowerName});

  Future<void> _accept(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final ok = await context.read<P2PCubit>().acceptLoan(loan.id);
    if (ok) navigator.pop();
    messenger.showSnackBar(SnackBar(
      content: Text(ok ? 'Empréstimo aceito.' : 'Não foi possível aceitar o empréstimo. Tente de novo.'),
      backgroundColor: ok ? AppColors.creditGreen : AppColors.debtRed,
    ));
  }

  Future<void> _decline(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Recusar empréstimo?'),
        content: Text('"${loan.title}" será cancelado e quem lançou recebe um aviso.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Voltar')),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.debtRed),
            child: const Text('Recusar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final ok = await context.read<P2PCubit>().declineLoan(loan.id);
    if (ok) navigator.pop();
    messenger.showSnackBar(SnackBar(
      content: Text(ok ? 'Empréstimo recusado.' : 'Não foi possível recusar o empréstimo. Tente de novo.'),
      backgroundColor: ok ? AppColors.primary : AppColors.debtRed,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final isBorrower = context.read<P2PCubit>().state.currentUserId == loan.borrowerMemberId;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            isBorrower
                ? 'Este empréstimo foi lançado para você. Confira e aceite; até lá, ele fica fora do fechamento do ciclo.'
                : 'Aguardando $borrowerName aceitar. Até lá, ele fica fora do fechamento do ciclo.',
            style: const TextStyle(fontSize: 13),
          ),
          if (isBorrower) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: const Key('loan_decline'),
                    onPressed: () => _decline(context),
                    style: OutlinedButton.styleFrom(foregroundColor: AppColors.debtRed),
                    child: const Text('Recusar'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    key: const Key('loan_accept'),
                    onPressed: () => _accept(context),
                    child: const Text('Aceitar'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// O que compõe o empréstimo: as compras da fatura que viraram dívida, uma por
/// linha, ou a descrição escrita quando ele não veio de uma importação.
class _LoanPurchases extends StatefulWidget {
  final P2PLoan loan;

  const _LoanPurchases({required this.loan});

  @override
  State<_LoanPurchases> createState() => _LoanPurchasesState();
}

class _LoanPurchasesState extends State<_LoanPurchases> {
  static final _day = DateFormat('dd/MM');
  late final Future<List<LoanPurchase>> _purchases = _load();

  Future<List<LoanPurchase>> _load() async {
    if (!sl.isRegistered<ImportRepository>()) return const [];
    try {
      return await sl<ImportRepository>().purchasesOfLoan(widget.loan.id);
    } catch (_) {
      return const []; // Sem a lista, vale a descrição
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    final description = widget.loan.description;
    return FutureBuilder<List<LoanPurchase>>(
      future: _purchases,
      builder: (context, snapshot) {
        final purchases = snapshot.data ?? const <LoanPurchase>[];
        if (purchases.isEmpty) {
          if (description == null || description.isEmpty) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(description, style: style),
          );
        }
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            key: const Key('loan_purchases'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Compras', style: style?.copyWith(fontWeight: FontWeight.bold)),
              for (final purchase in purchases)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Row(
                    children: [
                      Text(_day.format(purchase.date), style: style),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(purchase.title, style: style, overflow: TextOverflow.ellipsis),
                      ),
                      Text(purchase.amount.formatted, style: style),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
