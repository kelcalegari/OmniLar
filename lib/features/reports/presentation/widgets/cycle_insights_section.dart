import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/domain/value_objects/money.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/privacy_toggle.dart';
import '../../../finance/domain/entities/category.dart';
import '../../domain/entities/cycle_insights.dart';
import '../cubit/reports_cubit.dart';

/// Cartões de leitura do ciclo: quem paga as despesas, empréstimos em aberto
/// e a evolução dos últimos ciclos.
class CycleInsightsSection extends StatelessWidget {
  final List<ExpenseCategory> categories;

  /// Pede a carga da evolução (só quando o cartão é aberto).
  final VoidCallback onEvolutionRequested;

  const CycleInsightsSection({
    super.key,
    required this.categories,
    required this.onEvolutionRequested,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ReportsCubit, ReportsState>(
      builder: (context, state) {
        final insights = state.insights;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (insights != null && insights.byPayer.isNotEmpty) ...[
              _whoPays(insights),
              const SizedBox(height: 20),
            ],
            if (insights != null && insights.loanPositions.isNotEmpty) ...[
              _loans(insights.loanPositions),
              const SizedBox(height: 20),
            ],
            _evolution(state),
          ],
        );
      },
    );
  }

  Widget _card({
    required IconData icon,
    required String title,
    String? subtitle,
    required List<Widget> children,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(icon, title, subtitle),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _header(IconData icon, String title, String? subtitle) {
    return Row(
      children: [
        Icon(icon, color: AppColors.primary, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              if (subtitle != null)
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _barRow(
    String label,
    Money amount,
    int totalCents, {
    Color color = AppColors.primary,
  }) {
    final fraction = totalCents > 0
        ? (amount.cents / totalCents).clamp(0.0, 1.0)
        : 0.0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label, style: const TextStyle(fontSize: 13)),
              ),
              Text(
                '${(fraction * 100).toStringAsFixed(0)}%',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
              const SizedBox(width: 10),
              PrivacySensitiveText(
                amount.formatted,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 6,
              color: color,
              backgroundColor: color.withValues(alpha: 0.12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _subtitle(String text) => Padding(
    padding: const EdgeInsets.only(top: 12, bottom: 4),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: Colors.grey,
      ),
    ),
  );

  Widget _whoPays(CycleInsights insights) {
    final total = insights.byPayer.fold<int>(
      0,
      (acc, p) => acc + p.amount.cents,
    );
    return _card(
      icon: Icons.account_balance_wallet_outlined,
      title: 'Quem paga as despesas',
      subtitle:
          'Inclui faturas e contas em aberto, pela escolha padrão do fechamento',
      children: [
        for (final p in insights.byPayer)
          _barRow(
            p.memberId == null
                ? p.name
                : '${p.name} (do bolso, volta no fechamento)',
            p.amount,
            total,
            color: p.memberId == null
                ? AppColors.primary
                : AppColors.creditGreen,
          ),
        if (insights.byMethod.isNotEmpty) ...[
          _subtitle('Por forma de pagamento'),
          for (final m in insights.byMethod) _barRow(m.name, m.amount, total),
        ],
        _subtitle('Recorrentes e avulsas'),
        _barRow('Contas recorrentes', insights.recurring, total),
        _barRow('Despesas avulsas', insights.oneOff, total),
      ],
    );
  }

  Widget _loans(List<LoanPosition> positions) {
    return _card(
      icon: Icons.handshake_outlined,
      title: 'Empréstimos em aberto',
      children: [
        for (final p in positions)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  p.name,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Expanded(
                      child: _amount(
                        'A receber',
                        p.toReceive,
                        AppColors.creditGreen,
                      ),
                    ),
                    Expanded(
                      child: _amount('A pagar', p.toPay, AppColors.debtRed),
                    ),
                    Expanded(
                      child: _amount('Já pagou', p.alreadyPaid, Colors.grey),
                    ),
                  ],
                ),
                if (p.overdueInstallments > 0)
                  Text(
                    '${p.overdueInstallments} '
                    '${p.overdueInstallments == 1 ? 'parcela vencida' : 'parcelas vencidas'} a pagar',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.debtRed,
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _amount(String label, Money amount, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        PrivacySensitiveText(
          amount.formatted,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _evolution(ReportsState state) {
    final evolution = state.evolution;
    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      child: ExpansionTile(
        leading: const Icon(Icons.show_chart_rounded, color: AppColors.primary),
        title: const Text(
          'Evolução dos últimos ciclos',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        subtitle: const Text(
          'Total de cada ciclo e a categoria que mais pesou',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        shape: const Border(),
        collapsedShape: const Border(),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        onExpansionChanged: (open) {
          if (open && evolution == null && !state.evolutionLoading)
            onEvolutionRequested();
        },
        children: [
          if (state.evolutionLoading && evolution == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (evolution == null && state.evolutionError != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  state.evolutionError!,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.debtRed,
                  ),
                ),
                TextButton.icon(
                  onPressed: onEvolutionRequested,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Tentar de novo'),
                ),
              ],
            )
          else if (evolution != null)
            ..._evolutionRows(evolution),
        ],
      ),
    );
  }

  List<Widget> _evolutionRows(List<CycleTotal> totals) {
    final max = totals.fold<int>(
      0,
      (acc, t) => t.total.cents > acc ? t.total.cents : acc,
    );
    final names = {for (final c in categories) c.id: c.name};
    return [
      for (final t in totals.reversed)
        Builder(
          builder: (context) {
            String? topCategory;
            var topCents = 0;
            for (final entry in t.byCategory.entries) {
              if (entry.value > topCents) {
                topCents = entry.value;
                topCategory = entry.key;
              }
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _barRow(t.cycle.formattedPeriod, t.total, max),
                if (topCategory != null)
                  PrivacySensitiveText(
                    'Maior: ${names[topCategory] ?? 'Outros'} ${Money(topCents).formatted}',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
              ],
            );
          },
        ),
    ];
  }
}
