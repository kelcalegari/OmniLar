import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/services/transaction_aggregator.dart';

class TransactionsMetricsCard extends StatelessWidget {
  final TransactionAggregatorMetrics metrics;
  final String periodDescription;

  const TransactionsMetricsCard({
    super.key,
    required this.metrics,
    required this.periodDescription,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isPositive = metrics.netBalance.cents >= 0;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.2),
        ),
      ),
      color: isDark ? Colors.grey.shade900 : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Cabeçalho com o período e contagem
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Icon(Icons.calendar_month_outlined, size: 16, color: Colors.grey.shade500),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          periodDescription,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.grey.shade300 : Colors.grey.shade700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${metrics.count} ${metrics.count == 1 ? 'item' : 'itens'}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            // Três colunas: Entradas, Saídas e Saldo Líquido
            Row(
              children: [
                // Entradas
                Expanded(
                  child: _MetricItem(
                    label: 'Entradas',
                    amount: metrics.totalInflows.format(),
                    color: isDark ? Colors.green.shade400 : Colors.green.shade700,
                    icon: Icons.arrow_downward_rounded,
                    prefix: '+ ',
                  ),
                ),
                Container(
                  width: 1,
                  height: 36,
                  color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.grey.shade200,
                ),
                // Saídas
                Expanded(
                  child: _MetricItem(
                    label: 'Saídas',
                    amount: metrics.totalExpenses.format(),
                    color: isDark ? Colors.red.shade400 : AppColors.debtRed,
                    icon: Icons.arrow_upward_rounded,
                    prefix: '- ',
                  ),
                ),
                Container(
                  width: 1,
                  height: 36,
                  color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.grey.shade200,
                ),
                // Saldo Líquido
                Expanded(
                  child: _MetricItem(
                    label: 'Saldo',
                    amount: metrics.netBalance.format(),
                    color: isPositive
                        ? (isDark ? Colors.green.shade400 : Colors.green.shade700)
                        : (isDark ? Colors.red.shade400 : AppColors.debtRed),
                    icon: Icons.account_balance_wallet_outlined,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricItem extends StatelessWidget {
  final String label;
  final String amount;
  final Color color;
  final IconData icon;
  final String prefix;

  const _MetricItem({
    required this.label,
    required this.amount,
    required this.color,
    required this.icon,
    this.prefix = '',
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade500,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            '$prefix$amount',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}
