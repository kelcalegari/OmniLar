import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../core/domain/value_objects/financial_cycle.dart';
import '../../../../core/domain/value_objects/money.dart';
import '../../../../core/security/biometric_auth_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/responsive.dart';
import '../../../../core/widgets/responsive_container.dart';
import '../../../../core/widgets/privacy_toggle.dart';
import '../../domain/entities/settlement_options.dart';
import '../../domain/entities/settlement_summary.dart';
import '../../domain/entities/super_pix_transfer.dart';
import '../../domain/entities/transfer_settlement_resolution.dart';
import '../cubit/settlement_cubit.dart';
import '../cubit/settlement_state.dart';
import '../widgets/settlement_audit_sheet.dart';
import '../widgets/partial_payment_dialog.dart';
import '../../../finance/presentation/cubit/finance_cubit.dart';
import '../../../p2p/presentation/cubit/p2p_cubit.dart';

class SettlementHubPage extends StatelessWidget {
  final FinancialCycle? initialCycle;

  const SettlementHubPage({super.key, this.initialCycle});

  FinancialCycle _resolveInitialCycle(BuildContext context) {
    if (initialCycle != null) return initialCycle!;
    try {
      final financeCycle = context.read<FinanceCubit>().state.currentCycle;
      return financeCycle;
    } catch (_) {
      final now = DateTime.now();
      return FinancialCycle.fromDate(date: now, cycleStartDay: 5);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cycle = _resolveInitialCycle(context);

    return BlocProvider(
      create: (_) => sl<SettlementCubit>()..loadSettlement(cycle),
      child: const _SettlementHubContent(),
    );
  }
}

class _SettlementHubContent extends StatelessWidget {
  const _SettlementHubContent();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: Navigator.of(context).canPop()
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                tooltip: 'Voltar ao painel',
                onPressed: () => Navigator.of(context).pop(),
              )
            : null,
        title: const Text(
          'Fechamento do Ciclo',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          const PrivacyToggleButton(),
          BlocBuilder<SettlementCubit, SettlementState>(
            builder: (context, state) {
              final summary = state.summary;
              if (summary == null) return const SizedBox.shrink();
              return IconButton(
                icon: const Icon(Icons.calculate_outlined),
                tooltip: 'Auditar memória de cálculo',
                onPressed: () => SettlementAuditSheet.show(
                  context: context,
                  summary: summary,
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.help_outline_rounded),
            tooltip: 'Entenda como funciona a compensação',
            onPressed: () => _showExplanationDialog(context),
          ),
        ],
      ),
      body: BlocConsumer<SettlementCubit, SettlementState>(
        listener: (context, state) {
          if (state.status == SettlementCubitStatus.settled) {
            // Notifica cubits globais para refletir o fechamento do ciclo
            context.read<FinanceCubit>().loadCycleData();
            context.read<P2PCubit>().loadLoans();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                backgroundColor: AppColors.creditGreen,
                content: Row(
                  children: [
                    Icon(Icons.check_circle_rounded, color: Colors.white),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Ciclo liquidado com sucesso! Parcelas e saldos atualizados.',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
            );
          } else if (state.status == SettlementCubitStatus.error &&
              state.errorMessage != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                backgroundColor: AppColors.debtRed,
                content: Text(state.errorMessage!),
              ),
            );
          }
        },
        builder: (context, state) {
          if (state.status == SettlementCubitStatus.loading &&
              state.summary == null) {
            return const Center(child: CircularProgressIndicator());
          }

          final summary = state.summary;
          if (summary == null) {
            return const Center(
              child: Text('Nenhum dado de fechamento disponível.'),
            );
          }

          final isSettled = summary.status == SettlementStatus.settled;
          final isDesktop = context.isDesktop;

          final settlementColumn = ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Cabeçalho do Ciclo
              _buildCycleHeader(context, summary, state),
              const SizedBox(height: 16),

              // PASSO 1: Resumo do Caixa da Casa
              _buildStep1HouseSummary(context, summary, state),
              const SizedBox(height: 16),

              // PASSO 2: Resumo de Empréstimos P2P
              _buildStep2P2PSummary(context, summary),
              const SizedBox(height: 16),

              // PASSO 3: O Veredito - Super Pix
              _buildStep3SuperPix(context, summary, state),
              const SizedBox(height: 24),

              // Botão de Confirmação Atômica
              if (!isSettled)
                FilledButton.icon(
                  onPressed: state.status == SettlementCubitStatus.confirming
                      ? null
                      : () => _confirmSettlement(context, state),
                  icon: state.status == SettlementCubitStatus.confirming
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.check_circle_outline_rounded),
                  label: Text(
                    state.status == SettlementCubitStatus.confirming
                        ? 'Liquidando Ciclo...'
                        : 'Confirmar Liquidação do Ciclo',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                )
              else ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.creditGreen.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppColors.creditGreen.withValues(alpha: 0.4),
                    ),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.verified_rounded,
                        color: AppColors.creditGreen,
                        size: 28,
                      ),
                      SizedBox(width: 12),
                      Text(
                        'Ciclo 100% Liquidado e Quitado',
                        style: TextStyle(
                          color: AppColors.creditGreen,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Center(
                  child: TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.primary,
                    ),
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text(
                      'Reabrir / Recalcular com novos lançamentos',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    onPressed: () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Recalcular Fechamento?'),
                          content: const Text(
                            'Deseja reabrir este ciclo para que o saldo e parcelas sejam recalculados dinamicamente com as despesas atuais?',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('Cancelar'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('Recalcular'),
                            ),
                          ],
                        ),
                      );
                      if (confirmed == true && context.mounted) {
                        context.read<SettlementCubit>().reopenSettlement();
                      }
                    },
                  ),
                ),
              ],
              const SizedBox(height: 32),
            ],
          );

          if (isDesktop) {
            // Em Desktop/Web: Exibe o Super Pix à esquerda e a Memória de Cálculo Auditável fixada à direita
            return ResponsiveContainer(
              maxWidth: 1600,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 6,
                      child: settlementColumn,
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      flex: 5,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 16, bottom: 32),
                        child: SettlementAuditSheet(
                          summary: summary,
                          isEmbedded: true,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          return ResponsiveContainer(
            child: settlementColumn,
          );
        },
      ),
    );
  }

  Widget _buildCycleHeader(
    BuildContext context,
    SettlementSummary summary,
    SettlementState state,
  ) {
    final now = DateTime.now();
    final isPastCycle = summary.cycle.endDate.isBefore(now);
    final isSettled = summary.status == SettlementStatus.settled;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              IconButton.filledTonal(
                icon: const Icon(Icons.chevron_left_rounded),
                tooltip: 'Ciclo anterior',
                onPressed: () =>
                    context.read<SettlementCubit>().previousCycle(5),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.account_balance_rounded,
                          size: 18,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          summary.cycle.monthName.toUpperCase(),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      summary.cycle.formattedPeriod,
                      style: const TextStyle(
                        color: Colors.grey,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                icon: const Icon(Icons.chevron_right_rounded),
                tooltip: 'Próximo ciclo',
                onPressed: () => context.read<SettlementCubit>().nextCycle(5),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: isSettled
                      ? AppColors.creditGreen.withValues(alpha: 0.15)
                      : Colors.amber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isSettled
                          ? Icons.check_circle_rounded
                          : Icons.pending_actions_rounded,
                      size: 14,
                      color: isSettled
                          ? AppColors.creditGreen
                          : Colors.amber.shade800,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isSettled
                          ? 'Liquidado'
                          : (isPastCycle
                                ? 'Aberto (Ciclo Encerrado)'
                                : 'Ciclo em Andamento'),
                      style: TextStyle(
                        color: isSettled
                            ? AppColors.creditGreen
                            : Colors.amber.shade800,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStep1HouseSummary(
    BuildContext context,
    SettlementSummary summary,
    SettlementState state,
  ) {
    final isSurplus = summary.houseTreasuryBalance.cents >= 0;
    final isSettled = summary.status == SettlementStatus.settled;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Text(
                    '1',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Resumo do Caixa da Casa',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Aportes Realizados:',
                  style: TextStyle(color: Colors.grey),
                ),
                PrivacySensitiveText(
                  summary.totalContributions.formatted,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.creditGreen,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Despesas da Casa no Ciclo:',
                  style: TextStyle(color: Colors.grey),
                ),
                PrivacySensitiveText(
                  summary.totalHouseExpenses.formatted,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.debtRed,
                  ),
                ),
              ],
            ),
            if (summary.totalPersonalExpensesInBills.cents > 0) ...[
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '↳ Compartilhado: ${summary.totalSharedHouseExpenses.formatted}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.debtRed.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${summary.totalPersonalExpensesInBills.formatted} em itens pessoais',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: AppColors.debtRed,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const Divider(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  isSettled
                      ? 'Saldo Final do Ciclo:'
                      : (isSurplus
                            ? 'Saldo Livre (Sobra no Fundo):'
                            : 'Déficit do Caixa:'),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                PrivacySensitiveText(
                  isSettled
                      ? (isSurplus
                            ? summary.houseTreasuryBalance.formatted
                            : 'R\$ 0,00 (Equilibrado)')
                      : summary.houseTreasuryBalance.formatted,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: (isSettled || isSurplus)
                        ? AppColors.creditGreen
                        : AppColors.debtRed,
                  ),
                ),
              ],
            ),
            if (!isSettled && summary.bucketDeficit.cents > 0)
              _buildDeficitCard(context, summary, state),
            if (isSettled) ...[
              const SizedBox(height: 8),
              Text(
                'Todas as despesas deste ciclo foram cobertas pelos aportes e quitadas.',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
            ] else if (isSurplus && summary.houseTreasuryBalance.cents > 0) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.2),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.savings_rounded,
                          color: AppColors.primary,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'O que fazer com a sobra de ${summary.houseTreasuryBalance.formatted}?',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    RadioListTile<SurplusAction>(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      value: SurplusAction.toVault,
                      groupValue: state.options.surplusAction,
                      title: const Text(
                        'Guardar em uma Caixinha (Recomendado)',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      subtitle: const Text(
                        'Destina a economia para metas ou reserva da casa',
                        style: TextStyle(fontSize: 11),
                      ),
                      onChanged: (val) {
                        if (val != null)
                          context.read<SettlementCubit>().updateSurplusAction(
                            val,
                          );
                      },
                    ),
                    if (state.options.surplusAction ==
                        SurplusAction.toVault) ...[
                      Padding(
                        padding: const EdgeInsets.only(
                          left: 32,
                          right: 8,
                          bottom: 8,
                        ),
                        child: state.vaults.isEmpty
                            ? Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.amber.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  'Nenhuma caixinha criada ainda. Crie uma em Caixinhas ou opte por rolar o saldo.',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.orange,
                                  ),
                                ),
                              )
                            : DropdownButtonFormField<String>(
                                value:
                                    state.options.targetVaultId ??
                                    state.vaults.first.id,
                                decoration: const InputDecoration(
                                  labelText: 'Caixinha de Destino',
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                                items: state.vaults.map((vault) {
                                  return DropdownMenuItem<String>(
                                    value: vault.id,
                                    child: Text(
                                      '${vault.name} (${vault.currentBalance.formatted})',
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                  );
                                }).toList(),
                                onChanged: (vaultId) {
                                  if (vaultId != null) {
                                    context
                                        .read<SettlementCubit>()
                                        .updateTargetVaultId(vaultId);
                                  }
                                },
                              ),
                      ),
                    ],
                    RadioListTile<SurplusAction>(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      value: SurplusAction.rollover,
                      groupValue: state.options.surplusAction,
                      title: const Text(
                        'Deixar no Caixa para o próximo mês',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      subtitle: const Text(
                        'Começa o próximo ciclo com fôlego inicial positivo',
                        style: TextStyle(fontSize: 11),
                      ),
                      onChanged: (val) {
                        if (val != null)
                          context.read<SettlementCubit>().updateSurplusAction(
                            val,
                          );
                      },
                    ),
                    RadioListTile<SurplusAction>(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      value: SurplusAction.refund,
                      groupValue: state.options.surplusAction,
                      title: const Text(
                        'Devolver aos membros (Rateio)',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      subtitle: const Text(
                        'Reembolsa o valor proporcionalmente aos membros',
                        style: TextStyle(fontSize: 11),
                      ),
                      onChanged: (val) {
                        if (val != null)
                          context.read<SettlementCubit>().updateSurplusAction(
                            val,
                          );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Gastos acima do balde (aportes fixos): quem fecha escolhe como cobrir.
  Widget _buildDeficitCard(
    BuildContext context,
    SettlementSummary summary,
    SettlementState state,
  ) {
    final cubit = context.read<SettlementCubit>();
    final covered = summary.deficitCoveredByVault;
    final toSplit = Money(summary.bucketDeficit.cents - covered.cents);
    final vaultsWithBalance = state.vaults
        .where((v) => v.currentBalance.cents > 0)
        .toList();
    final selectedVaultId =
        vaultsWithBalance.any((v) => v.id == state.options.deficitVaultId)
        ? state.options.deficitVaultId
        : null;

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.debtRed.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.debtRed.withValues(alpha: 0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  color: AppColors.debtRed,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Os gastos passaram do balde em ${summary.bucketDeficit.formatted}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: AppColors.debtRed,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Escolha como cobrir o excedente deste ciclo.',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
            if (vaultsWithBalance.isNotEmpty) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                value: selectedVaultId,
                decoration: const InputDecoration(
                  labelText: 'Usar a reserva de uma caixinha',
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text(
                      'Não usar caixinha',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                  ...vaultsWithBalance.map(
                    (vault) => DropdownMenuItem<String?>(
                      value: vault.id,
                      child: Text(
                        '${vault.name} (${vault.currentBalance.formatted})',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ),
                ],
                onChanged: cubit.updateDeficitVault,
              ),
            ],
            if (covered.cents > 0) ...[
              const SizedBox(height: 8),
              Text(
                'A caixinha cobre ${covered.formatted}.',
                style: const TextStyle(fontSize: 12),
              ),
            ],
            const SizedBox(height: 12),
            if (toSplit.cents > 0) ...[
              Text(
                'Dividir ${toSplit.formatted} entre os moradores:',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Proporcional ao aporte'),
                    selected:
                        state.options.deficitSplit == DeficitSplit.proportional,
                    onSelected: (_) =>
                        cubit.updateDeficitSplit(DeficitSplit.proportional),
                  ),
                  ChoiceChip(
                    label: const Text('Partes iguais'),
                    selected: state.options.deficitSplit == DeficitSplit.equal,
                    onSelected: (_) =>
                        cubit.updateDeficitSplit(DeficitSplit.equal),
                  ),
                ],
              ),
            ] else
              const Text(
                'A caixinha cobre todo o excedente: ninguém paga a mais.',
                style: TextStyle(fontSize: 12),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep2P2PSummary(
    BuildContext context,
    SettlementSummary summary,
  ) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Text(
                        '2',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Compensação de Empréstimos P2P',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
                TextButton.icon(
                  onPressed: () => SettlementAuditSheet.show(
                    context: context,
                    summary: summary,
                  ),
                  icon: const Icon(Icons.receipt_long_rounded, size: 14),
                  label: const Text(
                    'Auditar',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: AppColors.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Parcelas Interpessoais do Mês:',
                  style: TextStyle(color: Colors.grey),
                ),
                PrivacySensitiveText(
                  summary.totalP2PCleared.formatted,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ...summary.memberBalances.map((m) {
              return InkWell(
                onTap: () => SettlementAuditSheet.show(
                  context: context,
                  summary: summary,
                  initialMemberId: m.memberId,
                ),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 6,
                    horizontal: 4,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Text(
                            '${m.memberName}:',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.info_outline_rounded,
                            size: 14,
                            color: Colors.grey.shade400,
                          ),
                        ],
                      ),
                      PrivacySensitiveText(
                        m.isCreditor
                            ? '+${m.netBalance.formatted} (a receber)'
                            : m.isDebtor
                            ? '-${m.netBalance.abs().formatted} (a pagar)'
                            : 'Zerado',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: m.isCreditor
                              ? AppColors.creditGreen
                              : m.isDebtor
                              ? AppColors.debtRed
                              : Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildStep3SuperPix(
    BuildContext context,
    SettlementSummary summary,
    SettlementState state,
  ) {
    final isSettled = summary.status == SettlementStatus.settled;

    // Obtém o nome da Caixinha alvo caso configurado
    final targetVault = state.vaults
        .where((v) => v.id == state.options.targetVaultId)
        .firstOrNull;
    final vaultName = targetVault?.name ?? 'Caixinha da Casa';

    return Card(
      elevation: 0,
      color: AppColors.primary.withValues(alpha: 0.05),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: AppColors.primary.withValues(alpha: 0.3),
          width: 1.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                      ),
                      child: const Text(
                        '3',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'O Veredito: O "Super Pix"',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
                TextButton.icon(
                  onPressed: () => _shareSettlementSummary(context, summary),
                  icon: const Icon(Icons.share_rounded, size: 16),
                  label: const Text(
                    'Compartilhar',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: AppColors.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'O motor cruzou os aportes com os empréstimos diretos e despesas do bolso. Nenhuma outra transferência é necessária.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            if (!isSettled) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(
                          Icons.tune_rounded,
                          size: 16,
                          color: AppColors.primary,
                        ),
                        SizedBox(width: 6),
                        Text(
                          'Acerto de despesas do bolso e aportes extras:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    RadioListTile<MemberCreditAction>(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      value: MemberCreditAction.rolloverNextCycle,
                      groupValue: state.options.creditAction,
                      title: const Text(
                        'Abater no próximo ciclo (Recomendado)',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                      subtitle: const Text(
                        'Quem colocou mais dinheiro no caixa paga menos na cota do próximo mês, sem precisar de Pix hoje.',
                        style: TextStyle(fontSize: 11),
                      ),
                      onChanged: (val) {
                        if (val != null)
                          context.read<SettlementCubit>().updateCreditAction(
                            val,
                          );
                      },
                    ),
                    RadioListTile<MemberCreditAction>(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      value: MemberCreditAction.settleNow,
                      groupValue: state.options.creditAction,
                      title: const Text(
                        'Fazer Pix de acerto agora',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                      subtitle: const Text(
                        'Gera transferências imediatas no Super Pix para zerar tudo hoje.',
                        style: TextStyle(fontSize: 11),
                      ),
                      onChanged: (val) {
                        if (val != null)
                          context.read<SettlementCubit>().updateCreditAction(
                            val,
                          );
                      },
                    ),
                  ],
                ),
              ),
            ],
            if (summary.transfers.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'Todos os saldos estão zerados! Nenhuma transferência necessária.',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppColors.creditGreen,
                    ),
                  ),
                ),
              )
            else
              ...summary.transfers.map(
                (t) => _buildTransferCard(context, t, state, isSettled),
              ),
            if (summary.houseTreasuryBalance.cents > 0)
              Container(
                margin: const EdgeInsets.only(top: 6),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.creditGreen.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.creditGreen.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.savings_outlined,
                      color: AppColors.creditGreen,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        state.options.surplusAction == SurplusAction.toVault
                            ? 'Sobra de ${summary.houseTreasuryBalance.formatted} será guardada na caixinha "$vaultName".'
                            : (state.options.surplusAction ==
                                      SurplusAction.rollover
                                  ? 'Sobra de ${summary.houseTreasuryBalance.formatted} permanecerá no Caixa para o próximo mês.'
                                  : 'Sobra de ${summary.houseTreasuryBalance.formatted} será estornada aos membros.'),
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.creditGreen,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransferCard(
    BuildContext context,
    SuperPixTransfer transfer,
    SettlementState state,
    bool isSettled,
  ) {
    final resolution = state.options.transferResolutions[transfer.id];
    final isPartial = resolution != null && resolution.isPartialPayment;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isPartial
              ? AppColors.accent.withValues(alpha: 0.5)
              : Colors.grey.withValues(alpha: 0.2),
          width: isPartial ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: transfer.fromMemberId == 'entity_caixa'
                        ? Colors.teal.withValues(alpha: 0.15)
                        : AppColors.debtRed.withValues(alpha: 0.15),
                    child: transfer.fromMemberId == 'entity_caixa'
                        ? const Icon(
                            Icons.home_rounded,
                            size: 18,
                            color: Colors.teal,
                          )
                        : Text(
                            transfer.fromMemberName.isNotEmpty
                                ? transfer.fromMemberName[0]
                                : '?',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppColors.debtRed,
                            ),
                          ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.arrow_forward_rounded,
                    size: 16,
                    color: Colors.grey,
                  ),
                  const SizedBox(width: 8),
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: transfer.toMemberId == 'entity_caixa'
                        ? Colors.teal.withValues(alpha: 0.15)
                        : AppColors.creditGreen.withValues(alpha: 0.15),
                    child: transfer.toMemberId == 'entity_caixa'
                        ? const Icon(
                            Icons.home_rounded,
                            size: 18,
                            color: Colors.teal,
                          )
                        : Text(
                            transfer.toMemberName.isNotEmpty
                                ? transfer.toMemberName[0]
                                : '?',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppColors.creditGreen,
                            ),
                          ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  PrivacySensitiveText(
                    isPartial
                        ? resolution.amountPaid.formatted
                        : transfer.amount.formatted,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: isPartial ? AppColors.accent : AppColors.primary,
                    ),
                  ),
                  if (isPartial)
                    Text(
                      'Total: ${transfer.amount.formatted}',
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.grey,
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  '${transfer.fromMemberName} transfere para ${transfer.toMemberName}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!isSettled) ...[
                    TextButton.icon(
                      onPressed: () {
                        PartialPaymentDialog.show(
                          context: context,
                          transfer: transfer,
                          vaults: state.vaults,
                          initialResolution: resolution,
                          onSave: (res) {
                            context
                                .read<SettlementCubit>()
                                .updateTransferResolution(res);
                          },
                          onRemove: () {
                            context
                                .read<SettlementCubit>()
                                .removeTransferResolution(transfer.id);
                          },
                        );
                      },
                      icon: Icon(
                        isPartial
                            ? Icons.edit_note_rounded
                            : Icons.payments_outlined,
                        size: 14,
                        color: isPartial ? AppColors.accent : null,
                      ),
                      label: Text(
                        isPartial ? 'Ajustado' : 'Pagar Parcial',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isPartial
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: isPartial ? AppColors.accent : null,
                        ),
                      ),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 4,
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],
                  if (transfer.pixKey != null) ...[
                    TextButton.icon(
                      onPressed: () {
                        Clipboard.setData(
                          ClipboardData(text: transfer.pixKey!),
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Chave Pix copiada: ${transfer.pixKey}',
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.copy_rounded, size: 14),
                      label: const Text(
                        'Chave Pix',
                        style: TextStyle(fontSize: 12),
                      ),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 4,
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],
                  TextButton.icon(
                    onPressed: () => _shareSingleTransfer(context, transfer),
                    icon: const Icon(
                      Icons.chat_bubble_outline_rounded,
                      size: 14,
                    ),
                    label: const Text(
                      'Cobrança',
                      style: TextStyle(fontSize: 12),
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 4,
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (isPartial) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppColors.accent.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.handshake_rounded,
                    size: 16,
                    color: AppColors.accent,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Pagamento Parcial: ${resolution.amountPaid.formatted} pago agora',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          'Diferença de ${resolution.shortfall.formatted}: ${_getResolutionDescription(resolution, transfer, state)}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!isSettled)
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 16),
                      tooltip: 'Restaurar pagamento integral',
                      onPressed: () {
                        context
                            .read<SettlementCubit>()
                            .removeTransferResolution(transfer.id);
                      },
                    ),
                ],
              ),
            ),
          ],
          if (transfer.explanation != null) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.15),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    size: 14,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      transfer.explanation!,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _getResolutionDescription(
    TransferSettlementResolution res,
    SuperPixTransfer transfer,
    SettlementState state,
  ) {
    switch (res.shortfallAction) {
      case ShortfallAction.createP2PLoan:
        return '${transfer.toMemberName} financia em ${res.loanInstallmentsCount}x via P2P';
      case ShortfallAction.deductFromVault:
        final vault = state.vaults
            .where((v) => v.id == res.vaultId)
            .firstOrNull;
        final name = vault?.name ?? 'Caixinha da Casa';
        return 'Coberto temporariamente por $name';
      case ShortfallAction.rolloverPending:
        return 'Fica pendente para o próximo fechamento';
      case ShortfallAction.forgiveRemainder:
        return 'Perdoado/anistiado por ${transfer.toMemberName}';
    }
  }

  void _shareSettlementSummary(
    BuildContext context,
    SettlementSummary summary,
  ) {
    final buffer = StringBuffer();
    buffer.writeln('🏡 Fechamento do Lar • Omni Lar');
    buffer.writeln('📅 Ciclo: ${summary.cycle.formattedPeriod}');
    buffer.writeln('');
    buffer.writeln('✨ Veredito Super Pix:');
    if (summary.transfers.isEmpty) {
      buffer.writeln(
        '• Todas as contas estão zeradas! Nenhuma transferência necessária.',
      );
    } else {
      for (final t in summary.transfers) {
        buffer.writeln(
          '• ${t.fromMemberName} transfere ${t.amount.formatted} para ${t.toMemberName}',
        );
        if (t.pixKey != null) {
          buffer.writeln('  Chave Pix: ${t.pixKey}');
        }
      }
    }
    if (summary.houseTreasuryBalance.cents > 0) {
      buffer.writeln('');
      buffer.writeln(
        '💰 Sobra no Caixa da Casa: ${summary.houseTreasuryBalance.formatted}',
      );
    }
    buffer.writeln('');
    buffer.writeln(
      'Todas as contas da casa e empréstimos pessoais foram compensados e quitados.',
    );

    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Veredito do Super Pix copiado! Pronto para colar no WhatsApp.',
        ),
      ),
    );
  }

  void _shareSingleTransfer(BuildContext context, SuperPixTransfer transfer) {
    final pixInfo = transfer.pixKey != null
        ? ' (Chave Pix: ${transfer.pixKey})'
        : '';
    final msg =
        'Oi ${transfer.fromMemberName}! Pelo fechamento do Omni Lar, ficou acertado você enviar ${transfer.amount.formatted} para ${transfer.toMemberName}$pixInfo para quitar o ciclo.';
    Clipboard.setData(ClipboardData(text: msg));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppColors.creditGreen,
        content: Row(
          children: [
            const Icon(
              Icons.check_circle_rounded,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Cobrança para ${transfer.fromMemberName} copiada! Pronto para colar no WhatsApp. 💬',
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmSettlement(BuildContext context, SettlementState state) {
    final targetVault = state.vaults
        .where((v) => v.id == state.options.targetVaultId)
        .firstOrNull;
    final vaultName = targetVault != null
        ? targetVault.name
        : 'Caixinha da Casa';

    final surplusDesc = state.options.surplusAction == SurplusAction.toVault
        ? 'Guardar sobra na caixinha "$vaultName"'
        : (state.options.surplusAction == SurplusAction.rollover
              ? 'Rolar sobra como saldo para o próximo mês'
              : 'Devolver sobra aos membros proporcionalmente');

    final creditDesc =
        state.options.creditAction == MemberCreditAction.rolloverNextCycle
        ? 'Abater créditos na cota do próximo mês'
        : 'Acerto imediato de créditos via Pix hoje';

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Confirmar Liquidação?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Esta ação gravará a liquidação de forma atômica no ledger financeiro e carimbará as parcelas e faturas deste ciclo como pagas.',
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '• Sobra da Casa: $surplusDesc',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '• Créditos de Membros: $creditDesc',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(dialogCtx);

              final authService = sl<BiometricAuthService>();
              final authenticated = await authService.authenticate(
                reason:
                    'Confirme sua identidade para liquidar o ciclo financeiro da casa.',
              );

              if (!authenticated) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Autenticação não confirmada. Liquidação cancelada.',
                      ),
                      backgroundColor: AppColors.debtRed,
                    ),
                  );
                }
                return;
              }

              if (context.mounted) {
                context.read<SettlementCubit>().confirmSettlement();
              }
            },
            child: const Text('Confirmar e Liquidar'),
          ),
        ],
      ),
    );
  }

  void _showExplanationDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.auto_awesome, color: AppColors.primary),
            SizedBox(width: 8),
            Text('O que é o Super Pix?'),
          ],
        ),
        content: const Text(
          'O Motor de Compensação Global do Omni Lar cruza todas as obrigações da Casa com as dívidas pessoais entre membros.\n\n'
          'Em vez de fazer vários pagamentos separados (um Pix para a Casa, outro para o cartão, outro de um empréstimo pessoal), '
          'o algoritmo junta tudo em uma única transferência simplificada!',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Entendi'),
          ),
        ],
      ),
    );
  }
}
