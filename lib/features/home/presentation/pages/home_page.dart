import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../core/domain/value_objects/money.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/responsive.dart';
import '../../../../core/widgets/privacy_toggle.dart';
import '../../../../core/widgets/responsive_container.dart';
import '../../../../core/widgets/save_feedback.dart';
import '../../../../core/widgets/theme_toggle_button.dart';
import '../../../../core/di/service_locator.dart';
import '../../../auth/domain/repositories/auth_repository.dart';
import '../../../auth/presentation/cubit/auth_cubit.dart';
import '../../../auth/presentation/cubit/auth_state.dart';
import '../../../finance/presentation/cubit/finance_cubit.dart';
import '../../../finance/presentation/cubit/finance_state.dart';
import '../../../finance/domain/entities/contribution.dart';
import '../../../finance/domain/entities/house_expense.dart';
import '../../../finance/domain/entities/house_inflow.dart';
import '../../../finance/domain/entities/third_party_receipt.dart';
import '../../../finance/presentation/widgets/house_inflows_card.dart';
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

  /// Alternador da lista: false = Saídas / Gastos, true = Entradas
  bool _showInflows = false;
  String _selectedInflowFilter = 'all'; // 'all', 'unapplied', 'receipts', 'contributions', 'inflows'

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
        params: state.houseSettings.folegoParams,
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

    final allInflows = _buildInflowItems(state);
    final unappliedCount = allInflows.where((i) => i.isUnapplied).length;
    final filteredInflows = _filterInflows(allInflows);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            SegmentedButton<bool>(
              key: const Key('timeline_direction_toggle'),
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              segments: [
                ButtonSegment<bool>(
                  value: false,
                  label: Text('Saídas (${state.expenses.length})'),
                  icon: const Icon(Icons.arrow_upward_rounded, size: 16),
                ),
                ButtonSegment<bool>(
                  value: true,
                  label: Text('Entradas (${allInflows.length})'),
                  icon: const Icon(Icons.arrow_downward_rounded, size: 16),
                ),
              ],
              selected: {_showInflows},
              onSelectionChanged: (selected) {
                setState(() {
                  _showInflows = selected.first;
                });
              },
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!_showInflows) ...[
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
                ] else ...[
                  Text(
                    '${filteredInflows.length} de ${allInflows.length} entradas',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (!_showInflows)
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
          )
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildInflowFilterChip('all', 'Todas', theme),
                const SizedBox(width: 6),
                _buildInflowFilterChip(
                  'unapplied',
                  unappliedCount > 0 ? 'Sem aplicar ($unappliedCount)' : 'Sem aplicar',
                  theme,
                  badgeColor: unappliedCount > 0 ? Colors.amber.shade800 : null,
                ),
                const SizedBox(width: 6),
                _buildInflowFilterChip('receipts', 'Repasses', theme),
                const SizedBox(width: 6),
                _buildInflowFilterChip('contributions', 'Aportes', theme),
                const SizedBox(width: 6),
                _buildInflowFilterChip('inflows', 'De fora', theme),
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
            hintText: _showInflows ? 'Buscar nas entradas' : 'Buscar nos lançamentos',
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
        if (!_showInflows) ...[
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
        ] else ...[
          if (filteredInflows.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _searchQuery.trim().isNotEmpty
                        ? 'Nenhuma entrada encontrada para "${_searchQuery.trim()}"'
                        : _selectedInflowFilter == 'all'
                            ? 'Nenhuma entrada registrada neste ciclo'
                            : _selectedInflowFilter == 'unapplied'
                                ? 'Tudo aplicado! Não há repasses ou entradas livres pendentes'
                                : 'Nenhuma entrada encontrada para este filtro',
                    style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.tonalIcon(
                    onPressed: () => showHouseInflowForm(context, context.read<FinanceCubit>(), state),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Registrar entrada'),
                  ),
                ],
              ),
            )
          else ...[
            if (filteredInflows.any((i) => i.isFromPreviousCycle)) ...[
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 8),
                child: Row(
                  children: [
                    Icon(Icons.history_rounded, size: 16, color: Colors.deepOrange.shade600),
                    const SizedBox(width: 6),
                    Text(
                      'Pendências de Ciclos Anteriores',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.deepOrange.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              ...filteredInflows
                  .where((i) => i.isFromPreviousCycle)
                  .map((item) => _buildInflowCard(item, theme, state)),
              const SizedBox(height: 8),
              if (filteredInflows.any((i) => !i.isFromPreviousCycle))
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 8),
                  child: Row(
                    children: [
                      Icon(Icons.calendar_today_rounded, size: 15, color: theme.colorScheme.primary),
                      const SizedBox(width: 6),
                      Text(
                        'Deste Ciclo',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            ...filteredInflows
                .where((i) => !i.isFromPreviousCycle)
                .map((item) => _buildInflowCard(item, theme, state)),
          ],
        ],
      ],
    );
  }

  List<_UnifiedInflowItem> _buildInflowItems(FinanceState state) {
    final list = <_UnifiedInflowItem>[];
    final cycle = state.currentCycle;

    for (final r in state.thirdPartyReceipts) {
      list.add(_ThirdPartyReceiptInflowItem(r, isInCurrentCycle: cycle.contains(r.receivedOn)));
    }
    for (final c in state.contributions) {
      list.add(_ContributionInflowItem(c, isInCurrentCycle: cycle.contains(c.date)));
    }
    for (final i in state.houseInflows) {
      list.add(_HouseInflowItem(i, isInCurrentCycle: cycle.contains(i.receivedOn)));
    }

    list.sort((a, b) => b.date.compareTo(a.date));
    return list;
  }

  List<_UnifiedInflowItem> _filterInflows(List<_UnifiedInflowItem> items) {
    return items.where((item) {
      switch (_selectedInflowFilter) {
        case 'unapplied':
          return item.isUnapplied;
        case 'receipts':
          return item is _ThirdPartyReceiptInflowItem;
        case 'contributions':
          return item is _ContributionInflowItem;
        case 'inflows':
          return item is _HouseInflowItem;
        case 'all':
        default:
          return true;
      }
    }).where((item) {
      if (_searchQuery.trim().isEmpty) return true;
      final query = _searchQuery.trim().toLowerCase();
      return item.title.toLowerCase().contains(query) ||
          item.subtitle.toLowerCase().contains(query) ||
          item.badgeLabel.toLowerCase().contains(query);
    }).toList();
  }

  Widget _buildInflowCard(_UnifiedInflowItem item, ThemeData theme, FinanceState state) {
    final isDark = theme.brightness == Brightness.dark;
    final dateStr = DateFormat('dd/MM/yyyy').format(item.date);

    final amountText = PrivacySensitiveText(
      '+ ${item.amount.formatted}',
      style: const TextStyle(
        fontWeight: FontWeight.bold,
        fontSize: 15,
        color: AppColors.creditGreen,
      ),
    );

    final menuButton = PopupMenuButton<String>(
      key: ValueKey('inflow_menu_${item.id}'),
      padding: EdgeInsets.zero,
      icon: const Icon(Icons.more_vert_rounded, size: 20, color: Colors.grey),
      tooltip: 'Opções da entrada',
      onSelected: (val) {
        if (item is _HouseInflowItem) {
          if (val == 'edit') {
            showHouseInflowForm(
              context,
              context.read<FinanceCubit>(),
              state,
              editing: item.inflow,
            );
          } else if (val == 'delete') {
            _confirmDeleteHouseInflow(context, item.inflow);
          }
        } else if (item is _ThirdPartyReceiptInflowItem) {
          if (val == 'use') {
            _showUseReceiptDialog(context, item.receipt, state);
          } else if (val == 'reopen') {
            _reopenReceipt(context, item.receipt);
          } else if (val == 'delete') {
            _confirmDeleteReceipt(context, item.receipt, state);
          }
        }
      },
      itemBuilder: (ctx) {
        if (item is _HouseInflowItem) {
          return [
            const PopupMenuItem(
              value: 'edit',
              child: Row(
                children: [
                  Icon(Icons.edit_outlined, size: 18, color: AppColors.primary),
                  SizedBox(width: 10),
                  Expanded(child: Text('Editar Entrada')),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.debtRed),
                  SizedBox(width: 10),
                  Expanded(child: Text('Excluir Entrada', style: TextStyle(color: AppColors.debtRed))),
                ],
              ),
            ),
          ];
        } else if (item is _ThirdPartyReceiptInflowItem) {
          final receipt = item.receipt;
          return [
            if (receipt.isHeld)
              const PopupMenuItem(
                value: 'use',
                child: Row(
                  children: [
                    Icon(Icons.credit_card_rounded, size: 18, color: AppColors.primary),
                    SizedBox(width: 10),
                    Expanded(child: Text('Usar na fatura')),
                  ],
                ),
              )
            else
              const PopupMenuItem(
                value: 'reopen',
                child: Row(
                  children: [
                    Icon(Icons.undo_rounded, size: 18, color: AppColors.primary),
                    SizedBox(width: 10),
                    Expanded(child: Text('Devolver para caixinha')),
                  ],
                ),
              ),
            const PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.debtRed),
                  SizedBox(width: 10),
                  Expanded(child: Text('Excluir Repasse', style: TextStyle(color: AppColors.debtRed))),
                ],
              ),
            ),
          ];
        }
        return const [];
      },
    );

    return Container(
      key: ValueKey('inflow_item_${item.id}'),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? AppColors.borderDark : AppColors.borderLight,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          if (item is _HouseInflowItem) {
            showHouseInflowForm(
              context,
              context.read<FinanceCubit>(),
              state,
              editing: item.inflow,
            );
          } else if (item is _ThirdPartyReceiptInflowItem) {
            if (item.receipt.isHeld) {
              _showUseReceiptDialog(context, item.receipt, state);
            } else {
              _reopenReceipt(context, item.receipt);
            }
          }
        },
        child: LayoutBuilder(
          builder: (context, constraints) {
            final narrow = constraints.maxWidth < 400;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    // Ícone em Container 44x44 arredondado (squircle) idêntico às saídas
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: item.color.withValues(alpha: isDark ? 0.25 : 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        item.icon,
                        color: item.color,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Título, Badges e Subtítulo
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              Text(
                                item.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                decoration: BoxDecoration(
                                  color: item.color.withValues(alpha: isDark ? 0.25 : 0.12),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  item.badgeLabel,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: item.color,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  '$dateStr • ${item.subtitle}',
                                  style: theme.textTheme.bodySmall?.copyWith(fontSize: 12),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),

                    if (!narrow) ...[
                      amountText,
                      menuButton,
                    ],
                  ],
                ),
                if (narrow) ...[
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      amountText,
                      menuButton,
                    ],
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _confirmDeleteHouseInflow(BuildContext context, HouseInflow inflow) async {
    final messenger = ScaffoldMessenger.of(context);
    final cubit = context.read<FinanceCubit>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Excluir entrada?'),
        content: Text('Os ${inflow.amount.formatted} de "${inflow.description}" saem do Caixa do ciclo.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.debtRed),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final ok = await cubit.deleteHouseInflow(inflow.id);
    showSaveFeedback(messenger, ok: ok, success: 'Entrada excluída.', failure: cubit.state.errorMessage);
  }

  Future<void> _confirmDeleteReceipt(BuildContext context, ThirdPartyReceipt receipt, FinanceState state) async {
    final messenger = ScaffoldMessenger.of(context);
    final cubit = context.read<FinanceCubit>();
    final vaultName = state.savingsVaults.where((v) => v.id == receipt.vaultId).firstOrNull?.name ?? 'Caixinha';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Excluir repasse?'),
        content: Text(
          'Os ${receipt.amount.formatted} de ${receipt.payerName} saem da caixinha "$vaultName". '
          'Use quando o registro foi um engano ou o dinheiro foi devolvido.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.debtRed),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final ok = await cubit.deleteThirdPartyReceipt(receipt.id);
    showSaveFeedback(messenger, ok: ok, success: 'Repasse excluído.', failure: cubit.state.errorMessage);
  }

  Future<void> _reopenReceipt(BuildContext context, ThirdPartyReceipt receipt) async {
    final messenger = ScaffoldMessenger.of(context);
    final cubit = context.read<FinanceCubit>();
    final ok = await cubit.reopenThirdPartyReceipt(receipt.id);
    showSaveFeedback(
      messenger,
      ok: ok,
      success: 'O repasse de ${receipt.payerName} voltou para a caixinha.',
      failure: cubit.state.errorMessage,
    );
  }

  Future<void> _showUseReceiptDialog(BuildContext context, ThirdPartyReceipt receipt, FinanceState state) async {
    final cards = state.paymentMethods.where((p) => p.isCreditCard).toList();
    String? cardId = cards.any((c) => c.id == receipt.paymentMethodId) ? receipt.paymentMethodId : null;
    ThirdPartyReceiptUse? use;
    final messenger = ScaffoldMessenger.of(context);
    final cubit = context.read<FinanceCubit>();

    ThirdPartyReceiptUse suggestedUse(String? id) {
      final card = cards.where((c) => c.id == id).firstOrNull;
      return card != null && card.ownerMemberId != null
          ? ThirdPartyReceiptUse.passedToOwner
          : ThirdPartyReceiptUse.housePaid;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final chosenUse = use ?? suggestedUse(cardId);
          final card = cards.where((c) => c.id == cardId).firstOrNull;
          final owner = state.members
              .where((m) => m.id == card?.ownerMemberId)
              .firstOrNull;

          return AlertDialog(
            title: Text('Usar o repasse de ${receipt.payerName}'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<String?>(
                    key: const Key('use_receipt_card'),
                    initialValue: cardId,
                    decoration: const InputDecoration(labelText: 'Fatura do cartão'),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('Outro pagamento')),
                      for (final c in cards) ...[
                        DropdownMenuItem<String?>(
                          value: c.id,
                          child: Text(
                            c.ownerMemberId == null
                                ? '${c.name} (da casa)'
                                : '${c.name} (${state.members.where((m) => m.id == c.ownerMemberId).firstOrNull?.name.split(' ').first ?? ''})',
                          ),
                        ),
                      ],
                    ],
                    onChanged: (value) => setDialogState(() {
                      cardId = value;
                      use = null;
                    }),
                  ),
                  const SizedBox(height: 16),
                  SegmentedButton<ThirdPartyReceiptUse>(
                    segments: const [
                      ButtonSegment(value: ThirdPartyReceiptUse.housePaid, label: Text('A Casa pagou')),
                      ButtonSegment(value: ThirdPartyReceiptUse.passedToOwner, label: Text('Repassei')),
                    ],
                    selected: {chosenUse},
                    onSelectionChanged: (s) => setDialogState(() => use = s.first),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    chosenUse == ThirdPartyReceiptUse.housePaid
                        ? 'A conta da Casa pagou: os ${receipt.amount.formatted} saem da caixinha, sem voltar ao Caixa do ciclo.'
                        : 'Os ${receipt.amount.formatted} saem da caixinha e vão para '
                            '${owner?.name.split(' ').first ?? 'quem pagou a fatura'}.',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogCtx, false), child: const Text('Cancelar')),
              FilledButton(
                key: const Key('use_receipt_confirm'),
                onPressed: () {
                  use = chosenUse;
                  Navigator.pop(dialogCtx, true);
                },
                child: const Text('Usar'),
              ),
            ],
          );
        },
      ),
    );
    if (confirmed != true) return;
    final ok = await cubit.useThirdPartyReceipts(
      receiptIds: [receipt.id],
      use: use ?? suggestedUse(cardId),
      paymentMethodId: cardId,
    );
    showSaveFeedback(
      messenger,
      ok: ok,
      success: 'Repasse de ${receipt.payerName} usado: ${receipt.amount.formatted} saíram da caixinha.',
      failure: cubit.state.errorMessage,
    );
  }

  Widget _buildInflowFilterChip(
    String filterKey,
    String label,
    ThemeData theme, {
    Color? badgeColor,
  }) {
    final isSelected = _selectedInflowFilter == filterKey;
    return ChoiceChip(
      label: Text(label),
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        color: isSelected
            ? Colors.white
            : (badgeColor ?? theme.textTheme.bodyMedium?.color),
      ),
      selected: isSelected,
      selectedColor: badgeColor ?? theme.colorScheme.primary,
      onSelected: (selected) {
        if (selected) {
          setState(() {
            _selectedInflowFilter = filterKey;
          });
        }
      },
      visualDensity: VisualDensity.compact,
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

abstract class _UnifiedInflowItem {
  String get id;
  String get title;
  String get subtitle;
  Money get amount;
  DateTime get date;
  IconData get icon;
  Color get color;
  String get badgeLabel;
  bool get isUnapplied;
  bool get isFromPreviousCycle;
}

class _ThirdPartyReceiptInflowItem implements _UnifiedInflowItem {
  final ThirdPartyReceipt receipt;
  final bool isInCurrentCycle;

  const _ThirdPartyReceiptInflowItem(this.receipt, {required this.isInCurrentCycle});

  @override
  String get id => receipt.id;

  @override
  String get title => receipt.payerName;

  @override
  String get subtitle {
    final status = receipt.isHeld
        ? (isInCurrentCycle ? 'Guardado para fatura' : 'Guardado • de ciclo anterior')
        : 'Usado em fatura';
    return receipt.description?.isNotEmpty == true ? '${receipt.description!} • $status' : status;
  }

  @override
  Money get amount => receipt.amount;

  @override
  DateTime get date => receipt.receivedOn;

  @override
  IconData get icon => Icons.call_received_rounded;

  @override
  Color get color => receipt.isHeld
      ? (isInCurrentCycle ? Colors.amber.shade700 : Colors.deepOrange.shade600)
      : Colors.teal;

  @override
  String get badgeLabel {
    if (receipt.isHeld) {
      return isInCurrentCycle ? 'Repasse (guardado)' : 'Repasse (ciclo anterior)';
    }
    return 'Repasse (usado)';
  }

  @override
  bool get isUnapplied => receipt.isHeld;

  @override
  bool get isFromPreviousCycle => !isInCurrentCycle;
}

class _ContributionInflowItem implements _UnifiedInflowItem {
  final Contribution contribution;
  final bool isInCurrentCycle;

  const _ContributionInflowItem(this.contribution, {required this.isInCurrentCycle});

  @override
  String get id => contribution.id;

  @override
  String get title => 'Aporte no Caixa';

  @override
  String get subtitle => isInCurrentCycle ? 'Depósito para custeio do ciclo' : 'Depósito • de ciclo anterior';

  @override
  Money get amount => contribution.amount;

  @override
  DateTime get date => contribution.date;

  @override
  IconData get icon => Icons.payments_outlined;

  @override
  Color get color => Colors.blue;

  @override
  String get badgeLabel => 'Aporte';

  @override
  bool get isUnapplied => false;

  @override
  bool get isFromPreviousCycle => !isInCurrentCycle;
}

class _HouseInflowItem implements _UnifiedInflowItem {
  final HouseInflow inflow;
  final bool isInCurrentCycle;

  const _HouseInflowItem(this.inflow, {required this.isInCurrentCycle});

  @override
  String get id => inflow.id;

  @override
  String get title => inflow.description.isNotEmpty ? inflow.description : inflow.source.label;

  @override
  String get subtitle => inflow.expenseId != null ? 'Reembolsa despesa' : 'Entrada livre do ciclo';

  @override
  Money get amount => inflow.amount;

  @override
  DateTime get date => inflow.receivedOn;

  @override
  IconData get icon => Icons.account_balance_wallet_outlined;

  @override
  Color get color => inflow.expenseId == null ? Colors.green.shade700 : Colors.indigo;

  @override
  String get badgeLabel => inflow.expenseId == null ? 'Livre' : 'Reembolso';

  @override
  bool get isUnapplied => inflow.expenseId == null;

  @override
  bool get isFromPreviousCycle => !isInCurrentCycle;
}

