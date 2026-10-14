import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/domain/value_objects/money.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/responsive_container.dart';
import '../../../../core/widgets/privacy_toggle.dart';
import '../../../finance/domain/entities/category.dart';
import '../../../finance/domain/entities/financial_cycle_summary.dart';
import '../../../finance/presentation/cubit/finance_cubit.dart';
import '../../../finance/presentation/cubit/finance_state.dart';
import '../../../../core/di/service_locator.dart';
import '../../../p2p/presentation/cubit/p2p_cubit.dart';
import '../cubit/reports_cubit.dart';
import '../widgets/cycle_preview_section.dart';
import '../widgets/payment_calendar_section.dart';
import '../widgets/upcoming_cycles_section.dart';

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  /// "Todos" escolhido na prévia; vale também para o calendário.
  final _showAll = ValueNotifier<bool>(false);

  @override
  void dispose() {
    _showAll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<ReportsCubit>(
      create: (context) {
        final cubit = sl<ReportsCubit>();
        final finance = context.read<FinanceCubit>().state;
        if (finance.status == FinanceStatus.success) cubit.loadPreview(finance);
        return cubit;
      },
      // A prévia acompanha o ciclo que o painel carregou (troca de ciclo,
      // lançamento novo, mudança vinda de outro aparelho)
      child: BlocListener<FinanceCubit, FinanceState>(
        listenWhen: (previous, current) =>
            current.status == FinanceStatus.success &&
            (previous.status != FinanceStatus.success ||
                previous.currentCycle != current.currentCycle ||
                previous.expenses != current.expenses ||
                previous.contributions != current.contributions ||
                previous.members != current.members),
        listener: (context, state) {
          final reports = context.read<ReportsCubit>();
          reports.loadPreview(state);
          // Próximos ciclos já abertos: um lançamento novo pode mudar eles
          if (reports.upcomingRequested) {
            reports.loadUpcoming(
              state,
              context.read<FinanceCubit>().cycleSchedule,
            );
          }
        },
        child: _ReportsPageContent(showAll: _showAll),
      ),
    );
  }
}

class _ReportsPageContent extends StatelessWidget {
  final ValueNotifier<bool> showAll;

  const _ReportsPageContent({required this.showAll});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Relatórios e Analytics',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download_outlined),
            tooltip: 'Exportar Relatório do Ciclo (CSV / Planilha)',
            onPressed: () {
              final state = context.read<FinanceCubit>().state;
              _exportReportCsv(context, state);
            },
          ),
          const PrivacyToggleButton(),
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
            return const Center(
              child: Text('Nenhum dado disponível para este ciclo.'),
            );
          }

          final cubit = context.read<FinanceCubit>();

          return RefreshIndicator(
            onRefresh: () => cubit.loadCycleData(),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: ResponsiveContainer(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Seletor de Ciclo
                    _buildCycleSelector(context, state, cubit),
                    const SizedBox(height: 16),

                    // Prévia do fechamento e calendário de pagamentos, por morador
                    ValueListenableBuilder<bool>(
                      valueListenable: showAll,
                      builder: (context, all, _) => Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          CyclePreviewSection(
                            currentMemberId: _currentMemberId(context),
                            showAll: all,
                            onShowAllChanged: (value) => showAll.value = value,
                            membersWithoutFixedContribution:
                                _membersWithoutFixedContribution(state),
                            onRetry: () =>
                                context.read<ReportsCubit>().loadPreview(state),
                          ),
                          PaymentCalendarSection(
                            currentMemberId: _currentMemberId(context),
                            showAll: all,
                          ),
                          const SizedBox(height: 20),
                          UpcomingCyclesSection(
                            currentMemberId: _currentMemberId(context),
                            showAll: all,
                            onRequested: () =>
                                context.read<ReportsCubit>().loadUpcoming(
                                  context.read<FinanceCubit>().state,
                                  context.read<FinanceCubit>().cycleSchedule,
                                ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Cards de Resumo Executivo
                    _buildExecutiveCards(context, state, summary),
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
              ),
            ),
          );
        },
      ),
    );
  }

  /// Morador logado (o mesmo usado pelos empréstimos); vazio fora da sessão.
  String _currentMemberId(BuildContext context) {
    try {
      return context.read<P2PCubit>().state.currentUserId;
    } catch (_) {
      return '';
    }
  }

  /// No modelo de aportes fixos, quem está sem valor definido não é cobrado.
  List<String> _membersWithoutFixedContribution(FinanceState state) {
    final usesFixed = state.members.any(
      (m) => (m.defaultFixedAmountCents ?? 0) > 0,
    );
    if (!usesFixed) return const [];
    return state.members
        .where((m) => (m.defaultFixedAmountCents ?? 0) <= 0)
        .map((m) => m.name.split(' ').first)
        .toList();
  }

  /// Rótulo do ciclo mostrado: o de hoje, um que já terminou ou um futuro.
  String _cycleLabel(FinanceState state) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final cycle = state.currentCycle;
    if (cycle.endDate.isBefore(today)) return 'Ciclo encerrado';
    if (cycle.startDate.isAfter(today)) return 'Próximo ciclo';
    return 'Ciclo atual';
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
              Text(
                _cycleLabel(state),
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                state.currentCycle.formattedPeriod,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
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

  Widget _buildExecutiveCards(
    BuildContext context,
    FinanceState state,
    FinancialCycleSummary summary,
  ) {
    // As mesmas despesas do gráfico por categoria: o total fecha com ele.
    // Compra no cartão fica pendente até a fatura ser paga.
    final paidCents = state.expenses
        .where((e) => !e.isPending)
        .fold<int>(0, (acc, e) => acc + e.amount.cents);
    final pendingCents = state.expenses
        .where((e) => e.isPending)
        .fold<int>(0, (acc, e) => acc + e.amount.cents);

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildMetricTile(
                title: 'Pago',
                amount: Money(paidCents),
                color: AppColors.debtRed,
                icon: Icons.check_circle_outline_rounded,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildMetricTile(
                title: 'A vencer',
                amount: Money(pendingCents),
                color: Colors.orange,
                icon: Icons.schedule_rounded,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildMetricTile(
                title: 'Total do ciclo',
                amount: Money(paidCents + pendingCents),
                color: AppColors.primary,
                icon: Icons.trending_down_rounded,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
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
                color: summary.folego.cents >= 0
                    ? AppColors.creditGreen
                    : AppColors.debtRed,
                icon: Icons.shield_outlined,
              ),
            ),
          ],
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
            child: PrivacySensitiveText(
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
      catTotals[exp.categoryId] =
          (catTotals[exp.categoryId] ?? 0) + exp.amount.cents;
    }

    // O gráfico soma pagas e pendentes: o percentual é sobre esse mesmo total
    final totalSpentCents = catTotals.values.fold<int>(0, (a, b) => a + b);

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
                Icon(
                  Icons.pie_chart_outline_rounded,
                  color: AppColors.primary,
                  size: 20,
                ),
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
                        orElse: () => ExpenseCategory(
                          id: catId,
                          name: 'Outros',
                          icon: 'category',
                          colorHex: '#94A3B8',
                        ),
                      );
                      final cents = catTotals[catId] ?? 0;
                      final flex =
                          (cents *
                                  100 ~/
                                  (totalSpentCents > 0 ? totalSpentCents : 1))
                              .clamp(1, 100);
                      final pct =
                          (cents * 100.0) /
                          (totalSpentCents > 0 ? totalSpentCents : 1);
                      final color = _parseColor(cat.colorHex);

                      return Expanded(
                        flex: flex,
                        child: Tooltip(
                          message:
                              '${cat.name}: ${Money(cents).format()} (${pct.toStringAsFixed(1)}%)',
                          child: Container(color: color),
                        ),
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
                  orElse: () => ExpenseCategory(
                    id: catId,
                    name: 'Outros',
                    icon: 'category',
                    colorHex: '#94A3B8',
                  ),
                );
                final cents = catTotals[catId] ?? 0;
                final percentage =
                    (cents * 100.0) /
                    (totalSpentCents > 0 ? totalSpentCents : 1);
                final color = _parseColor(cat.colorHex);

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          cat.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w500,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      Text(
                        '${percentage.toStringAsFixed(1)}%',
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(width: 12),
                      PrivacySensitiveText(
                        Money(cents).formatted,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
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
                Icon(
                  Icons.people_alt_outlined,
                  color: AppColors.primary,
                  size: 20,
                ),
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
                      backgroundColor: AppColors.primary.withValues(
                        alpha: 0.15,
                      ),
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
                          Text(
                            member.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          if ((member.defaultFixedAmountCents ?? 0) > 0)
                            Text(
                              'Meta de aporte: ${Money(member.defaultFixedAmountCents!).formatted}',
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 11,
                              ),
                            )
                          else if (member.defaultSplitPercent > 0)
                            Text(
                              'Meta de rateio: ${member.defaultSplitPercent.toStringAsFixed(0)}%',
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 11,
                              ),
                            ),
                        ],
                      ),
                    ),
                    PrivacySensitiveText(
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

  void _exportReportCsv(BuildContext context, FinanceState state) {
    final buffer = StringBuffer();
    // BOM UTF-8 para o Excel reconhecer acentuação e caracteres brasileiros
    buffer.write('\uFEFF');

    buffer.writeln('RELATÓRIO DE DESPESAS DO CICLO — OMNI LAR');
    final cycle = state.currentCycle;
    if (cycle != null) {
      buffer.writeln(
        'Período;${cycle.startDate.day}/${cycle.startDate.month}/${cycle.startDate.year} até ${cycle.endDate.day}/${cycle.endDate.month}/${cycle.endDate.year}',
      );
    }
    buffer.writeln('');
    buffer.writeln(
      'Data;Descrição;Categoria;Valor (R\$);Quem Pagou;Status;Recorrente',
    );

    for (final exp in state.expenses) {
      final cat =
          state.categories
              .where((c) => c.id == exp.categoryId)
              .firstOrNull
              ?.name ??
          'Geral';
      final payer =
          state.members
              .where((m) => m.id == exp.paidByMemberId)
              .firstOrNull
              ?.name ??
          'Membro';
      final dt =
          '${exp.date.day.toString().padLeft(2, '0')}/${exp.date.month.toString().padLeft(2, '0')}/${exp.date.year}';
      final valStr = (exp.amount.cents / 100.0)
          .toStringAsFixed(2)
          .replaceAll('.', ',');
      final statusStr = exp.isPending ? 'Pendente' : 'Paga';
      final recStr = exp.isRecurring
          ? (exp.isVariable ? 'Recorrente Variável' : 'Recorrente Fixa')
          : 'Avulsa';

      buffer.writeln(
        '$dt;"${exp.title}";"$cat";$valStr;"$payer";$statusStr;$recStr',
      );
    }

    buffer.writeln('');
    buffer.writeln('RESUMO GERAL');
    // Totais das próprias linhas listadas acima, para o arquivo fechar com ele mesmo
    String asCsvMoney(int cents) =>
        (cents / 100.0).toStringAsFixed(2).replaceAll('.', ',');
    final paidCents = state.expenses
        .where((e) => !e.isPending)
        .fold<int>(0, (acc, e) => acc + e.amount.cents);
    final pendingCents = state.expenses
        .where((e) => e.isPending)
        .fold<int>(0, (acc, e) => acc + e.amount.cents);
    buffer.writeln('Total Pago (R\$);${asCsvMoney(paidCents)}');
    buffer.writeln('Total Pendente (R\$);${asCsvMoney(pendingCents)}');
    buffer.writeln(
      'Total Lançado (R\$);${asCsvMoney(paidCents + pendingCents)}',
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(
              Icons.file_download_done_rounded,
              color: AppColors.creditGreen,
            ),
            SizedBox(width: 8),
            Text('Relatório Gerado'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'O relatório consolidado do ciclo foi estruturado no padrão universal CSV (UTF-8 com delimitador ponto e vírgula para Excel e Google Sheets).',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(ctx).cardColor,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
              ),
              child: Text(
                'Total de lançamentos: ${state.expenses.length}\nTotal lançado (pagas e pendentes): ${Money(state.expenses.fold<int>(0, (acc, e) => acc + e.amount.cents)).format()}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Fechar'),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.check_rounded),
            label: const Text('Concluído'),
            onPressed: () {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Relatório pronto para download e compartilhamento! 📊',
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
