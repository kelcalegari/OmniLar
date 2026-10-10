import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/responsive.dart';
import '../../../../core/widgets/privacy_toggle.dart';
import '../../../../core/widgets/responsive_container.dart';
import '../../../finance/presentation/cubit/finance_cubit.dart';
import '../../../finance/presentation/cubit/finance_state.dart';
import '../../../finance/presentation/widgets/folego_gauge_card.dart';
import '../../../finance/presentation/widgets/expense_timeline_item.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const _HomePageContent();
  }
}

class _HomePageContent extends StatelessWidget {
  const _HomePageContent();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDesktop = context.isDesktop;

    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Nossa Casa', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            Text('Carlos & Marina', style: TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
        actions: [
          const PrivacyToggleButton(),
          IconButton(
            icon: const Icon(Icons.notifications_none_rounded),
            onPressed: () {},
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
            return const Center(child: Text('Nenhum dado encontrado para o ciclo.'));
          }

          final cubit = context.read<FinanceCubit>();

          return RefreshIndicator(
            onRefresh: () => cubit.loadCycleData(),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: ResponsiveContainer(
                child: isDesktop
                    ? _buildWideLayout(context, theme, state, summary, cubit)
                    : _buildMobileLayout(context, theme, state, summary, cubit),
              ),
            ),
          );
        },
      ),
    );
  }

  // Layout Mobile (1 coluna vertical)
  Widget _buildMobileLayout(
    BuildContext context,
    ThemeData theme,
    FinanceState state,
    dynamic summary,
    FinanceCubit cubit,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FolegoGaugeCard(
          summary: summary,
          cycle: state.currentCycle,
          onPreviousCycle: cubit.previousCycle,
          onNextCycle: cubit.nextCycle,
        ),
        const SizedBox(height: 16),
        _buildSettlementCard(context),
        const SizedBox(height: 16),
        _buildQuickShortcuts(context, theme),
        const SizedBox(height: 24),
        _buildExpensesSection(theme, state),
        const SizedBox(height: 80),
      ],
    );
  }

  // Layout Desktop / Wide (2 colunas lado a lado)
  Widget _buildWideLayout(
    BuildContext context,
    ThemeData theme,
    FinanceState state,
    dynamic summary,
    FinanceCubit cubit,
  ) {
    final isUltra = context.isUltraWide;

    if (isUltra) {
      // Layout 3 Colunas Ultra-Wide
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Coluna 1: Fôlego & Fechamento
              Expanded(
                flex: 4,
                child: Column(
                  children: [
                    FolegoGaugeCard(
                      summary: summary,
                      cycle: state.currentCycle,
                      onPreviousCycle: cubit.previousCycle,
                      onNextCycle: cubit.nextCycle,
                    ),
                    const SizedBox(height: 16),
                    _buildSettlementCard(context),
                  ],
                ),
              ),
              const SizedBox(width: 20),
              // Coluna 2: Gastos do Ciclo (Timeline)
              Expanded(
                flex: 5,
                child: Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: Colors.grey.withValues(alpha: 0.15)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: _buildExpensesSection(theme, state),
                  ),
                ),
              ),
              const SizedBox(width: 20),
              // Coluna 3: Visão de Rotina & Compras da Casa
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: Colors.grey.withValues(alpha: 0.15)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.flash_auto_rounded, color: AppColors.accent, size: 20),
                                SizedBox(width: 8),
                                Text('Rotina da Casa', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                              ],
                            ),
                            const SizedBox(height: 14),
                            _buildQuickShortcuts(context, theme),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 40),
        ],
      );
    }

    // Layout 2 Colunas Regular Desktop
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Coluna Esquerda: Termômetro + Super Pix + Acessos Rápidos
            Expanded(
              flex: 5,
              child: Column(
                children: [
                  FolegoGaugeCard(
                    summary: summary,
                    cycle: state.currentCycle,
                    onPreviousCycle: cubit.previousCycle,
                    onNextCycle: cubit.nextCycle,
                  ),
                  const SizedBox(height: 16),
                  _buildSettlementCard(context),
                  const SizedBox(height: 16),
                  _buildQuickShortcuts(context, theme),
                ],
              ),
            ),
            const SizedBox(width: 24),
            // Coluna Direita: Gastos do Ciclo
            Expanded(
              flex: 6,
              child: Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: Colors.grey.withValues(alpha: 0.15)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: _buildExpensesSection(theme, state),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _buildSettlementCard(BuildContext context) {
    return InkWell(
      onTap: () => context.push('/fechamento'),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.primary.withValues(alpha: 0.12),
              AppColors.primaryLight.withValues(alpha: 0.08),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.flash_on_rounded, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Fechamento do Ciclo',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  Text(
                    'Compensar gastos da casa e empréstimos em um só Pix',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.primary),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickShortcuts(BuildContext context, ThemeData theme) {
    return Row(
      children: [
        Expanded(
          child: InkWell(
            onTap: () => context.push('/compras'),
            borderRadius: BorderRadius.circular(12),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Icon(Icons.shopping_bag_outlined, color: AppColors.primaryLight, size: 20),
                        Icon(Icons.chevron_right_rounded, size: 16, color: Colors.grey),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text('Compras', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    Text('4 itens', style: theme.textTheme.bodySmall?.copyWith(fontSize: 11)),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: InkWell(
            onTap: () => context.push('/caixinhas'),
            borderRadius: BorderRadius.circular(12),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Icon(Icons.savings_outlined, color: Colors.teal, size: 20),
                        Icon(Icons.chevron_right_rounded, size: 16, color: Colors.grey),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text('Caixinhas', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    Text('Metas da casa', style: theme.textTheme.bodySmall?.copyWith(fontSize: 11)),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: InkWell(
            onTap: () => context.go('/agenda'),
            borderRadius: BorderRadius.circular(12),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Icon(Icons.task_alt_rounded, color: AppColors.accent, size: 20),
                        Icon(Icons.chevron_right_rounded, size: 16, color: Colors.grey),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text('Tarefas', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    Text('2 hoje', style: theme.textTheme.bodySmall?.copyWith(fontSize: 11)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildExpensesSection(ThemeData theme, FinanceState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Gastos do Ciclo',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            Text(
              '${state.expenses.length} lançamentos',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (state.expenses.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            alignment: Alignment.center,
            child: const Text('Nenhuma despesa lançada neste ciclo'),
          )
        else
          ...state.expenses.map((expense) {
            final category = state.categories.firstWhere(
              (c) => c.id == expense.categoryId,
              orElse: () => state.categories.first,
            );
            final paymentMethod = state.paymentMethods.firstWhere(
              (pm) => pm.id == expense.paymentMethodId,
              orElse: () => state.paymentMethods.first,
            );
            final paidByMember = state.members.firstWhere(
              (m) => m.id == expense.paidByMemberId,
              orElse: () => state.members.first,
            );

            return ExpenseTimelineItem(
              expense: expense,
              category: category,
              paymentMethod: paymentMethod,
              paidByMember: paidByMember,
            );
          }),
      ],
    );
  }
}
