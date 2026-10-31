import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../core/domain/value_objects/financial_cycle.dart';
import '../../../../core/domain/value_objects/money.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/responsive.dart';
import '../../../auth/presentation/cubit/auth_cubit.dart';
import '../../domain/entities/contribution.dart';
import '../../domain/entities/house_expense.dart';
import '../../domain/entities/house_inflow.dart';
import '../../domain/entities/house_transaction.dart';
import '../../domain/services/transaction_aggregator.dart';
import '../../domain/services/transactions_export_service.dart';
import '../../domain/value_objects/transaction_filter.dart';
import '../cubit/finance_cubit.dart';
import '../cubit/transactions_cubit.dart';
import '../cubit/transactions_state.dart';
import '../widgets/house_inflows_card.dart';
import '../widgets/transactions_filter_sheet.dart';
import '../widgets/transactions_metrics_card.dart';
import '../widgets/reconcile_cash_modal.dart';
import '../widgets/transaction_tile.dart';
import 'add_contribution_page.dart';
import 'add_expense_page.dart';

class TransactionsPage extends StatefulWidget {
  final FinancialCycle? initialCycle;

  const TransactionsPage({super.key, this.initialCycle});

  @override
  State<TransactionsPage> createState() => _TransactionsPageState();
}

class _TransactionsPageState extends State<TransactionsPage> {
  final _searchController = TextEditingController();
  bool _isSearching = false;

  final _dateHeaderFormat = DateFormat("EEEE, d 'de' MMMM", 'pt_BR');
  final _yearHeaderFormat = DateFormat("d 'de' MMMM 'de' yyyy", 'pt_BR');

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _openDetails(BuildContext context, HouseTransaction transaction, TransactionsCubit cubit) async {
    final raw = transaction.rawEntity;
    final financeCubit = context.read<FinanceCubit>();

    if (raw is HouseExpense) {
      await showAdaptiveModal(
        context: context,
        maxWidth: 540,
        child: AddExpensePage(expenseToEdit: raw),
      );
      cubit.refresh();
      if (context.mounted) {
        financeCubit.loadCycleData();
      }
    } else if (raw is Contribution) {
      await showAdaptiveModal(
        context: context,
        maxWidth: 540,
        child: AddContributionPage(editing: raw),
      );
      cubit.refresh();
      if (context.mounted) {
        financeCubit.loadCycleData();
      }
    } else if (raw is HouseInflow) {
      final changed = await showHouseInflowForm(
        context,
        financeCubit,
        financeCubit.state,
        editing: raw,
      );
      if (changed) {
        cubit.refresh();
      }
    } else {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(transaction.title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Tipo: ${transaction.isExpense ? 'Saída / Despesa' : 'Entrada / Aporte'}'),
              const SizedBox(height: 6),
              Text('Valor: ${transaction.amount.format()}'),
              const SizedBox(height: 6),
              Text('Data: ${DateFormat('dd/MM/yyyy').format(transaction.date)}'),
              if (transaction.memberName != null) ...[
                const SizedBox(height: 6),
                Text('Responsável: ${transaction.memberName}'),
              ],
              if (transaction.paymentMethodName != null) ...[
                const SizedBox(height: 6),
                Text('Forma de Pagamento: ${transaction.paymentMethodName}'),
              ],
              if (transaction.description != null && transaction.description!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text('Descrição: ${transaction.description}'),
              ],
              if (transaction.notes != null && transaction.notes!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text('Observações: ${transaction.notes}'),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Fechar'),
            ),
          ],
        ),
      );
    }
  }

  String _formatPeriodDescription(TransactionFilter filter) {
    final dateFormat = DateFormat('dd/MM/yyyy');
    if (filter.periodMode == PeriodMode.cycle && filter.selectedCycle != null) {
      final c = filter.selectedCycle!;
      return '${c.monthName} (${dateFormat.format(c.startDate)} - ${dateFormat.format(c.endDate)})';
    } else if (filter.startDate != null && filter.endDate != null) {
      return '${dateFormat.format(filter.startDate!)} até ${dateFormat.format(filter.endDate!)}';
    }
    return 'Período atual';
  }

  Future<void> _exportCsv(
    BuildContext context,
    String houseName,
    String periodDescription,
    List<HouseTransaction> transactions,
    TransactionAggregatorMetrics metrics,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    const service = TransactionsExportService();
    final csv = service.buildCsv(
      houseName: houseName,
      periodDescription: periodDescription,
      transactions: transactions,
      metrics: metrics,
    );

    try {
      final dateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final saved = await FilePicker.saveFile(
        fileName: 'omnilar_extrato_$dateStr.csv',
        bytes: Uint8List.fromList(utf8.encode(csv)),
        mimeType: 'text/csv',
        dialogTitle: 'Exportar Extrato em CSV',
        allowedExtensions: const ['csv'],
        type: FileType.custom,
      );
      if (saved != null) {
        messenger.showSnackBar(
          SnackBar(content: Text('Extrato CSV exportado com sucesso (${transactions.length} lançamentos).')),
        );
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(backgroundColor: AppColors.debtRed, content: Text('Erro ao exportar CSV: $e')),
      );
    }
  }

  Future<void> _exportPdf(
    BuildContext context,
    String houseName,
    String periodDescription,
    List<HouseTransaction> transactions,
    TransactionAggregatorMetrics metrics,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    const service = TransactionsExportService();

    try {
      final bytes = await service.buildPdf(
        houseName: houseName,
        periodDescription: periodDescription,
        transactions: transactions,
        metrics: metrics,
      );

      final dateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final saved = await FilePicker.saveFile(
        fileName: 'omnilar_extrato_$dateStr.pdf',
        bytes: bytes,
        mimeType: 'application/pdf',
        dialogTitle: 'Exportar Extrato em PDF',
        allowedExtensions: const ['pdf'],
        type: FileType.custom,
      );
      if (saved != null) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Extrato PDF exportado com sucesso.')),
        );
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(backgroundColor: AppColors.debtRed, content: Text('Erro ao exportar PDF: $e')),
      );
    }
  }

  Map<DateTime, List<HouseTransaction>> _groupByDate(List<HouseTransaction> list) {
    final map = <DateTime, List<HouseTransaction>>{};
    for (final t in list) {
      final day = DateTime(t.date.year, t.date.month, t.date.day);
      map.putIfAbsent(day, () => []).add(t);
    }
    return map;
  }

  String _formatDayHeader(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    if (date == today) return 'Hoje';
    if (date == yesterday) return 'Ontem';
    if (date.year == now.year) {
      final s = _dateHeaderFormat.format(date);
      return s[0].toUpperCase() + s.substring(1);
    }
    return _yearHeaderFormat.format(date);
  }

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthCubit>().state;
    final financeState = context.watch<FinanceCubit>().state;
    final houseName = authState.house?.name ?? 'Minha Casa';

    return BlocProvider<TransactionsCubit>(
      create: (ctx) {
        final cubit = sl<TransactionsCubit>();
        cubit.initialize(
          initialCycle: widget.initialCycle ?? financeState.currentCycle,
          categories: financeState.categories,
          members: financeState.members,
          paymentMethods: financeState.paymentMethods,
        );
        return cubit;
      },
      child: Builder(
        builder: (context) {
          final cubit = context.watch<TransactionsCubit>();
          final state = cubit.state;
          final isDark = Theme.of(context).brightness == Brightness.dark;
          final periodDesc = _formatPeriodDescription(state.filter);

          return Scaffold(
            appBar: AppBar(
              title: _isSearching
                  ? TextField(
                      controller: _searchController,
                      autofocus: true,
                      decoration: const InputDecoration(
                        hintText: 'Pesquisar transação...',
                        border: InputBorder.none,
                      ),
                      onChanged: cubit.setSearchQuery,
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Extrato & Transações', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                        Text(houseName, style: TextStyle(fontSize: 12, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600)),
                      ],
                    ),
              actions: [
                IconButton(
                  tooltip: _isSearching ? 'Fechar busca' : 'Buscar',
                  icon: Icon(_isSearching ? Icons.close : Icons.search_rounded),
                  onPressed: () {
                    setState(() {
                      _isSearching = !_isSearching;
                      if (!_isSearching) {
                        _searchController.clear();
                        cubit.setSearchQuery('');
                      }
                    });
                  },
                ),
                Stack(
                  alignment: Alignment.center,
                  children: [
                    IconButton(
                      tooltip: 'Filtros avançados',
                      icon: const Icon(Icons.tune_rounded),
                      onPressed: () {
                        TransactionsFilterSheet.show(
                          context: context,
                          initialFilter: state.filter,
                          availableCycles: state.availableCycles,
                          categories: cubit.categories,
                          members: cubit.members,
                          paymentMethods: cubit.paymentMethods,
                          onApply: (newFilter) {
                            if (newFilter.periodMode != state.filter.periodMode ||
                                newFilter.selectedCycle != state.filter.selectedCycle ||
                                newFilter.startDate != state.filter.startDate ||
                                newFilter.endDate != state.filter.endDate) {
                              if (newFilter.periodMode == PeriodMode.cycle && newFilter.selectedCycle != null) {
                                cubit.selectCycle(newFilter.selectedCycle!);
                              } else if (newFilter.startDate != null && newFilter.endDate != null) {
                                cubit.setDateRange(
                                  startDate: newFilter.startDate!,
                                  endDate: newFilter.endDate!,
                                  preset: newFilter.datePreset,
                                );
                              }
                            }
                            cubit.setCategoryFilter(newFilter.categoryIds);
                            cubit.setMemberFilter(newFilter.memberId);
                            cubit.setPaymentMethodFilter(newFilter.paymentMethodId);
                            if (newFilter.onlyPending != state.filter.onlyPending) {
                              cubit.toggleOnlyPending();
                            }
                          },
                        );
                      },
                    ),
                    if (state.filter.hasActiveFilters)
                      Positioned(
                        top: 10,
                        right: 10,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                  ],
                ),
                PopupMenuButton<String>(
                  tooltip: 'Exportar extrato',
                  icon: const Icon(Icons.more_vert_rounded),
                  onSelected: (val) {
                    if (val == 'reconcile') {
                      final transCubit = context.read<TransactionsCubit>();
                      ReconcileCashModal.show(
                        context,
                        currentBalance: state.metrics.netBalance,
                        onSuccess: () => transCubit.refresh(),
                      );
                    } else if (val == 'csv') {
                      _exportCsv(context, houseName, periodDesc, state.filteredTransactions, state.metrics);
                    } else if (val == 'pdf') {
                      _exportPdf(context, houseName, periodDesc, state.filteredTransactions, state.metrics);
                    }
                  },
                  itemBuilder: (ctx) => [
                    const PopupMenuItem(
                      value: 'reconcile',
                      child: Row(
                        children: [
                          Icon(Icons.tune_rounded, color: AppColors.primary, size: 20),
                          SizedBox(width: 10),
                          Text('Conciliar com o Banco'),
                        ],
                      ),
                    ),
                    const PopupMenuDivider(),
                    const PopupMenuItem(
                      value: 'pdf',
                      child: Row(
                        children: [
                          Icon(Icons.picture_as_pdf_outlined, color: AppColors.debtRed, size: 20),
                          SizedBox(width: 10),
                          Text('Exportar como PDF'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'csv',
                      child: Row(
                        children: [
                          Icon(Icons.table_chart_outlined, color: AppColors.primary, size: 20),
                          SizedBox(width: 10),
                          Text('Exportar como Planilha (CSV)'),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            body: RefreshIndicator(
              onRefresh: cubit.refresh,
              child: CustomScrollView(
                slivers: [
                  // 1. Resumo Financeiro (Métricas de Entradas, Saídas e Saldo)
                  SliverToBoxAdapter(
                    child: TransactionsMetricsCard(
                      metrics: state.metrics,
                      periodDescription: periodDesc,
                    ),
                  ),

                  // 2. Barra de Chips Rápidos de Filtro
                  SliverToBoxAdapter(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: Row(
                        children: [
                          ChoiceChip(
                            label: const Text('Todas', style: TextStyle(fontSize: 12)),
                            selected: state.filter.type == null,
                            onSelected: (_) => cubit.setTypeFilter(null),
                          ),
                          const SizedBox(width: 8),
                          ChoiceChip(
                            label: const Text('Saídas', style: TextStyle(fontSize: 12)),
                            selected: state.filter.type == TransactionType.expense,
                            onSelected: (sel) => cubit.setTypeFilter(sel ? TransactionType.expense : null),
                          ),
                          const SizedBox(width: 8),
                          ChoiceChip(
                            label: const Text('Entradas', style: TextStyle(fontSize: 12)),
                            selected: state.filter.type == TransactionType.inflow,
                            onSelected: (sel) => cubit.setTypeFilter(sel ? TransactionType.inflow : null),
                          ),
                          const SizedBox(width: 8),
                          ActionChip(
                            avatar: const Icon(Icons.tune_rounded, size: 14),
                            label: Text(
                              state.filter.categoryIds.isNotEmpty
                                  ? 'Categorias (${state.filter.categoryIds.length})'
                                  : 'Filtrar',
                              style: const TextStyle(fontSize: 12),
                            ),
                            onPressed: () {
                              TransactionsFilterSheet.show(
                                context: context,
                                initialFilter: state.filter,
                                availableCycles: state.availableCycles,
                                categories: cubit.categories,
                                members: cubit.members,
                                paymentMethods: cubit.paymentMethods,
                                onApply: (f) {
                                  cubit.setCategoryFilter(f.categoryIds);
                                  cubit.setMemberFilter(f.memberId);
                                  cubit.setPaymentMethodFilter(f.paymentMethodId);
                                },
                              );
                            },
                          ),
                          if (state.filter.hasActiveFilters) ...[
                            const SizedBox(width: 8),
                            ActionChip(
                              avatar: const Icon(Icons.clear_rounded, size: 14),
                              label: const Text('Limpar', style: TextStyle(fontSize: 12)),
                              onPressed: cubit.clearFilters,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 8)),

                  // 3. Conteúdo: Carregando, Lista ou Vazio
                  if (state.status == TransactionsStatus.loading && state.allTransactions.isEmpty)
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (state.filteredTransactions.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.search_off_rounded, size: 64, color: Colors.grey.shade400),
                              const SizedBox(height: 16),
                              const Text(
                                'Nenhuma transação encontrada',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                state.filter.hasActiveFilters
                                    ? 'Tente ajustar ou limpar os filtros para ver mais lançamentos.'
                                    : 'Não há registros para este período.',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                              ),
                              if (state.filter.hasActiveFilters) ...[
                                const SizedBox(height: 16),
                                OutlinedButton(
                                  onPressed: cubit.clearFilters,
                                  child: const Text('Limpar Filtros'),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    )
                  else ...[
                    // Constrói os grupos por data
                    Builder(
                      builder: (ctx) {
                        final groups = _groupByDate(state.filteredTransactions);
                        final dates = groups.keys.toList();

                        return SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              final date = dates[index];
                              final transactionsOfDay = groups[date]!;
                              final dayTotalCents = transactionsOfDay.fold<int>(
                                0,
                                (sum, t) => sum + (t.isExpense ? -t.amount.cents : t.amount.cents),
                              );

                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Cabeçalho da Data
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          _formatDayHeader(date),
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: isDark ? Colors.grey.shade400 : Colors.grey.shade700,
                                          ),
                                        ),
                                        Text(
                                          (dayTotalCents >= 0 ? '+ ' : '- ') + Money(dayTotalCents.abs()).format(),
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: dayTotalCents >= 0
                                                ? (isDark ? Colors.green.shade400 : Colors.green.shade700)
                                                : (isDark ? Colors.red.shade400 : AppColors.debtRed),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  // Itens do dia
                                  Card(
                                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      side: BorderSide(
                                        color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.grey.withValues(alpha: 0.15),
                                      ),
                                    ),
                                    child: ListView.separated(
                                      shrinkWrap: true,
                                      physics: const NeverScrollableScrollPhysics(),
                                      itemCount: transactionsOfDay.length,
                                      separatorBuilder: (_, _) => Divider(
                                        height: 1,
                                        indent: 68,
                                        color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.grey.shade100,
                                      ),
                                      itemBuilder: (ctx, i) {
                                        final item = transactionsOfDay[i];
                                        return TransactionTile(
                                          transaction: item,
                                          onTap: () => _openDetails(context, item, cubit),
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              );
                            },
                            childCount: dates.length,
                          ),
                        );
                      },
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 32)),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
