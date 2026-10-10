import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../../../core/domain/value_objects/money.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/responsive_container.dart';
import '../../../calendar/domain/entities/task_item.dart';
import '../../../calendar/presentation/cubit/calendar_cubit.dart';
import '../../../calendar/presentation/cubit/calendar_state.dart';
import '../../../calendar/presentation/widgets/add_task_sheet.dart';
import '../../../finance/presentation/cubit/finance_cubit.dart';
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
  String _taskFilter = 'all'; // 'all', 'pending', 'completed'
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
  void dispose() {
    _tabController.dispose();
    _addShoppingController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
  // ABA 1: TAREFAS DA CASA
  // ==========================================
  Widget _buildTasksTab(BuildContext context, ThemeData theme) {
    return BlocBuilder<CalendarCubit, CalendarState>(
      builder: (context, state) {
        final cubit = context.read<CalendarCubit>();
        List<TaskItem> filteredTasks = state.tasks;

        if (_taskFilter == 'pending') {
          filteredTasks = filteredTasks.where((t) => !t.isCompleted).toList();
        } else if (_taskFilter == 'completed') {
          filteredTasks = filteredTasks.where((t) => t.isCompleted).toList();
        }

        final pendingCount = state.tasks.where((t) => !t.isCompleted).length;
        final completedCount = state.tasks.where((t) => t.isCompleted).length;

        return ResponsiveContainer(
          maxWidth: 900,
          child: Column(
            children: [
              // Barra de Filtros e Ação
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      ChoiceChip(
                        label: Text('Todas (${state.tasks.length})'),
                        selected: _taskFilter == 'all',
                        onSelected: (_) => setState(() => _taskFilter = 'all'),
                      ),
                      const SizedBox(width: 8),
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
                  ),
                ),
              ),

              // Lista de Tarefas
              Expanded(
                child: filteredTasks.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _taskFilter == 'completed'
                                  ? Icons.checklist_rtl_rounded
                                  : Icons.task_alt_rounded,
                              size: 56,
                              color: Colors.grey.withValues(alpha: 0.4),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _taskFilter == 'completed'
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
                              onPressed: () => AddTaskSheet.show(context, state.activeMemberId),
                              icon: const Icon(Icons.add_rounded),
                              label: const Text('Criar Tarefa'),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
                        itemCount: filteredTasks.length,
                        itemBuilder: (context, index) {
                          final task = filteredTasks[index];
                          return _buildTaskCard(context, task, cubit, theme);
                        },
                      ),
              ),
            ],
          ),
        );
      },
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
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline_rounded, size: 20, color: Colors.grey),
          tooltip: 'Excluir tarefa',
          onPressed: () => cubit.deleteTask(task.id),
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
        final shoppingCubit = context.read<ShoppingCubit>();
        final pendingItems = state.items.where((i) => !i.isBought).toList();
        final boughtItems = state.items.where((i) => i.isBought).toList();

        return ResponsiveContainer(
          maxWidth: 900,
          child: Column(
            children: [
              // Barra de Adição Rápida de Item
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
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
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
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
                    ? Center(
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
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
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
          ),
        );
      },
    );
  }

  void _onAddShoppingItem() {
    final text = _addShoppingController.text.trim();
    if (text.isEmpty) return;

    context.read<ShoppingCubit>().addItem(
          name: text,
          isPersonal: _isPersonalShoppingItem,
          assignedMemberId: _isPersonalShoppingItem ? 'member_marina' : null,
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
              icon: const Icon(Icons.close_rounded, size: 18, color: Colors.grey),
              tooltip: 'Remover da lista',
              onPressed: () => cubit.deleteItem(item.id),
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

    final amountController = TextEditingController();
    final personalAmountController = TextEditingController();
    String? selectedPmId = paymentMethods.isNotEmpty ? paymentMethods.first.id : null;
    String selectedPayerId = 'member_carlos';
    String selectedDebtorId = 'member_marina';

    final personalItems = state.items.where((i) => i.isBought && i.isPersonal).toList();
    final hasPersonal = personalItems.isNotEmpty;

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
                      TextField(
                        controller: amountController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: 'Valor Total da Nota Fiscal',
                          prefixText: 'R\$ ',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: selectedPmId,
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
                        value: selectedPayerId,
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
                              TextField(
                                controller: personalAmountController,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: InputDecoration(
                                  labelText: 'Subtotal dos Itens Pessoais',
                                  prefixText: 'R\$ ',
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                              ),
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
                    final total = Money.parse(amountController.text);
                    if (total.isZero) return;

                    Money? personalMoney;
                    if (personalAmountController.text.isNotEmpty) {
                      personalMoney = Money.parse(personalAmountController.text);
                    }

                    Navigator.pop(dialogCtx);

                    context.read<ShoppingCubit>().completeTrip(
                          totalAmount: total,
                          paymentMethodId: selectedPmId ?? 'pm_caixa',
                          paidByMemberId: selectedPayerId,
                          personalItemsAmount: personalMoney,
                          personalDebtorMemberId: selectedDebtorId,
                        );

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
