import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../../../core/domain/value_objects/money.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/responsive.dart';
import '../../../../core/widgets/money_input_field.dart';
import '../../../../core/widgets/responsive_container.dart';
import '../../../../core/di/service_locator.dart';
import '../../../auth/domain/repositories/auth_repository.dart';
import '../../../calendar/domain/entities/task_item.dart';
import '../../../calendar/presentation/cubit/calendar_cubit.dart';
import '../../../calendar/presentation/cubit/calendar_state.dart';
import '../../../calendar/presentation/widgets/add_task_sheet.dart';
import '../../../finance/presentation/cubit/finance_cubit.dart';
import '../../../p2p/presentation/cubit/p2p_cubit.dart';
import '../../../shopping/domain/entities/shopping_item.dart';
import '../../../shopping/presentation/cubit/shopping_cubit.dart';
import '../../../shopping/presentation/cubit/shopping_state.dart';

class TasksAndShoppingPage extends StatefulWidget {
  final int initialTabIndex;

  const TasksAndShoppingPage({
    super.key,
    this.initialTabIndex = 0,
  });

  @override
  State<TasksAndShoppingPage> createState() => _TasksAndShoppingPageState();
}

class _TasksAndShoppingPageState extends State<TasksAndShoppingPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _taskFilter = 'pending'; // 'pending', 'completed', 'all'
  final _addShoppingController = TextEditingController();
  bool _isPersonalShoppingItem = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, 1),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<CalendarCubit>().loadCalendarData();
        context.read<ShoppingCubit>().loadShoppingData();
      }
    });
  }

  @override
  void didUpdateWidget(TasksAndShoppingPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialTabIndex != oldWidget.initialTabIndex) {
      _tabController.animateTo(widget.initialTabIndex.clamp(0, 1));
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _addShoppingController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDesktop = context.isDesktop;

    if (isDesktop) {
      return Scaffold(
        appBar: AppBar(
          title: const Text(
            'Tarefas & Compras',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        body: _buildDesktopDualPane(context, theme),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Tarefas & Compras',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: theme.cardColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
            ),
            child: TabBar(
              controller: _tabController,
              indicatorSize: TabBarIndicatorSize.tab,
              indicator: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              labelColor: AppColors.primary,
              unselectedLabelColor: Colors.grey,
              labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              tabs: [
                Tab(
                  child: BlocBuilder<CalendarCubit, CalendarState>(
                    builder: (context, state) {
                      final pendingCount = state.tasks.where((t) => !t.isCompleted).length;
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.check_circle_outline_rounded, size: 18),
                          const SizedBox(width: 6),
                          Text('Tarefas da Casa ($pendingCount)'),
                        ],
                      );
                    },
                  ),
                ),
                Tab(
                  child: BlocBuilder<ShoppingCubit, ShoppingState>(
                    builder: (context, state) {
                      final pendingCount = state.items.where((i) => !i.isBought).length;
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.shopping_cart_outlined, size: 18),
                          const SizedBox(width: 6),
                          Text('Lista de Compras ($pendingCount)'),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildTasksTab(context, theme),
          _buildShoppingTab(context, theme),
        ],
      ),
    );
  }

  // ==========================================
  // DESKTOP DUAL-PANE & KPIs DE ROTINA
  // ==========================================
  Widget _buildDesktopDualPane(BuildContext context, ThemeData theme) {
    return BlocBuilder<CalendarCubit, CalendarState>(
      builder: (context, calState) {
        return BlocBuilder<ShoppingCubit, ShoppingState>(
          builder: (context, shopState) {
            return ResponsiveContainer(
              maxWidth: kMaxContentWidth,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  children: [
                    // Linha Superior de KPIs
                    _buildKpisHeader(calState, shopState, theme),
                    const SizedBox(height: 14),

                    // Painéis Lado a Lado
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Coluna 1: Tarefas da Casa
                          Expanded(
                            child: Card(
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                                side: BorderSide(color: Colors.grey.withValues(alpha: 0.15)),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: _buildTasksColumnContent(
                                  context,
                                  calState,
                                  theme,
                                  isDesktop: true,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),

                          // Coluna 2: Lista de Compras
                          Expanded(
                            child: Card(
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                                side: BorderSide(color: Colors.grey.withValues(alpha: 0.15)),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: _buildShoppingColumnContent(
                                  context,
                                  shopState,
                                  theme,
                                  isDesktop: true,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildKpisHeader(CalendarState calState, ShoppingState shopState, ThemeData theme) {
    final pendingTasks = calState.tasks.where((t) => !t.isCompleted).length;
    final overdueTasks = calState.tasks.where((t) => !t.isCompleted && t.isOverdue).length;
    final pendingShopping = shopState.items.where((i) => !i.isBought).length;
    final cartItems = shopState.items.where((i) => i.isBought).length;

    return Row(
      children: [
        Expanded(
          child: _buildKpiCard(
            title: 'Tarefas Pendentes',
            count: pendingTasks.toString(),
            icon: Icons.check_circle_outline_rounded,
            color: AppColors.primary,
            theme: theme,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildKpiCard(
            title: 'Tarefas Atrasadas',
            count: overdueTasks.toString(),
            icon: Icons.warning_amber_rounded,
            color: overdueTasks > 0 ? AppColors.debtRed : Colors.grey,
            theme: theme,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildKpiCard(
            title: 'Itens a Comprar',
            count: pendingShopping.toString(),
            icon: Icons.shopping_basket_outlined,
            color: Colors.orange,
            theme: theme,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildKpiCard(
            title: 'No Carrinho',
            count: cartItems.toString(),
            icon: Icons.shopping_bag_outlined,
            color: AppColors.creditGreen,
            theme: theme,
          ),
        ),
      ],
    );
  }

  Widget _buildKpiCard({
    required String title,
    required String count,
    required IconData icon,
    required Color color,
    required ThemeData theme,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.withValues(alpha: 0.15)),
      ),
      color: theme.cardColor,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    count,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                  Text(
                    title,
                    style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // ABA 1: TAREFAS DA CASA
  // ==========================================
  Widget _buildTasksTab(BuildContext context, ThemeData theme) {
    return BlocBuilder<CalendarCubit, CalendarState>(
      builder: (context, state) {
        return ResponsiveContainer(
          maxWidth: 900,
          child: _buildTasksColumnContent(
            context,
            state,
            theme,
            isDesktop: false,
          ),
        );
      },
    );
  }

  Widget _buildTasksColumnContent(
    BuildContext context,
    CalendarState state,
    ThemeData theme, {
    required bool isDesktop,
  }) {
    final cubit = context.read<CalendarCubit>();
    final pendingTasks = state.tasks.where((t) => !t.isCompleted).toList();
    final completedTasks = state.tasks.where((t) => t.isCompleted).toList();
    final pendingCount = pendingTasks.length;
    final completedCount = completedTasks.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isDesktop) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_outline_rounded, color: AppColors.primary, size: 22),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Tarefas da Casa (${state.tasks.length})',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: () => AddTaskSheet.show(context, state.activeMemberId),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Nova Tarefa'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],

        // Barra de Filtros e Ação
        Padding(
          padding: EdgeInsets.fromLTRB(
            isDesktop ? 0 : 16,
            isDesktop ? 0 : 12,
            isDesktop ? 0 : 16,
            8,
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ChoiceChip(
                  label: Text('Pendentes ($pendingCount)'),
                  selected: _taskFilter == 'pending',
                  onSelected: (_) => setState(() => _taskFilter = 'pending'),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: Text('Concluídas ($completedCount)'),
                  selected: _taskFilter == 'completed',
                  onSelected: (_) => setState(() => _taskFilter = 'completed'),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: Text('Todas (${state.tasks.length})'),
                  selected: _taskFilter == 'all',
                  onSelected: (_) => setState(() => _taskFilter = 'all'),
                ),
                if (!isDesktop) ...[
                  const SizedBox(width: 16),
                  FilledButton.icon(
                    onPressed: () => AddTaskSheet.show(context, state.activeMemberId),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Nova Tarefa'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),

        // Lista de Tarefas
        Expanded(
          child: _buildTasksList(
            context,
            state,
            pendingTasks,
            completedTasks,
            cubit,
            theme,
            isDesktop: isDesktop,
          ),
        ),
      ],
    );
  }

  Widget _buildTasksList(
    BuildContext context,
    CalendarState state,
    List<TaskItem> pendingTasks,
    List<TaskItem> completedTasks,
    CalendarCubit cubit,
    ThemeData theme, {
    required bool isDesktop,
  }) {
    final padding = EdgeInsets.fromLTRB(
      isDesktop ? 0 : 16,
      4,
      isDesktop ? 0 : 16,
      isDesktop ? 16 : 80,
    );

    if (_taskFilter == 'pending') {
      if (pendingTasks.isEmpty) {
        return _buildEmptyTasksWidget(context, 'pending', state.activeMemberId);
      }
      return ListView.builder(
        padding: padding,
        itemCount: pendingTasks.length,
        itemBuilder: (context, index) => _buildTaskCard(context, pendingTasks[index], cubit, theme),
      );
    }

    if (_taskFilter == 'completed') {
      if (completedTasks.isEmpty) {
        return _buildEmptyTasksWidget(context, 'completed', state.activeMemberId);
      }
      return ListView(
        padding: padding,
        children: [
          ...completedTasks.map((t) => _buildTaskCard(context, t, cubit, theme)),
          _buildHistoryBanner(context, state, cubit, theme),
        ],
      );
    }

    // Modo 'all' (Todas)
    if (pendingTasks.isEmpty && completedTasks.isEmpty) {
      return _buildEmptyTasksWidget(context, 'all', state.activeMemberId);
    }

    return ListView(
      padding: padding,
      children: [
        if (pendingTasks.isNotEmpty) ...[
          if (completedTasks.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8, top: 2),
              child: Text(
                'Pendentes (${pendingTasks.length})',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey),
              ),
            ),
          ...pendingTasks.map((t) => _buildTaskCard(context, t, cubit, theme)),
        ] else if (completedTasks.isNotEmpty) ...[
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.creditGreen.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              children: [
                Icon(Icons.done_all_rounded, color: AppColors.creditGreen, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Todas as tarefas estão em dia! Nenhuma pendência no lar.',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.creditGreen),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (completedTasks.isNotEmpty) ...[
          Card(
            elevation: 0,
            margin: const EdgeInsets.only(top: 6, bottom: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: Colors.grey.withValues(alpha: 0.15)),
            ),
            color: theme.cardColor,
            clipBehavior: Clip.antiAlias,
            child: Theme(
              data: theme.copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                initiallyExpanded: false,
                leading: const Icon(
                  Icons.check_circle_outline_rounded,
                  color: AppColors.creditGreen,
                  size: 22,
                ),
                title: Text(
                  'Concluídas (${completedTasks.length})',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                subtitle: Text(
                  state.isShowingHistory
                      ? 'Exibindo histórico completo'
                      : 'Concluídas nos últimos 15 dias',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
                childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                children: [
                  ...completedTasks.map((t) => _buildTaskCard(context, t, cubit, theme)),
                  _buildHistoryBanner(context, state, cubit, theme),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildHistoryBanner(
    BuildContext context,
    CalendarState state,
    CalendarCubit cubit,
    ThemeData theme,
  ) {
    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Icon(
            state.isShowingHistory ? Icons.history_toggle_off_rounded : Icons.history_rounded,
            size: 18,
            color: Colors.grey,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              state.isShowingHistory
                  ? 'Exibindo todo o histórico de tarefas concluídas'
                  : 'Tarefas concluídas há mais de 15 dias estão no histórico',
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ),
          TextButton(
            onPressed: () => cubit.toggleShowHistory(),
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            child: Text(
              state.isShowingHistory ? 'Ocultar antigas' : 'Ver histórico',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyTasksWidget(BuildContext context, String taskFilter, String activeMemberId) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            taskFilter == 'completed'
                ? Icons.checklist_rtl_rounded
                : Icons.task_alt_rounded,
            size: 56,
            color: Colors.grey.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 12),
          Text(
            taskFilter == 'completed'
                ? 'Nenhuma tarefa concluída ainda'
                : 'Nenhuma tarefa pendente! Tudo em ordem no lar.',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.grey),
          ),
          const SizedBox(height: 6),
          const Text(
            'Adicione tarefas para organizar a rotina compartilhada.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 16),
          FilledButton.tonalIcon(
            onPressed: () => AddTaskSheet.show(context, activeMemberId),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Criar Tarefa'),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskCard(BuildContext context, TaskItem task, CalendarCubit cubit, ThemeData theme) {
    Color priorityColor;
    String priorityLabel;
    switch (task.priority) {
      case TaskPriority.high:
        priorityColor = AppColors.debtRed;
        priorityLabel = 'Alta';
        break;
      case TaskPriority.medium:
        priorityColor = Colors.orange;
        priorityLabel = 'Média';
        break;
      case TaskPriority.low:
        priorityColor = Colors.blue;
        priorityLabel = 'Baixa';
        break;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: task.isOverdue
              ? AppColors.debtRed.withValues(alpha: 0.3)
              : Colors.grey.withValues(alpha: 0.15),
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: Checkbox(
          value: task.isCompleted,
          activeColor: AppColors.primary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          onChanged: (_) => cubit.toggleTask(task.id),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                task.title,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  decoration: task.isCompleted ? TextDecoration.lineThrough : null,
                  color: task.isCompleted ? Colors.grey : null,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: priorityColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                priorityLabel,
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: priorityColor),
              ),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (task.description != null && task.description!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(task.description!, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
            const SizedBox(height: 6),
            Row(
              children: [
                if (task.assignedToMemberName != null) ...[
                  const Icon(Icons.person_outline, size: 14, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(
                    task.assignedToMemberName!,
                    style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(width: 12),
                ],
                if (task.dueDate != null) ...[
                  Icon(
                    Icons.calendar_today_outlined,
                    size: 14,
                    color: task.isOverdue ? AppColors.debtRed : Colors.grey,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    DateFormat('dd/MM').format(task.dueDate!),
                    style: TextStyle(
                      fontSize: 12,
                      color: task.isOverdue ? AppColors.debtRed : Colors.grey,
                      fontWeight: task.isOverdue ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  if (task.isOverdue) ...[
                    const SizedBox(width: 4),
                    const Text(
                      '(Atrasada)',
                      style: TextStyle(fontSize: 11, color: AppColors.debtRed, fontWeight: FontWeight.bold),
                    ),
                  ],
                ],
                if (task.cost != null) ...[
                  const Spacer(),
                  Text(
                    task.cost!.formatted,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primary),
                  ),
                ],
              ],
            ),
          ],
        ),
        // Um botão só, para não tirar largura do conteúdo da tarefa
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert_rounded, size: 20, color: Colors.grey),
          tooltip: 'Editar ou excluir tarefa',
          onSelected: (action) {
            if (action == 'edit') {
              AddTaskSheet.show(context, task.createdByMemberId, taskToEdit: task);
            } else {
              cubit.deleteTask(task.id);
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'edit', child: Text('Editar')),
            PopupMenuItem(value: 'delete', child: Text('Excluir')),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // ABA 2: LISTA DE COMPRAS
  // ==========================================
  Widget _buildShoppingTab(BuildContext context, ThemeData theme) {
    return BlocBuilder<ShoppingCubit, ShoppingState>(
      builder: (context, state) {
        return ResponsiveContainer(
          maxWidth: 900,
          child: _buildShoppingColumnContent(
            context,
            state,
            theme,
            isDesktop: false,
          ),
        );
      },
    );
  }

  Widget _buildShoppingColumnContent(
    BuildContext context,
    ShoppingState state,
    ThemeData theme, {
    required bool isDesktop,
  }) {
    final shoppingCubit = context.read<ShoppingCubit>();
    final pendingItems = state.items.where((i) => !i.isBought).toList();
    final boughtItems = state.items.where((i) => i.isBought).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isDesktop) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    const Icon(Icons.shopping_cart_outlined, color: AppColors.primary, size: 22),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Lista de Compras (${state.items.length})',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              if (boughtItems.isNotEmpty) ...[
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: () => _showFinishTripDialog(context, state),
                  icon: const Icon(Icons.receipt_long_rounded, size: 16),
                  label: const Text('Finalizar Compra'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.creditGreen,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
        ],

        // Barra de Adição Rápida de Item
        Padding(
          padding: EdgeInsets.fromLTRB(
            isDesktop ? 0 : 16,
            isDesktop ? 0 : 12,
            isDesktop ? 0 : 16,
            8,
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _addShoppingController,
                  decoration: InputDecoration(
                    hintText: 'Adicionar à lista (ex: Café, Detergente...)',
                    prefixIcon: const Icon(Icons.add_shopping_cart_rounded, size: 20),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FilterChip(
                          label: const Text('Pessoal', style: TextStyle(fontSize: 11)),
                          selected: _isPersonalShoppingItem,
                          visualDensity: VisualDensity.compact,
                          onSelected: (val) => setState(() => _isPersonalShoppingItem = val),
                        ),
                        const SizedBox(width: 6),
                      ],
                    ),
                  ),
                  onSubmitted: (_) => _onAddShoppingItem(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _onAddShoppingItem,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
                child: const Text('Adicionar'),
              ),
            ],
          ),
        ),

        // Barra de Ação de Finalizar Compras (quando há itens comprados)
        if (boughtItems.isNotEmpty)
          Container(
            margin: EdgeInsets.fromLTRB(
              isDesktop ? 0 : 16,
              4,
              isDesktop ? 0 : 16,
              isDesktop ? 10 : 6,
            ),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                const Icon(Icons.shopping_bag_rounded, color: AppColors.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${boughtItems.length} item(ns) no carrinho de compras',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
                if (!isDesktop)
                  FilledButton.icon(
                    onPressed: () => _showFinishTripDialog(context, state),
                    icon: const Icon(Icons.receipt_long_rounded, size: 16),
                    label: const Text('Finalizar Compra'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
              ],
            ),
          ),

        // Listas de Itens (Pendentes e No Carrinho)
        Expanded(
          child: state.items.isEmpty
              ? _buildEmptyShoppingWidget()
              : ListView(
                  padding: EdgeInsets.fromLTRB(
                    isDesktop ? 0 : 16,
                    4,
                    isDesktop ? 0 : 16,
                    isDesktop ? 16 : 80,
                  ),
                  children: [
                    if (pendingItems.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.only(left: 4, bottom: 8, top: 4),
                        child: Text(
                          'A Comprar (${pendingItems.length})',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                      ),
                      ...pendingItems.map((item) => _buildShoppingItemCard(context, item, shoppingCubit, theme)),
                    ],
                    if (boughtItems.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.creditGreen.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.creditGreen.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppColors.creditGreen,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.shopping_cart_checkout_rounded, color: Colors.white, size: 20),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${boughtItems.length} item(ns) no carrinho',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                  const Text(
                                    'Lançar valor no Caixa da Casa e quitar lista',
                                    style: TextStyle(fontSize: 11, color: Colors.grey),
                                  ),
                                ],
                              ),
                            ),
                            FilledButton(
                              onPressed: () => _showFinishTripDialog(context, state),
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.creditGreen,
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              ),
                              child: const Text('Lançar Caixa', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(left: 4, bottom: 8),
                        child: Text(
                          'No Carrinho / Comprados (${boughtItems.length})',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.creditGreen),
                        ),
                      ),
                      ...boughtItems.map((item) => _buildShoppingItemCard(context, item, shoppingCubit, theme)),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildEmptyShoppingWidget() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.shopping_basket_outlined, size: 56, color: Colors.grey.withValues(alpha: 0.4)),
          const SizedBox(height: 12),
          const Text(
            'A lista de compras está vazia!',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.grey),
          ),
          const SizedBox(height: 4),
          const Text(
            'Digite os itens acima para montar a lista coletiva do lar.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  void _onAddShoppingItem() {
    final text = _addShoppingController.text.trim();
    if (text.isEmpty) return;

    final authRepo = sl<AuthRepository>();
    final currentUserId = authRepo.currentUser?.id;
    final isDemo = authRepo.isDemoMode;
    final defaultMemberId = isDemo ? 'member_marina' : currentUserId;

    context.read<ShoppingCubit>().addItem(
          name: text,
          isPersonal: _isPersonalShoppingItem,
          assignedMemberId: _isPersonalShoppingItem ? defaultMemberId : null,
        );

    _addShoppingController.clear();
    setState(() => _isPersonalShoppingItem = false);
  }

  Widget _buildShoppingItemCard(BuildContext context, ShoppingItem item, ShoppingCubit cubit, ThemeData theme) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        leading: Checkbox(
          value: item.isBought,
          activeColor: AppColors.creditGreen,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          onChanged: (_) => cubit.toggleItemBought(item.id),
        ),
        title: Text(
          item.name,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
            decoration: item.isBought ? TextDecoration.lineThrough : null,
            color: item.isBought ? Colors.grey : null,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (item.isPersonal)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Pessoal',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.accent),
                ),
              ),
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 18, color: Colors.grey),
              tooltip: 'Editar item',
              onPressed: () => _showEditItemDialog(context, item, cubit),
            ),
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 18, color: Colors.grey),
              tooltip: 'Remover da lista',
              onPressed: () => cubit.deleteItem(item.id),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditItemDialog(BuildContext context, ShoppingItem item, ShoppingCubit cubit) {
    final nameController = TextEditingController(text: item.name);
    final quantityController = TextEditingController(
      text: item.quantity == item.quantity.roundToDouble()
          ? item.quantity.toInt().toString()
          : item.quantity.toString().replaceAll('.', ','),
    );
    var isPersonal = item.isPersonal;

    showDialog<void>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) => AlertDialog(
          title: const Text('Editar item'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Item',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: quantityController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Quantidade',
                  suffixText: item.unit,
                  border: const OutlineInputBorder(),
                ),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Item Pessoal (só meu)', style: TextStyle(fontSize: 14)),
                value: isPersonal,
                onChanged: (val) => setDialogState(() => isPersonal = val ?? false),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                final name = nameController.text.trim();
                final quantity = double.tryParse(quantityController.text.trim().replaceAll(',', '.'));
                if (name.isEmpty || quantity == null || quantity <= 0) return;
                cubit.updateItem(
                  item.copyWith(name: name, quantity: quantity, isPersonal: isPersonal),
                );
                Navigator.pop(dialogCtx);
              },
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
  }

  void _showFinishTripDialog(BuildContext context, ShoppingState state) {
    final financeState = context.read<FinanceCubit>().state;
    final paymentMethods = financeState.paymentMethods;
    final members = financeState.members;

    final amountController = MoneyTextEditingController(allowEmpty: false);
    final personalAmountController = MoneyTextEditingController(allowEmpty: true);
    final currentUserId = sl<AuthRepository>().currentUser?.id ?? 'member_carlos';
    // Quem fecha a compra é, por padrão, quem pagou; a forma de pagamento sugerida é a dele
    String selectedPayerId = members.any((m) => m.id == currentUserId)
        ? currentUserId
        : (members.isNotEmpty ? members.first.id : currentUserId);
    String? selectedPmId = (paymentMethods.where((p) => p.ownerMemberId == selectedPayerId).firstOrNull ??
            paymentMethods.firstOrNull)
        ?.id;

    final personalItems = state.items.where((i) => i.isBought && i.isPersonal).toList();
    final hasPersonal = personalItems.isNotEmpty;

    // Dono dos itens pessoais: por padrão quem está logado. Se for o próprio
    // pagador, o valor só sai da despesa da casa; se for outro morador, vira
    // empréstimo dele para quem pagou.
    String selectedDebtorId = members.any((m) => m.id == currentUserId)
        ? currentUserId
        : (members.isNotEmpty ? members.first.id : currentUserId);

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Row(
                children: [
                  Icon(Icons.shopping_bag_outlined, color: AppColors.primary),
                  SizedBox(width: 8),
                  Text('Finalizar Compra da Casa', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
              content: SizedBox(
                width: 480,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Lança o gasto no Caixa da Casa e calcula ressarcimento para itens pessoais.',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const SizedBox(height: 16),
                      MoneyTextFormField(
                        controller: amountController,
                        labelText: 'Valor Total da Nota Fiscal',
                        hintText: 'R\$ 0,00',
                        prefixIcon: const Icon(Icons.receipt_long_rounded),
                        allowEmpty: false,
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: selectedPmId,
                        decoration: InputDecoration(
                          labelText: 'Forma de Pagamento',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        items: paymentMethods.map((pm) {
                          return DropdownMenuItem(value: pm.id, child: Text(pm.name));
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) setDialogState(() => selectedPmId = val);
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: selectedPayerId,
                        decoration: InputDecoration(
                          labelText: 'Quem Pagou no Caixa',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        items: members.map((m) {
                          return DropdownMenuItem(value: m.id, child: Text(m.name));
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) setDialogState(() => selectedPayerId = val);
                        },
                      ),
                      if (hasPersonal) ...[
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.amber.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Há ${personalItems.length} item(ns) pessoais nesta compra!',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.orange),
                              ),
                              const SizedBox(height: 8),
                              MoneyTextFormField(
                                controller: personalAmountController,
                                labelText: 'Subtotal dos Itens Pessoais',
                                hintText: 'R\$ 0,00',
                                prefixIcon: const Icon(Icons.person_pin_circle_outlined),
                                allowEmpty: true,
                              ),
                              if (members.isNotEmpty) ...[
                                const SizedBox(height: 10),
                                DropdownButtonFormField<String>(
                                  initialValue: selectedDebtorId,
                                  decoration: InputDecoration(
                                    labelText: 'De quem são os itens pessoais',
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                  items: members.map((m) {
                                    return DropdownMenuItem(value: m.id, child: Text(m.name));
                                  }).toList(),
                                  onChanged: (val) {
                                    if (val != null) setDialogState(() => selectedDebtorId = val);
                                  },
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogCtx),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () {
                    final total = amountController.money;
                    if (total.isZero) return;

                    Money? personalMoney;
                    if (personalAmountController.text.isNotEmpty && personalAmountController.cents > 0) {
                      personalMoney = personalAmountController.money;
                    }

                    Navigator.pop(dialogCtx);

                    context.read<ShoppingCubit>().completeTrip(
                          totalAmount: total,
                          paymentMethodId: selectedPmId ?? 'pm_caixa',
                          paidByMemberId: selectedPayerId,
                          personalItemsAmount: personalMoney,
                          personalDebtorMemberId: selectedDebtorId,
                        ).then((_) {
                      if (context.mounted) {
                        context.read<FinanceCubit>().loadCycleData();
                        context.read<P2PCubit>().loadLoans();
                      }
                    });

                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        backgroundColor: AppColors.creditGreen,
                        content: Text('Compra de ${total.formatted} lançada com sucesso no Caixa da Casa! 🛒🎉'),
                      ),
                    );
                  },
                  child: const Text('Confirmar e Lançar'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
