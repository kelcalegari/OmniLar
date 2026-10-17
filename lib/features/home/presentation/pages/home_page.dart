import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/responsive.dart';
import '../../../../core/widgets/privacy_toggle.dart';
import '../../../../core/widgets/responsive_container.dart';
import '../../../../core/widgets/theme_toggle_button.dart';
import '../../../../core/di/service_locator.dart';
import '../../../auth/domain/repositories/auth_repository.dart';
import '../../../auth/presentation/cubit/auth_cubit.dart';
import '../../../auth/presentation/cubit/auth_state.dart';
import '../../../finance/presentation/cubit/finance_cubit.dart';
import '../../../finance/presentation/cubit/finance_state.dart';
import '../../../finance/domain/entities/house_expense.dart';
import '../../../finance/domain/repositories/finance_repository.dart';
import '../../../finance/domain/services/cycle_expense_grouping.dart';
import '../../../finance/domain/services/expense_search.dart';
import '../../../finance/presentation/widgets/expense_grid_table.dart';
import '../../../../core/widgets/search_shortcut.dart';
import '../../../finance/presentation/widgets/card_invoice_group_tile.dart';
import '../../../finance/presentation/widgets/card_invoice_payment_sheet.dart';
import '../../../settlement/domain/entities/settlement_summary.dart';
import '../../../settlement/domain/repositories/settlement_repository.dart';
import '../../../finance/presentation/widgets/folego_gauge_card.dart';
import '../../../finance/presentation/widgets/cycle_funding_planner_card.dart';
import '../../../finance/presentation/widgets/expense_timeline_item.dart';
import '../../../finance/presentation/widgets/expense_detail_desktop_pane.dart';
import '../../../notifications/presentation/widgets/notification_bell_button.dart';
import '../../../calendar/presentation/cubit/calendar_cubit.dart';
import '../../../calendar/presentation/cubit/calendar_state.dart';
import '../../../shopping/presentation/cubit/shopping_cubit.dart';
import '../../../shopping/presentation/cubit/shopping_state.dart';
import '../widgets/home_skeleton.dart';
import '../widgets/shortcut_subtitles.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final cubit = context.read<FinanceCubit>();
        if (cubit.state.summary == null) {
          cubit.loadCycleData();
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return const _HomePageContent();
  }
}

class _HomePageContent extends StatefulWidget {
  const _HomePageContent();

  @override
  State<_HomePageContent> createState() => _HomePageContentState();
}

class _HomePageContentState extends State<_HomePageContent> {
  String _selectedExpenseFilter = 'all'; // 'all', 'mine', 'recurring', 'bills'
  String? _selectedExpenseId;

  /// Busca nos lançamentos do ciclo (Ctrl + F no computador).
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  String _searchQuery = '';

  /// No computador, os lançamentos podem aparecer em tabela.
  bool _gridView = false;

  @override
  void initState() {
    super.initState();
    SearchShortcut.register(_searchFocus);
  }

  @override
  void dispose() {
    SearchShortcut.unregister(_searchFocus);
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  /// Faturas abertas na lista de gastos (pela chave da fatura).
  final Set<String> _expandedInvoices = {};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDesktop = context.isDesktop;

    return Scaffold(
      appBar: AppBar(
        title: BlocBuilder<AuthCubit, AuthState>(
          builder: (context, authState) {
            final isDemo = sl<AuthRepository>().isDemoMode;
            final house = authState.house;
            final user = authState.user;

            final houseName = house?.name ?? 'Omni Lar';
            final subtitle = isDemo
                ? 'Carlos & Marina (Demo)'
                : (user?.fullName.isNotEmpty == true
                      ? user!.fullName
                      : 'Minha Casa');

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  houseName,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            );
          },
        ),
        actions: [
          const ThemeToggleButton(),
          const PrivacyToggleButton(),
          const NotificationBellButton(),
        ],
      ),
      body: BlocBuilder<FinanceCubit, FinanceState>(
        builder: (context, state) {
          if (state.status == FinanceStatus.loading && state.summary == null) {
            return const HomeSkeleton();
          }

          final summary = state.summary;
          if (summary == null) {
            final isFailure = state.status == FinanceStatus.failure;
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isFailure
                          ? Icons.error_outline_rounded
                          : Icons.inbox_outlined,
                      size: 48,
                      color: isFailure ? AppColors.debtRed : Colors.grey,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      state.errorMessage ??
                          'Nenhum dado encontrado para o ciclo.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: () =>
                          context.read<FinanceCubit>().loadCycleData(),
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Carregar Dados do Ciclo'),
                    ),
                  ],
                ),
              ),
            );
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

  /// Consulta da situação (fechado ou em aberto) do ciclo mostrado, refeita a
  /// cada carga do ciclo para refletir um fechamento ou uma reabertura.
  Future<bool?>? _cycleSettledFuture;
  Object? _cycleSettledKey;

  Future<bool?> _cycleSettledFor(FinanceState state) {
    final key = (state.currentCycle, state.summary);
    if (_cycleSettledFuture == null || _cycleSettledKey != key) {
      _cycleSettledKey = key;
      final cycle = state.currentCycle;
      _cycleSettledFuture = cycle.contains(DateTime.now()) ||
              !sl.isRegistered<SettlementRepository>()
          ? Future.value(null)
          : sl<SettlementRepository>()
              .isCycleSettled(cycle)
              .then<bool?>((settled) => settled)
              .catchError((_) => null);
    }
    return _cycleSettledFuture!;
  }

  Widget _buildFolegoCard(FinanceState state, dynamic summary, FinanceCubit cubit) {
    return FutureBuilder<bool?>(
      future: _cycleSettledFor(state),
      builder: (context, snapshot) => FolegoGaugeCard(
        summary: summary,
        cycle: state.currentCycle,
        onPreviousCycle: cubit.canGoToPreviousCycle ? cubit.previousCycle : null,
        onNextCycle: cubit.nextCycle,
        onCurrentCycle: cubit.goToCurrentCycle,
        isLoading: _isSwitchingCycle(state),
        isCycleSettled: snapshot.data,
      ),
    );
  }

  /// O ciclo mostrado no topo já mudou, mas os números ainda são do anterior.
  bool _isSwitchingCycle(FinanceState state) =>
      state.status == FinanceStatus.loading &&
      state.summary != null &&
      state.summary!.cycle != state.currentCycle;

  /// Esmaece o que ainda é do ciclo anterior até o novo chegar.
  Widget _dimWhileSwitching(FinanceState state, Widget child) {
    return AnimatedOpacity(
      opacity: _isSwitchingCycle(state) ? 0.4 : 1,
      duration: const Duration(milliseconds: 150),
      child: child,
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
        _buildFolegoCard(state, summary, cubit),
        if (state.fundingEstimate != null) ...[
          const SizedBox(height: 16),
          _dimWhileSwitching(state, CycleFundingPlannerCard(estimate: state.fundingEstimate!)),
        ],
        const SizedBox(height: 16),
        _buildCycleRoutineCards(context),
        const SizedBox(height: 16),
        _buildQuickShortcuts(context, theme),
        const SizedBox(height: 24),
        _dimWhileSwitching(state, _buildExpensesSection(theme, state)),
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

    final selectedExpense = state.expenses.where((e) => e.id == _selectedExpenseId).firstOrNull;

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
                    _buildFolegoCard(state, summary, cubit),
                    if (state.fundingEstimate != null) ...[
                      const SizedBox(height: 16),
                      _dimWhileSwitching(state, CycleFundingPlannerCard(estimate: state.fundingEstimate!)),
                    ],
                    const SizedBox(height: 16),
                    _buildCycleRoutineCards(context),
                  ],
                ),
              ),
              const SizedBox(width: 20),
              // Coluna 2: Gastos do Ciclo (Timeline)
              Expanded(
                flex: selectedExpense != null ? 5 : 5,
                child: Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: Colors.grey.withValues(alpha: 0.15),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: _dimWhileSwitching(state, _buildExpensesSection(theme, state, isDesktop: true)),
                  ),
                ),
              ),
              const SizedBox(width: 20),
              // Coluna 3: Se tiver gasto selecionado, mostra detalhes lado a lado (Dual-Pane). Senão, rotina.
              Expanded(
                flex: selectedExpense != null ? 5 : 3,
                child: selectedExpense != null
                    ? ExpenseDetailDesktopPane(
                        expense: selectedExpense,
                        category: state.categories.where((c) => c.id == selectedExpense.categoryId).firstOrNull,
                        paymentMethod: state.paymentMethods.where((p) => p.id == selectedExpense.paymentMethodId).firstOrNull,
                        paidByMember: state.members.where((m) => m.id == selectedExpense.paidByMemberId).firstOrNull,
                        members: state.members,
                        onClose: () => setState(() => _selectedExpenseId = null),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Card(
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: BorderSide(
                                color: Colors.grey.withValues(alpha: 0.15),
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Row(
                                    children: [
                                      Icon(
                                        Icons.bolt_rounded,
                                        color: AppColors.accent,
                                        size: 22,
                                      ),
                                      SizedBox(width: 8),
                                      Text(
                                        'Rotina da Casa',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
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
                  _buildFolegoCard(state, summary, cubit),
                  if (state.fundingEstimate != null) ...[
                    const SizedBox(height: 16),
                    _dimWhileSwitching(state, CycleFundingPlannerCard(estimate: state.fundingEstimate!)),
                  ],
                  const SizedBox(height: 16),
                  _buildCycleRoutineCards(context),
                  const SizedBox(height: 16),
                  _buildQuickShortcuts(context, theme),
                ],
              ),
            ),
            const SizedBox(width: 24),
            // Coluna Direita: Gastos do Ciclo (ou Lado a Lado se selecionado)
            Expanded(
              flex: selectedExpense != null ? 7 : 6,
              child: selectedExpense != null
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
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
                              child: _dimWhileSwitching(state, _buildExpensesSection(theme, state, isDesktop: true)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          flex: 5,
                          child: ExpenseDetailDesktopPane(
                            expense: selectedExpense,
                            category: state.categories.where((c) => c.id == selectedExpense.categoryId).firstOrNull,
                            paymentMethod: state.paymentMethods.where((p) => p.id == selectedExpense.paymentMethodId).firstOrNull,
                            paidByMember: state.members.where((m) => m.id == selectedExpense.paidByMemberId).firstOrNull,
                            members: state.members,
                            onClose: () => setState(() => _selectedExpenseId = null),
                          ),
                        ),
                      ],
                    )
                  : Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: Colors.grey.withValues(alpha: 0.15)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: _dimWhileSwitching(state, _buildExpensesSection(theme, state, isDesktop: true)),
                      ),
                    ),
            ),
          ],
        ),
        const SizedBox(height: 40),
      ],
    );
  }

  /// A rotina do ciclo: importar fatura e extrato e depois fechar.
  Widget _buildCycleRoutineCards(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildImportCard(context),
        const SizedBox(height: 10),
        _buildSettlementCard(context),
      ],
    );
  }

  Widget _buildImportCard(BuildContext context) {
    return InkWell(
      key: const Key('home_import_card'),
      onTap: () => context.push('/importar'),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.accent.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.upload_file_rounded, color: AppColors.accent, size: 20),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Importar fatura ou extrato',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  Text(
                    'Confira o arquivo do banco com o que já foi lançado',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.accent),
          ],
        ),
      ),
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
              child: const Icon(
                Icons.flash_on_rounded,
                color: Colors.white,
                size: 22,
              ),
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
    // Contagens reais da lista de compras e das tarefas da casa
    final shopping = context.watch<ShoppingCubit>().state;
    final calendar = context.watch<CalendarCubit>().state;
    final shoppingLoaded = shopping.status != ShoppingCubitStatus.initial &&
        shopping.status != ShoppingCubitStatus.loading;
    final tasksLoaded = calendar.status == CalendarCubitStatus.loaded;

    final shortcuts = [
      _ShortcutItem(
        icon: Icons.shopping_bag_outlined,
        iconColor: AppColors.primaryLight,
        title: 'Compras',
        subtitle: shoppingShortcutSubtitle(shopping.items, loaded: shoppingLoaded),
        route: '/compras',
      ),
      _ShortcutItem(
        icon: Icons.savings_outlined,
        iconColor: Colors.teal,
        title: 'Caixinhas',
        subtitle: 'Metas da casa',
        route: '/caixinhas',
      ),
      _ShortcutItem(
        icon: Icons.task_alt_rounded,
        iconColor: AppColors.accent,
        title: 'Tarefas',
        subtitle: tasksShortcutSubtitle(calendar.tasks, loaded: tasksLoaded),
        route: '/tarefas',
      ),
      _ShortcutItem(
        icon: Icons.flight_takeoff_rounded,
        iconColor: AppColors.accent,
        title: 'Viagens',
        subtitle: 'e Projetos',
        route: '/projetos',
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        // Quando a largura for reduzida (< 520px, como na coluna lateral ultra-wide ou no mobile),
        // renderiza em grade 2x2 para garantir espaço confortável, leitura nítida e altura padronizada.
        final isCompact = constraints.maxWidth < 520;

        if (isCompact) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _buildShortcutCard(context, theme, shortcuts[0]),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildShortcutCard(context, theme, shortcuts[1]),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _buildShortcutCard(context, theme, shortcuts[2]),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildShortcutCard(context, theme, shortcuts[3]),
                    ),
                  ],
                ),
              ),
            ],
          );
        }

        // Caso haja largura ampla (>= 520px), renderiza em linha com altura padronizada
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (int i = 0; i < shortcuts.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(
                  child: _buildShortcutCard(context, theme, shortcuts[i]),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildShortcutCard(
    BuildContext context,
    ThemeData theme,
    _ShortcutItem item,
  ) {
    return InkWell(
      onTap: () => context.push(item.route),
      borderRadius: BorderRadius.circular(12),
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.grey.withValues(alpha: 0.15)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Icon(item.icon, color: item.iconColor, size: 20),
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 16,
                    color: Colors.grey,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    item.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 11,
                      color: Colors.grey,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExpensesSection(ThemeData theme, FinanceState state, {bool isDesktop = false}) {
    final currentUserId = context.read<AuthCubit>().state.user?.id;
    final filteredExpenses = state.expenses.where((expense) {
      if (_selectedExpenseFilter == 'recurring') {
        return expense.isRecurring;
      }
      if (_selectedExpenseFilter == 'mine') {
        return currentUserId != null && expense.paidByMemberId == currentUserId;
      }
      if (_selectedExpenseFilter == 'bills') {
        return expense.isPending ||
            expense.dueDate != null ||
            expense.isRecurring;
      }
      return true;
    }).where((expense) {
      if (_searchQuery.trim().isEmpty) return true;
      return expenseMatchesSearch(
        expense,
        _searchQuery,
        categoryName: state.categories.where((c) => c.id == expense.categoryId).firstOrNull?.name,
        payerName: state.members.where((m) => m.id == expense.paidByMemberId).firstOrNull?.name,
        paymentMethodName: state.paymentMethods.where((m) => m.id == expense.paymentMethodId).firstOrNull?.name,
      );
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Gastos do Ciclo',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${filteredExpenses.length} de ${state.expenses.length} lançamentos',
                  style: theme.textTheme.bodySmall,
                ),
                if (isDesktop) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    key: const Key('expense_view_toggle'),
                    tooltip: _gridView ? 'Ver em lista' : 'Ver em tabela',
                    icon: Icon(_gridView ? Icons.view_agenda_outlined : Icons.table_rows_outlined, size: 20),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => setState(() => _gridView = !_gridView),
                  ),
                ],
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildFilterChip('all', 'Todos', theme),
              const SizedBox(width: 6),
              _buildFilterChip('recurring', 'Recorrentes', theme),
              const SizedBox(width: 6),
              _buildFilterChip('mine', 'Minhas', theme),
              const SizedBox(width: 6),
              _buildFilterChip('bills', 'Contas/Fixas', theme),
            ],
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          key: const Key('expense_search'),
          controller: _searchController,
          focusNode: _searchFocus,
          onChanged: (value) => setState(() => _searchQuery = value),
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Buscar nos lançamentos',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _searchQuery.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'Limpar busca',
                    onPressed: () => setState(() {
                      _searchController.clear();
                      _searchQuery = '';
                    }),
                  ),
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
        const SizedBox(height: 12),
        if (filteredExpenses.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            alignment: Alignment.center,
            child: Text(
              _searchQuery.trim().isNotEmpty
                  ? 'Nenhum lançamento encontrado para "${_searchQuery.trim()}"'
                  : _selectedExpenseFilter == 'all'
                      ? 'Nenhuma despesa lançada neste ciclo'
                      : 'Nenhum gasto encontrado para este filtro',
              style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey),
            ),
          )
        else if (isDesktop && _gridView)
          ExpenseGridTable(
            expenses: filteredExpenses,
            categories: state.categories,
            members: state.members,
            paymentMethods: state.paymentMethods,
            selectedExpenseId: _selectedExpenseId,
            onSelect: (id) => setState(() => _selectedExpenseId = _selectedExpenseId == id ? null : id),
          )
        else
          ...groupCardInvoices(filteredExpenses, state.paymentMethods).map((entry) {
            Widget item(HouseExpense expense, {bool inInvoice = false}) =>
                _buildExpenseItem(state, expense, isDesktop: isDesktop, inInvoice: inInvoice);

            switch (entry) {
              case SingleExpenseEntry(:final expense):
                return item(expense);
              case CardInvoiceEntry():
                // A fatura que guarda a despesa selecionada fica aberta
                final expanded = _expandedInvoices.contains(entry.key) ||
                    entry.purchases.any((e) => e.id == _selectedExpenseId);
                return CardInvoiceGroupTile(
                  invoice: entry,
                  barcode: state.invoiceCodeFor(entry.card.id, entry.dueDate),
                  expanded: expanded,
                  onToggle: () => setState(() {
                    if (expanded) {
                      _expandedInvoices.remove(entry.key);
                      if (entry.purchases.any((e) => e.id == _selectedExpenseId)) {
                        _selectedExpenseId = null;
                      }
                    } else {
                      _expandedInvoices.add(entry.key);
                    }
                  }),
                  onImport: () => context.push(
                    Uri(path: '/importar', queryParameters: {'origem': entry.card.id}).toString(),
                  ),
                  onRegisterPayment: () {
                    final financeCubit = context.read<FinanceCubit>();
                    showAdaptiveModal(
                      context: context,
                      maxWidth: 480,
                      child: CardInvoicePaymentSheet(
                        card: entry.card,
                        initialDueDate: entry.dueDate,
                        memberNames: {for (final m in state.members) m.id: m.name.split(' ').first},
                        repository: sl<FinanceRepository>(),
                        financeCubit: financeCubit,
                        cycleSchedule: financeCubit.cycleSchedule,
                        isCycleClosed: (cycle) async =>
                            (await sl<SettlementRepository>().getSettlementSummary(cycle)).status ==
                            SettlementStatus.settled,
                      ),
                    );
                  },
                  children: [
                    for (final expense in entry.purchases) item(expense, inInvoice: true),
                  ],
                );
            }
          }),
      ],
    );
  }

  Widget _buildExpenseItem(
    FinanceState state,
    HouseExpense expense, {
    required bool isDesktop,
    bool inInvoice = false,
  }) {
            final category =
                state.categories
                    .where((c) => c.id == expense.categoryId)
                    .firstOrNull ??
                state.categories.firstOrNull;
            final paymentMethod =
                state.paymentMethods
                    .where((pm) => pm.id == expense.paymentMethodId)
                    .firstOrNull ??
                state.paymentMethods.firstOrNull;
            final paidByMember =
                state.members
                    .where((m) => m.id == expense.paidByMemberId)
                    .firstOrNull ??
                state.members.firstOrNull;

            final isSelected = isDesktop && _selectedExpenseId == expense.id;

            return ExpenseTimelineItem(
              expense: expense,
              category: category,
              paymentMethod: paymentMethod,
              paidByMember: paidByMember,
              members: state.members,
              isSelected: isSelected,
              showPurchaseDate: inInvoice,
              onSelect: isDesktop
                  ? () {
                      setState(() {
                        if (_selectedExpenseId == expense.id) {
                          _selectedExpenseId = null;
                        } else {
                          _selectedExpenseId = expense.id;
                        }
                      });
                    }
                  : null,
            );
  }

  Widget _buildFilterChip(String filterKey, String label, ThemeData theme) {
    final isSelected = _selectedExpenseFilter == filterKey;
    return ChoiceChip(
      label: Text(label),
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        color: isSelected ? Colors.white : theme.textTheme.bodyMedium?.color,
      ),
      selected: isSelected,
      selectedColor: theme.colorScheme.primary,
      onSelected: (selected) {
        if (selected) {
          setState(() {
            _selectedExpenseFilter = filterKey;
          });
        }
      },
      visualDensity: VisualDensity.compact,
    );
  }
}

class _ShortcutItem {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final String route;

  const _ShortcutItem({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.route,
  });
}
