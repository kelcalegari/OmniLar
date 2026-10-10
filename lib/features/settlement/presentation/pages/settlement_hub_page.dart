import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../core/domain/value_objects/financial_cycle.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/responsive.dart';
import '../../../../core/widgets/responsive_container.dart';
import '../../domain/entities/settlement_summary.dart';
import '../../domain/entities/super_pix_transfer.dart';
import '../cubit/settlement_cubit.dart';
import '../cubit/settlement_state.dart';

class SettlementHubPage extends StatelessWidget {
  final FinancialCycle? initialCycle;

  const SettlementHubPage({super.key, this.initialCycle});

  @override
  Widget build(BuildContext context) {
    final cycle = initialCycle ??
        FinancialCycle.fromDate(
          date: DateTime.now(),
          cycleStartDay: 5,
        );

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
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: Navigator.of(context).canPop()
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                tooltip: 'Voltar ao painel',
                onPressed: () => Navigator.of(context).pop(),
              )
            : null,
        title: const Text('Fechamento do Ciclo', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
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
          } else if (state.status == SettlementCubitStatus.error && state.errorMessage != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                backgroundColor: AppColors.debtRed,
                content: Text(state.errorMessage!),
              ),
            );
          }
        },
        builder: (context, state) {
          if (state.status == SettlementCubitStatus.loading && state.summary == null) {
            return const Center(child: CircularProgressIndicator());
          }

          final summary = state.summary;
          if (summary == null) {
            return const Center(child: Text('Nenhum dado de fechamento disponível.'));
          }

          final isSettled = summary.status == SettlementStatus.settled;

          return ResponsiveContainer(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Cabeçalho do Ciclo
              _buildCycleHeader(context, summary),
              const SizedBox(height: 16),

              // PASSO 1: Resumo do Caixa da Casa
              _buildStep1HouseSummary(context, summary),
              const SizedBox(height: 16),

              // PASSO 2: Resumo de Empréstimos P2P
              _buildStep2P2PSummary(context, summary),
              const SizedBox(height: 16),

              // PASSO 3: O Veredito - Super Pix
              _buildStep3SuperPix(context, summary),
              const SizedBox(height: 24),

              // Botão de Confirmação Atômica
              if (!isSettled)
                FilledButton.icon(
                  onPressed: state.status == SettlementCubitStatus.confirming
                      ? null
                      : () => _confirmSettlement(context),
                  icon: state.status == SettlementCubitStatus.confirming
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : const Icon(Icons.check_circle_outline_rounded),
                  label: Text(
                    state.status == SettlementCubitStatus.confirming
                        ? 'Liquidando Ciclo...'
                        : 'Confirmar Liquidação do Ciclo',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.creditGreen.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.creditGreen.withValues(alpha: 0.4)),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.verified_rounded, color: AppColors.creditGreen, size: 28),
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
              const SizedBox(height: 32),
            ],
          ),
        );
      },
      ),
    );
  }

  Widget _buildCycleHeader(BuildContext context, SettlementSummary summary) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.account_balance_rounded, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Fechamento do Ciclo Financeiro',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                Text(
                  summary.cycle.formattedPeriod,
                  style: const TextStyle(color: Colors.grey, fontSize: 13),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: summary.status == SettlementStatus.settled
                  ? AppColors.creditGreen.withValues(alpha: 0.15)
                  : Colors.amber.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              summary.status == SettlementStatus.settled ? 'Liquidado' : 'Aberto',
              style: TextStyle(
                color: summary.status == SettlementStatus.settled
                    ? AppColors.creditGreen
                    : Colors.amber.shade800,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep1HouseSummary(BuildContext context, SettlementSummary summary) {
    final isSurplus = summary.houseTreasuryBalance.cents >= 0;

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
                  child: const Text('1', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary)),
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
                const Text('Aportes Realizados:', style: TextStyle(color: Colors.grey)),
                Text(
                  summary.totalContributions.formatted,
                  style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.creditGreen),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Despesas da Casa no Ciclo:', style: TextStyle(color: Colors.grey)),
                Text(
                  summary.totalHouseExpenses.formatted,
                  style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.debtRed),
                ),
              ],
            ),
            const Divider(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  isSurplus ? 'Saldo Livre (Sobra no Fundo):' : 'Déficit do Caixa:',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  summary.houseTreasuryBalance.formatted,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: isSurplus ? AppColors.creditGreen : AppColors.debtRed,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep2P2PSummary(BuildContext context, SettlementSummary summary) {
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
                  child: const Text('2', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary)),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Compensação de Empréstimos P2P',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Parcelas Interpessoais do Mês:', style: TextStyle(color: Colors.grey)),
                Text(
                  summary.totalP2PCleared.formatted,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ...summary.memberBalances.map((m) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('${m.memberName}:', style: const TextStyle(fontSize: 13)),
                    Text(
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
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildStep3SuperPix(BuildContext context, SettlementSummary summary) {
    return Card(
      elevation: 0,
      color: AppColors.primary.withValues(alpha: 0.05),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppColors.primary.withValues(alpha: 0.3), width: 1.5),
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
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                  child: const Text('3', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                ),
                const SizedBox(width: 8),
                const Text(
                  'O Veredito: O "Super Pix"',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.primary),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'O motor cruzou os aportes com os empréstimos diretos e despesas do bolso. Nenhuma outra transferência é necessária.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            if (summary.transfers.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'Todos os saldos estão zerados! Nenhuma transferência necessária.',
                    style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.creditGreen),
                  ),
                ),
              )
            else
              ...summary.transfers.map((t) => _buildTransferCard(context, t)),
            if (summary.houseTreasuryBalance.cents > 0)
              Container(
                margin: const EdgeInsets.only(top: 6),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.creditGreen.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.creditGreen.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.savings_outlined, color: AppColors.creditGreen, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Sobra de ${summary.houseTreasuryBalance.formatted} do Caixa permanece no Fundo de Reserva da Casa.',
                        style: const TextStyle(fontSize: 12, color: AppColors.creditGreen, fontWeight: FontWeight.w600),
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

  Widget _buildTransferCard(BuildContext context, SuperPixTransfer transfer) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
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
                    backgroundColor: AppColors.debtRed.withValues(alpha: 0.15),
                    child: Text(
                      transfer.fromMemberName[0],
                      style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.debtRed),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.arrow_forward_rounded, size: 16, color: Colors.grey),
                  const SizedBox(width: 8),
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: AppColors.creditGreen.withValues(alpha: 0.15),
                    child: Text(
                      transfer.toMemberName[0],
                      style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.creditGreen),
                    ),
                  ),
                ],
              ),
              Text(
                transfer.amount.formatted,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.primary),
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
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ),
              if (transfer.pixKey != null)
                TextButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: transfer.pixKey!));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Chave Pix copiada: ${transfer.pixKey}')),
                    );
                  },
                  icon: const Icon(Icons.copy_rounded, size: 14),
                  label: const Text('Copiar Pix', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  void _confirmSettlement(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Confirmar Liquidação?'),
        content: const Text(
          'Esta ação gravará a liquidação de forma atômica no ledger financeiro e carimbará as parcelas e faturas deste ciclo como pagas.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogCtx);
              context.read<SettlementCubit>().confirmSettlement();
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
