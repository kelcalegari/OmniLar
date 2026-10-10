import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../core/domain/value_objects/money.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../finance/domain/entities/category.dart';
import '../../../finance/domain/entities/financial_cycle_summary.dart';
import '../../../finance/presentation/cubit/finance_cubit.dart';
import '../../../finance/presentation/cubit/finance_state.dart';

class ReportsPage extends StatelessWidget {
  const ReportsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const _ReportsPageContent();
  }
}

class _ReportsPageContent extends StatelessWidget {
  const _ReportsPageContent();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Relatórios e Analytics', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on_rounded, color: AppColors.primary),
            tooltip: 'Hub de Liquidação',
            onPressed: () => context.push('/fechamento'),
          ),
        ],
      ),
      body: BlocBuilder<FinanceCubit, FinanceState>(
        builder: (context, state) {
          if (state.status == FinanceStatus.loading && state.summary == null) {
            return const Center(child: CircularProgressIndicator());
          }

          final summary = state.summary;
          if (summary == null) {
            return const Center(child: Text('Nenhum dado disponível para este ciclo.'));
          }

          final cubit = context.read<FinanceCubit>();

          return RefreshIndicator(
            onRefresh: () => cubit.loadCycleData(),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Seletor de Ciclo
                _buildCycleSelector(context, state, cubit),
                const SizedBox(height: 16),

                // Cards de Resumo Executivo
                _buildExecutiveCards(context, summary),
                const SizedBox(height: 20),

                // Seção: Gastos por Categoria
                _buildCategoriesSection(context, state),
                const SizedBox(height: 20),

                // Seção: Aportes por Membro
                _buildMembersSection(context, state),
                const SizedBox(height: 20),

                // Card de Acesso ao Hub de Fechamento
                _buildSettlementCard(context),
                const SizedBox(height: 32),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildCycleSelector(
    BuildContext context,
    FinanceState state,
    FinanceCubit cubit,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left_rounded),
            onPressed: cubit.previousCycle,
            tooltip: 'Ciclo Anterior',
          ),
          Column(
            children: [
              const Text(
                'Ciclo Atual',
                style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w600),
              ),
              Text(
                state.currentCycle.formattedPeriod,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right_rounded),
            onPressed: cubit.nextCycle,
            tooltip: 'Próximo Ciclo',
          ),
        ],
      ),
    );
  }

  Widget _buildExecutiveCards(BuildContext context, FinancialCycleSummary summary) {
    return Row(
      children: [
        Expanded(
          child: _buildMetricTile(
            title: 'Despesas',
            amount: summary.totalSpent,
            color: AppColors.debtRed,
            icon: Icons.trending_down_rounded,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildMetricTile(
            title: 'Aportes',
            amount: summary.totalContributed,
            color: AppColors.creditGreen,
            icon: Icons.trending_up_rounded,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildMetricTile(
            title: 'Fôlego',
            amount: summary.folego,
            color: summary.folego.cents >= 0 ? AppColors.creditGreen : AppColors.debtRed,
            icon: Icons.shield_outlined,
          ),
        ),
      ],
    );
  }

  Widget _buildMetricTile({
    required String title,
    required Money amount,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 6),
          Text(title, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              amount.formatted,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoriesSection(BuildContext context, FinanceState state) {
    final expenses = state.expenses;
    final categories = state.categories;

    // Agrupa despesas por categoria
    final Map<String, int> catTotals = {};
    for (final exp in expenses) {
      catTotals[exp.categoryId] = (catTotals[exp.categoryId] ?? 0) + exp.amount.cents;
    }

    final totalSpentCents = state.summary?.totalSpent.cents ?? 1;

    // Ordena do maior para o menor
    final sortedCatIds = catTotals.keys.toList()
      ..sort((a, b) => (catTotals[b] ?? 0).compareTo(catTotals[a] ?? 0));

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
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Gastos por Categoria',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                Icon(Icons.pie_chart_outline_rounded, color: AppColors.primary, size: 20),
              ],
            ),
            const SizedBox(height: 16),

            // Barra visual de progresso proporcional
            if (sortedCatIds.isNotEmpty) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  height: 12,
                  child: Row(
                    children: sortedCatIds.map((catId) {
                      final cat = categories.firstWhere(
                        (c) => c.id == catId,
                        orElse: () => ExpenseCategory(id: catId, name: 'Outros', icon: 'category', colorHex: '#94A3B8'),
                      );
                      final cents = catTotals[catId] ?? 0;
                      final flex = (cents * 100 ~/ (totalSpentCents > 0 ? totalSpentCents : 1)).clamp(1, 100);
                      final color = _parseColor(cat.colorHex);

                      return Expanded(
                        flex: flex,
                        child: Container(color: color),
                      );
                    }).toList(),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Lista detalhada
            if (sortedCatIds.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('Nenhuma despesa registrada neste ciclo.'),
                ),
              )
            else
              ...sortedCatIds.map((catId) {
                final cat = categories.firstWhere(
                  (c) => c.id == catId,
                  orElse: () => ExpenseCategory(id: catId, name: 'Outros', icon: 'category', colorHex: '#94A3B8'),
                );
                final cents = catTotals[catId] ?? 0;
                final percentage = (cents * 100.0) / (totalSpentCents > 0 ? totalSpentCents : 1);
                final color = _parseColor(cat.colorHex);

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          cat.name,
                          style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
                        ),
                      ),
                      Text(
                        '${percentage.toStringAsFixed(1)}%',
                        style: const TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        Money(cents).formatted,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
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

  Widget _buildMembersSection(BuildContext context, FinanceState state) {
    final members = state.members;
    final contributions = state.contributions;

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
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Aportes Realizados por Membro',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                Icon(Icons.people_alt_outlined, color: AppColors.primary, size: 20),
              ],
            ),
            const SizedBox(height: 16),
            ...members.map((member) {
              final paidCents = contributions
                  .where((c) => c.memberId == member.id)
                  .fold<int>(0, (acc, c) => acc + c.amount.cents);

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                      child: Text(
                        member.name[0],
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(member.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          if (member.defaultSplitPercent != null)
                            Text(
                              'Meta de rateio: ${member.defaultSplitPercent!.toStringAsFixed(0)}%',
                              style: const TextStyle(color: Colors.grey, fontSize: 11),
                            ),
                        ],
                      ),
                    ),
                    Text(
                      Money(paidCents).formatted,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColors.creditGreen,
                        fontSize: 14,
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

  Widget _buildSettlementCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary.withValues(alpha: 0.1),
            AppColors.primaryLight.withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.flash_on_rounded, color: Colors.white),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pronto para fechar o ciclo?',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                Text(
                  'Gere o Super Pix e faça a liquidação unificada.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
          FilledButton(
            onPressed: () => context.push('/fechamento'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              visualDensity: VisualDensity.compact,
            ),
            child: const Text('Abrir Hub', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Color _parseColor(String? hex) {
    if (hex == null || !hex.startsWith('#')) return AppColors.primary;
    final cleanHex = hex.replaceFirst('#', '');
    return Color(int.parse('FF$cleanHex', radix: 16));
  }
}
