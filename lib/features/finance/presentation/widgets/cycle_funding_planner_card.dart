import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/responsive.dart';
import '../../../../core/widgets/privacy_toggle.dart';
import '../../../../core/widgets/money_input_field.dart';
import '../../domain/entities/house_settings.dart';
import '../cubit/finance_state.dart';
import '../../domain/entities/cycle_funding_estimate.dart';
import '../cubit/finance_cubit.dart';
import '../pages/add_contribution_page.dart';

/// Card interativo para planejamento e sugestão inteligente de aportes no início do ciclo financeiro.
class CycleFundingPlannerCard extends StatelessWidget {
  final CycleFundingEstimate estimate;

  const CycleFundingPlannerCard({super.key, required this.estimate});

  void _showDetailSheet(BuildContext context, FinanceCubit? cubit) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => cubit == null
          ? _FundingDetailsSheet(estimate: estimate)
          // Ajuste de categoria refaz a estimativa: a folha acompanha o cubit
          : BlocBuilder<FinanceCubit, FinanceState>(
              bloc: cubit,
              builder: (_, state) => _FundingDetailsSheet(
                estimate: state.fundingEstimate ?? estimate,
                cubit: cubit,
              ),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    FinanceCubit? cubit;
    try {
      cubit = context.read<FinanceCubit>();
    } catch (_) {
      cubit = null;
    }
    final adjustPercent =
        cubit?.state.houseSettings.adjustPercent ?? HouseSettings.defaultAdjustPercent;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: AppColors.primary.withValues(alpha: 0.25),
          width: 1.2,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cabeçalho com Ícone e Título
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.savings_rounded,
                    color: AppColors.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Planejamento de Aportes',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      Text(
                        'Contas do ciclo + estimativa de gastos variáveis',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: () => _showDetailSheet(context, cubit),
                  icon: const Icon(Icons.tune_rounded, size: 14),
                  label: const Text(
                    'Detalhes',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: AppColors.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Chips de Seleção de Modo (Média Histórica / Econômico / Com Folga)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ChoiceChip(
                    label: const Text(
                      'Média Histórica',
                      style: TextStyle(fontSize: 11),
                    ),
                    selected:
                        estimate.mode == FundingEstimateMode.historicalAverage,
                    onSelected: (_) => cubit?.updateFundingEstimateMode(
                      FundingEstimateMode.historicalAverage,
                    ),
                  ),
                  const SizedBox(width: 6),
                  ChoiceChip(
                    label: Text(
                      'Econômico (-$adjustPercent%)',
                      style: TextStyle(fontSize: 11),
                    ),
                    selected: estimate.mode == FundingEstimateMode.economical,
                    onSelected: (_) => cubit?.updateFundingEstimateMode(
                      FundingEstimateMode.economical,
                    ),
                  ),
                  const SizedBox(width: 6),
                  ChoiceChip(
                    label: Text(
                      'Com Folga (+$adjustPercent%)',
                      style: TextStyle(fontSize: 11),
                    ),
                    selected: estimate.mode == FundingEstimateMode.comfortable,
                    onSelected: (_) => cubit?.updateFundingEstimateMode(
                      FundingEstimateMode.comfortable,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Total Necessário
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Expanded(
                  child: Text(
                    'Previsão Total do Mês:',
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                PrivacySensitiveText(
                  estimate.totalProjectedExpenses.formatted,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),

            // Sub-detalhamento visual da fórmula
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: theme.brightness == Brightness.dark
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.black.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    size: 12,
                    color: Colors.grey,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${estimate.fixedCommittedExpenses.formatted} fixas + ${estimate.totalVariablesEstimated.formatted} em variáveis (mercado e consumo)'
                      '${estimate.currentHouseBalance.cents > 0 ? " - ${estimate.currentHouseBalance.formatted} de sobra em caixa" : ""}',
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 20),

            // Cotas por Membro
            Text(
              estimate.isSettled
                  ? 'Cotas Gravadas no Fechamento:'
                  : 'Cota Recomendada no Início do Ciclo:',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
            ),
            const SizedBox(height: 8),

            ...estimate.memberQuotes.map(
              (quote) => _buildMemberQuoteRow(context, quote),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMemberQuoteRow(BuildContext context, MemberFundingQuote quote) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          // Nome e regra ocupam o espaço que sobra e quebram linha, para o
          // valor e o botão "Aportar" nunca serem empurrados para fora do card.
          Expanded(
            child: Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                  child: Text(
                    quote.memberName.isNotEmpty ? quote.memberName[0] : '?',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        quote.memberName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        quote.ruleDescription,
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Em tela estreita ou com fonte grande, os valores encolhem em vez
          // de estourar a linha.
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  PrivacySensitiveText(
                    quote.recommendedAmount.formatted,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  if (quote.settledAtClosing)
                    const Text(
                      'Ciclo fechado',
                      style: TextStyle(
                        fontSize: 10,
                        color: AppColors.creditGreen,
                        fontWeight: FontWeight.bold,
                      ),
                    )
                  else if (quote.isFulfilled)
                    const Text(
                      '100% Aportado',
                      style: TextStyle(
                        fontSize: 10,
                        color: AppColors.creditGreen,
                        fontWeight: FontWeight.bold,
                      ),
                    )
                  else if (quote.alreadyContributed.cents > 0 ||
                      quote.paidOutOfPocket.cents > 0)
                    Text(
                      'Falta: ${quote.pendingAmount.formatted}',
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.amber,
                        fontWeight: FontWeight.w600,
                      ),
                    )
                  else
                    const Text(
                      'Pendente',
                      style: TextStyle(fontSize: 10, color: AppColors.debtRed),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (!quote.isFulfilled)
            FilledButton.tonal(
              onPressed: () {
                showAdaptiveModal(
                  context: context,
                  maxWidth: 540,
                  child: AddContributionPage(
                    initialMemberId: quote.memberId,
                    initialAmount: quote.pendingAmount,
                  ),
                );
              },
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                visualDensity: VisualDensity.compact,
              ),
              child: const Text(
                'Aportar',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
    );
  }
}

class _FundingDetailsSheet extends StatelessWidget {
  final CycleFundingEstimate estimate;
  final FinanceCubit? cubit;

  const _FundingDetailsSheet({required this.estimate, this.cubit});

  /// Valor previsto da categoria ajustado à mão (fica guardado na casa).
  void _editCategory(BuildContext context, CategoryFundingEstimate cat) {
    var amount = cat.adjustedAmount;
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text('Previsto para ${cat.categoryName}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Média calculada: ${cat.averageMonthlyAmount.formatted}. O valor que você puser vale para a casa até voltar à média.',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            MoneyInputField(
              initialValue: cat.adjustedAmount,
              label: 'Valor previsto',
              autoFocus: true,
              onChanged: (value) => amount = value,
            ),
          ],
        ),
        actions: [
          if (cat.isOverridden)
            TextButton(
              onPressed: () {
                cubit?.updateCustomCategoryFunding(cat.categoryId, null);
                Navigator.pop(dialogCtx);
              },
              child: const Text('Voltar à média'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              cubit?.updateCustomCategoryFunding(cat.categoryId, amount);
              Navigator.pop(dialogCtx);
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.80,
      ),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(
                      Icons.tune_rounded,
                      color: AppColors.primary,
                      size: 22,
                    ),
                    SizedBox(width: 10),
                    Text(
                      'Memória do Planejamento',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 17,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // 1. Contas Fixas
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Contas Fixas / Provisionadas',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            PrivacySensitiveText(
                              estimate.fixedCommittedExpenses.formatted,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: AppColors.primary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Aluguel, condomínio, internet e assinaturas deste ciclo.',
                          style: TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // 2. Variáveis com Médias Históricas
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Médias de Categorias Variáveis',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            PrivacySensitiveText(
                              estimate.totalVariablesEstimated.formatted,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: AppColors.primary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Estimadas com base no consumo dos ciclos anteriores.',
                          style: TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                        const Divider(height: 16),
                        if (estimate.variableCategoryEstimates.isEmpty)
                          const Text(
                            'Nenhuma categoria variável com histórico recente.',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          )
                        else
                          ...estimate.variableCategoryEstimates.map((cat) {
                            return ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              onTap: cubit == null ? null : () => _editCategory(context, cat),
                              title: Text(
                                cat.categoryName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                              subtitle: Text(
                                'Média de ${cat.sampleCyclesCount} ${cat.sampleCyclesCount == 1 ? 'ciclo' : 'ciclos'}: ${cat.averageMonthlyAmount.formatted}'
                                '${cat.isOverridden ? " (Ajuste manual)" : ""}',
                                style: const TextStyle(fontSize: 11),
                              ),
                              trailing: PrivacySensitiveText(
                                cat.adjustedAmount.formatted,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            );
                          }),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // 3. Saldo em Caixa Abatido
                if (estimate.currentHouseBalance.cents > 0)
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: AppColors.creditGreen.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Sobra do Caixa (Ciclo Anterior)',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                                Text(
                                  'Abatido da necessidade de novos aportes.',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          PrivacySensitiveText(
                            '-${estimate.currentHouseBalance.formatted}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppColors.creditGreen,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
