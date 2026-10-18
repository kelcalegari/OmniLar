import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
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
import '../widgets/cycle_insights_section.dart';
import '../../domain/services/cycle_report_csv.dart';
import '../../domain/services/cycle_report_pdf.dart';
import '../../../auth/domain/repositories/auth_repository.dart';
import '../../domain/entities/cycle_insights.dart';
import '../../../finance/presentation/widgets/house_inflows_card.dart';

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
        if (finance.status == FinanceStatus.success)
          cubit.loadPreview(
            finance,
            schedule: context.read<FinanceCubit>().cycleSchedule,
          );
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
          reports.loadPreview(
            state,
            schedule: context.read<FinanceCubit>().cycleSchedule,
          );
          // Próximos ciclos já abertos: um lançamento novo pode mudar eles
          if (reports.evolutionRequested) {
            reports.loadEvolution(
              state,
              context.read<FinanceCubit>().cycleSchedule,
            );
          }
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
          PopupMenuButton<String>(
            icon: const Icon(Icons.file_download_outlined),
            tooltip: 'Exportar relatório do ciclo',
            onSelected: (format) {
              final state = context.read<FinanceCubit>().state;
              if (format == 'pdf') {
                _exportReportPdf(context, state);
              } else {
                _exportReportCsv(context, state);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'pdf',
                child: ListTile(
                  leading: Icon(Icons.picture_as_pdf_outlined),
                  title: Text('Prestação de contas (PDF)'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'csv',
                child: ListTile(
                  leading: Icon(Icons.table_chart_outlined),
                  title: Text('Planilha (CSV)'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
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
                    if (!state.currentCycle.contains(DateTime.now()))
                      Center(
                        child: TextButton.icon(
                          key: const Key('reports_back_to_current_cycle'),
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            foregroundColor: AppColors.primary,
                          ),
                          icon: const Icon(Icons.today_rounded, size: 16),
                          label: const Text(
                            'Voltar ao ciclo atual',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                          onPressed: cubit.goToCurrentCycle,
                        ),
                      ),
                    // A linha vira barra de progresso enquanto o ciclo escolhido carrega
                    SizedBox(
                      height: 16,
                      child: Center(
                        child: _isSwitchingCycle(state)
                            ? const LinearProgressIndicator(minHeight: 2)
                            : null,
                      ),
                    ),

                    // Esmaece o que ainda é do ciclo anterior até o novo chegar
                    AnimatedOpacity(
                      key: const Key('reports_cycle_content'),
                      opacity: _isSwitchingCycle(state) ? 0.4 : 1,
                      duration: const Duration(milliseconds: 150),
                      child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
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
                                context.read<ReportsCubit>().loadPreview(
                                  state,
                                  schedule: context
                                      .read<FinanceCubit>()
                                      .cycleSchedule,
                                ),
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

                    // Seção: Gastos por Categoria (com o ciclo anterior)
                    BlocBuilder<ReportsCubit, ReportsState>(
                      buildWhen: (a, b) => a.insights != b.insights,
                      builder: (context, reports) => _buildCategoriesSection(
                        context,
                        state,
                        reports.insights,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Seção: Aportes por Membro
                    _buildMembersSection(context, state),
                    const SizedBox(height: 20),

                    // Seção: Entradas de fora (dinheiro no Caixa que não é aporte)
                    HouseInflowsCard(state: state, cubit: cubit),
                    const SizedBox(height: 20),

                    // Quem paga, empréstimos e evolução dos ciclos
                    CycleInsightsSection(
                      categories: state.categories,
                      onEvolutionRequested: () =>
                          context.read<ReportsCubit>().loadEvolution(
                            context.read<FinanceCubit>().state,
                            context.read<FinanceCubit>().cycleSchedule,
                          ),
                    ),
                    const SizedBox(height: 20),

                    // Card de Acesso ao Hub de Fechamento
                    _buildSettlementCard(context),
                    const SizedBox(height: 32),
                  ],
                      ),
                    ),
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

  /// O ciclo mostrado no topo já mudou, mas os números ainda são do anterior.
  bool _isSwitchingCycle(FinanceState state) =>
      state.status == FinanceStatus.loading &&
      state.summary != null &&
      state.summary!.cycle != state.currentCycle;

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
            onPressed: cubit.canGoToPreviousCycle ? cubit.previousCycle : null,
            tooltip: cubit.canGoToPreviousCycle ? 'Ciclo Anterior' : 'Primeiro ciclo da casa',
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

  /// Variação de uma categoria sobre o ciclo anterior: gastar mais é vermelho.
  Widget _changeLabel(double? change) {
    if (change == null) return const SizedBox.shrink();
    final up = change > 0;
    final text = change.abs() < 0.5
        ? '='
        : '${up ? '▲' : '▼'} ${change.abs().toStringAsFixed(0)}%';
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: change.abs() < 0.5
              ? Colors.grey
              : (up ? AppColors.debtRed : AppColors.creditGreen),
        ),
      ),
    );
  }

  Widget _buildCategoriesSection(
    BuildContext context,
    FinanceState state,
    CycleInsights? insights,
  ) {
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
            // Sem lançamento no ciclo anterior não há com o que comparar
            if (insights != null && insights.previousTotal.isPositive) ...[
              const SizedBox(height: 4),
              PrivacySensitiveText(
                'Ciclo anterior: ${insights.previousTotal.formatted} · este ciclo '
                '${totalSpentCents >= insights.previousTotal.cents ? '+' : '−'}'
                '${Money((totalSpentCents - insights.previousTotal.cents).abs()).formatted}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
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
                      _changeLabel(insights?.changeOf(catId, cents)),
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

  /// Aviso depois de salvar. No navegador o arquivo vai direto para os
  /// downloads e o `saveFile` sempre devolve null, então null ali não quer
  /// dizer que a pessoa cancelou.
  String _savedMessage(
    Uri? saved, {
    required String web,
    required String file,
  }) {
    if (kIsWeb) return '$web Veja a pasta de downloads do navegador.';
    return saved == null ? 'Exportação cancelada.' : file;
  }

  /// Salva a prestação de contas do ciclo em PDF, pelo mesmo caminho do CSV.
  Future<void> _exportReportPdf(
    BuildContext context,
    FinanceState state,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final reports = context.read<ReportsCubit>().state;
    final sameCycle = reports.preview?.cycle == state.currentCycle;
    String houseName;
    try {
      houseName = sl<AuthRepository>().currentHouse?.name ?? 'Nossa casa';
    } catch (_) {
      houseName = 'Nossa casa';
    }
    try {
      final bytes = await const CycleReportPdf().build(
        houseName: houseName,
        cycle: state.currentCycle,
        expenses: state.expenses,
        categories: state.categories,
        members: state.members,
        contributions: state.contributions,
        summary: state.summary,
        preview: sameCycle ? reports.preview : null,
        insights: sameCycle ? reports.insights : null,
        generatedAt: DateTime.now(),
      );
      final saved = await FilePicker.saveFile(
        fileName: CycleReportPdf.fileNameFor(state.currentCycle),
        bytes: bytes,
        mimeType: 'application/pdf',
        dialogTitle: 'Salvar prestação de contas',
        allowedExtensions: const ['pdf'],
        type: FileType.custom,
      );
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            _savedMessage(
              saved,
              web: 'Prestação de contas baixada.',
              file: 'Prestação de contas salva.',
            ),
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Não foi possível gerar o PDF: $e')),
      );
    }
  }

  /// Salva o relatório do ciclo em CSV: download no navegador, escolha do
  /// local no celular e no computador.
  Future<void> _exportReportCsv(
    BuildContext context,
    FinanceState state,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final reports = context.read<ReportsCubit>().state;
    // A prévia só vale se for do ciclo que está na tela
    final sameCycle = reports.preview?.cycle == state.currentCycle;
    final csv = const CycleReportCsv().build(
      cycle: state.currentCycle,
      expenses: state.expenses,
      categories: state.categories,
      members: state.members,
      preview: sameCycle ? reports.preview : null,
      calendar: sameCycle ? reports.calendar : null,
    );
    try {
      final saved = await FilePicker.saveFile(
        fileName: CycleReportCsv.fileNameFor(state.currentCycle),
        bytes: Uint8List.fromList(utf8.encode(csv)),
        mimeType: 'text/csv',
        dialogTitle: 'Salvar relatório do ciclo',
        allowedExtensions: const ['csv'],
        type: FileType.custom,
      );
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            _savedMessage(
              saved,
              web: 'Planilha do ciclo baixada.',
              file:
                  'Planilha do ciclo salva (${state.expenses.length} lançamentos).',
            ),
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Não foi possível salvar o relatório: $e')),
      );
    }
  }
}
