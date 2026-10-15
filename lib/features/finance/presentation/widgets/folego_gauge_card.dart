import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/privacy_toggle.dart';
import '../../../../core/domain/value_objects/money.dart';
import '../../../../core/domain/value_objects/financial_cycle.dart';
import '../../domain/entities/financial_cycle_summary.dart';

class FolegoGaugeCard extends StatelessWidget {
  final FinancialCycleSummary summary;
  final FinancialCycle cycle;
  final VoidCallback onPreviousCycle;
  final VoidCallback onNextCycle;

  /// Volta ao ciclo em andamento; o atalho só aparece fora dele.
  final VoidCallback? onCurrentCycle;

  /// Os números ainda são do ciclo anterior: o do [cycle] está carregando.
  final bool isLoading;

  /// Fora do ciclo em andamento o selo mostra a situação do ciclo ("Fechado"
  /// ou "Em aberto") em vez da saúde do caixa; null = ainda não se sabe.
  final bool? isCycleSettled;

  const FolegoGaugeCard({
    super.key,
    required this.summary,
    required this.cycle,
    required this.onPreviousCycle,
    required this.onNextCycle,
    this.onCurrentCycle,
    this.isLoading = false,
    this.isCycleSettled,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = summary.status;

    Color statusColor;
    String statusText;
    IconData statusIcon;

    final isCurrentCycle = cycle.contains(DateTime.now());

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
    if (!isCurrentCycle) {
      // Em ciclo passado ou futuro a saúde do caixa não diz nada
      final settled = isCycleSettled == true;
      statusColor = settled ? AppColors.primary : Colors.grey;
      statusText = settled ? 'Fechado' : 'Em aberto';
      statusIcon = settled ? Icons.lock_outline_rounded : Icons.lock_open_rounded;
    }
    final showBadge = isCurrentCycle || isCycleSettled != null;

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
            if (onCurrentCycle != null && !isCurrentCycle)
              Center(
                child: TextButton.icon(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: AppColors.primary,
                  ),
                  icon: const Icon(Icons.today_rounded, size: 16),
                  label: const Text(
                    'Voltar ao ciclo atual',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  onPressed: onCurrentCycle,
                ),
              ),
            // A linha vira barra de progresso enquanto o ciclo escolhido carrega
            SizedBox(
              height: 24,
              child: Center(
                child: isLoading
                    ? const LinearProgressIndicator(minHeight: 2)
                    : const Divider(height: 1),
              ),
            ),

            AnimatedOpacity(
              opacity: isLoading ? 0.4 : 1,
              duration: const Duration(milliseconds: 150),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Cabeçalho Fôlego + Badge
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Fôlego do Caixa',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      if (showBadge)
                      Container(
                        key: const Key('folego_status_badge'),
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
                  PrivacySensitiveText(
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
                      Expanded(
                        child: _buildMetricColumn(
                          context,
                          label: 'Aportes',
                          value: summary.totalContributions.format(),
                          color: AppColors.creditGreen,
                        ),
                      ),
                      Expanded(
                        child: _buildMetricColumn(
                          context,
                          label: 'Despesas Pagas',
                          value: summary.totalExpensesPaid.format(),
                          color: theme.textTheme.bodyLarge?.color,
                        ),
                      ),
                      Expanded(
                        child: _buildMetricColumn(
                          context,
                          label: 'A Vencer',
                          value: summary.committedFutureExpenses.format(),
                          color: AppColors.folegoWarning,
                        ),
                      ),
                    ],
                  ),
                  // Indicador de Gasto Diário Seguro (Burn Rate - Fase 2.1)
                  // Só no ciclo em andamento: em ciclo passado ou futuro não há "dias restantes"
                  if (isCurrentCycle) ...[
                  const SizedBox(height: 14),
                  Builder(
                    builder: (context) {
                      final now = DateTime.now();
                      final end = cycle.endDate;
                      final daysRemaining = end.isAfter(now)
                          ? end.difference(now).inDays + 1
                          : 1;

                      final dailySafeCents = summary.folego.isPositive && daysRemaining > 0
                          ? (summary.folego.cents / daysRemaining).round()
                          : 0;

                      final isComfortable = dailySafeCents >= 5000; // >= R$ 50/dia

                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: (summary.folego.isNegative
                                  ? AppColors.debtRed
                                  : (isComfortable ? AppColors.creditGreen : AppColors.folegoWarning))
                              .withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              summary.folego.isNegative
                                  ? Icons.error_outline_rounded
                                  : (isComfortable ? Icons.speed_rounded : Icons.info_outline_rounded),
                              size: 16,
                              color: summary.folego.isNegative
                                  ? AppColors.debtRed
                                  : (isComfortable ? AppColors.creditGreen : AppColors.folegoWarning),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                summary.folego.isNegative
                                    ? 'Déficit no ciclo: requer novo aporte para reequilibrar'
                                    : 'Gasto diário seguro: ~${Money(dailySafeCents).format()}/dia ($daysRemaining ${daysRemaining == 1 ? 'dia restante' : 'dias restantes'})',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: summary.folego.isNegative
                                      ? AppColors.debtRed
                                      : (isComfortable ? AppColors.creditGreen : AppColors.folegoWarning),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  ],
                ],
              ),
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
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}
