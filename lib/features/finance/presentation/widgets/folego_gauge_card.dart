import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/domain/value_objects/financial_cycle.dart';
import '../../domain/entities/financial_cycle_summary.dart';

class FolegoGaugeCard extends StatelessWidget {
  final FinancialCycleSummary summary;
  final FinancialCycle cycle;
  final VoidCallback onPreviousCycle;
  final VoidCallback onNextCycle;

  const FolegoGaugeCard({
    super.key,
    required this.summary,
    required this.cycle,
    required this.onPreviousCycle,
    required this.onNextCycle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = summary.status;

    Color statusColor;
    String statusText;
    IconData statusIcon;

    switch (status) {
      case FolegoStatus.positive:
        statusColor = AppColors.folegoPositive;
        statusText = 'Saudável';
        statusIcon = Icons.check_circle_outline_rounded;
        break;
      case FolegoStatus.warning:
        statusColor = AppColors.folegoWarning;
        statusText = 'Atenção';
        statusIcon = Icons.warning_amber_rounded;
        break;
      case FolegoStatus.danger:
        statusColor = AppColors.folegoDanger;
        statusText = 'Comprometido';
        statusIcon = Icons.error_outline_rounded;
        break;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Seletor de Ciclo
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left_rounded),
                  onPressed: onPreviousCycle,
                  tooltip: 'Ciclo anterior',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                Text(
                  cycle.label,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right_rounded),
                  onPressed: onNextCycle,
                  tooltip: 'Próximo ciclo',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const Divider(height: 24),

            // Cabeçalho Fôlego + Badge
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Fôlego do Caixa',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(statusIcon, size: 14, color: statusColor),
                      const SizedBox(width: 4),
                      Text(
                        statusText,
                        style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Valor Principal do Fôlego
            Text(
              summary.folego.format(),
              style: TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.bold,
                letterSpacing: -0.5,
                color: summary.folego.isNegative ? AppColors.debtRed : null,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Saldo livre após reservar o que vence no ciclo',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 18),

            // Barra de Progresso / Comprometimento
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: summary.commitmentPercentage,
                minHeight: 8,
                backgroundColor: theme.brightness == Brightness.dark
                    ? Colors.white10
                    : Colors.black.withValues(alpha: 0.06),
                valueColor: AlwaysStoppedAnimation<Color>(
                  summary.commitmentPercentage > 0.85
                      ? AppColors.folegoDanger
                      : (summary.commitmentPercentage > 0.65
                          ? AppColors.folegoWarning
                          : AppColors.primary),
                ),
              ),
            ),
            const SizedBox(height: 18),

            // Detalhamento em 3 colunas (Aportes / Pagos / Provisionados)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildMetricColumn(
                  context,
                  label: 'Aportes',
                  value: summary.totalContributions.format(),
                  color: AppColors.creditGreen,
                ),
                _buildMetricColumn(
                  context,
                  label: 'Despesas Pagas',
                  value: summary.totalExpensesPaid.format(),
                  color: theme.textTheme.bodyLarge?.color,
                ),
                _buildMetricColumn(
                  context,
                  label: 'A Vencer',
                  value: summary.committedFutureExpenses.format(),
                  color: AppColors.folegoWarning,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricColumn(
    BuildContext context, {
    required String label,
    required String value,
    Color? color,
  }) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }
}
