import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/domain/value_objects/money.dart';
import '../../../../core/widgets/money_input_field.dart';
import '../../../auth/domain/repositories/auth_repository.dart';
import '../../../projects/domain/entities/shared_project.dart';
import '../../../projects/domain/repositories/projects_repository.dart';
import '../../domain/entities/house_expense.dart';
import '../../domain/entities/house_expense_item.dart';
import '../../domain/entities/split_rule.dart';
import '../../domain/entities/category.dart';
import '../../domain/entities/payment_method.dart';
import '../../domain/services/credit_card_invoice_calculator.dart';
import '../../../../core/domain/enums/recurrence.dart';
import '../../../../core/widgets/recurrence_scope_dialog.dart';
import '../cubit/finance_cubit.dart';
import '../cubit/finance_state.dart';

class _DraftExpenseItem {
  final TextEditingController titleController;
  int cents;
  String? categoryId;
  String? responsibleMemberId;

  _DraftExpenseItem({
    required String title,
    required this.cents,
    this.categoryId,
    this.responsibleMemberId,
  }) : titleController = TextEditingController(text: title);

  void dispose() {
    titleController.dispose();
  }
}

class AddExpensePage extends StatefulWidget {
  final bool isRecurringDefault;
  final HouseExpense? expenseToEdit;

  const AddExpensePage({
    super.key,
    this.isRecurringDefault = false,
    this.expenseToEdit,
  });

  @override
  State<AddExpensePage> createState() => _AddExpensePageState();
}

class _AddExpensePageState extends State<AddExpensePage> {
  final _titleController = TextEditingController();

  String? _selectedCategoryId;
  String? _selectedPaidByMemberId;
  String? _selectedPaymentMethodId;
  String? _selectedProjectId;
  List<SharedProject> _availableProjects = [];
  final SplitType _selectedSplitType = SplitType.percentage;
  DateTime _selectedDate = DateTime.now();

  late bool _isRecurring;
  bool _isVariable = false;
  int _dueDay = DateTime.now().day;
  ExpenseStatus _expenseStatus = ExpenseStatus.paid;

  int _cents = 0;

  bool _isItemized = false;
  final List<_DraftExpenseItem> _draftItems = [];
  String? _attachedReceiptName;

  @override
  void initState() {
    super.initState();
    final edit = widget.expenseToEdit;
    if (edit != null) {
      _titleController.text = edit.title;
      _cents = edit.amount.cents;
      _selectedCategoryId = edit.categoryId;
      _selectedPaidByMemberId = edit.paidByMemberId;
      _selectedPaymentMethodId = edit.paymentMethodId;
      _selectedProjectId = edit.projectId;
      _selectedDate = edit.dueDate ?? edit.date;
      _isRecurring = edit.isRecurring;
      _isVariable = edit.isVariable;
      _dueDay = edit.dueDay ?? (edit.dueDate ?? edit.date).day;
      _expenseStatus = edit.status;
      _isItemized = edit.items.isNotEmpty;
      if (edit.items.isNotEmpty) {
        _draftItems.addAll(edit.items.map((it) => _DraftExpenseItem(
          title: it.title,
          cents: it.amount.cents,
          categoryId: it.categoryId,
          responsibleMemberId: it.responsibleMemberId,
        )));
      }
    } else {
      _isRecurring = widget.isRecurringDefault;
      if (_isRecurring) {
        _expenseStatus = ExpenseStatus.pending;
      }
    }
    _loadAvailableProjects();
  }

  Future<void> _loadAvailableProjects() async {
    try {
      if (sl.isRegistered<ProjectsRepository>()) {
        final projects = await sl<ProjectsRepository>().getProjects(houseId: 'house_demo');
        if (mounted) {
          setState(() {
            _availableProjects = projects;
          });
        }
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _titleController.dispose();
    for (final item in _draftItems) {
      item.dispose();
    }
    super.dispose();
  }

  void _applyCondoPreset(FinanceState state) {
    for (final item in _draftItems) {
      item.dispose();
    }
    _draftItems.clear();

    final moradiaCatId = state.categories.where((c) => c.name.toLowerCase().contains('moradia')).firstOrNull?.id 
        ?? state.categories.firstOrNull?.id;
    final contasCatId = state.categories.where((c) => c.name.toLowerCase().contains('conta')).firstOrNull?.id 
        ?? state.categories.firstOrNull?.id;
    final firstMemberId = state.members.firstOrNull?.id;

    if (_cents == 85000) {
      _draftItems.addAll([
        _DraftExpenseItem(title: 'Taxa Condomínio Ordinária', cents: 50000, categoryId: moradiaCatId),
        _DraftExpenseItem(title: 'Consumo de Água', cents: 12000, categoryId: contasCatId),
        _DraftExpenseItem(title: 'Gás Encanado', cents: 8000, categoryId: contasCatId),
        _DraftExpenseItem(title: 'Fundo de Obras / Reserva', cents: 15000, categoryId: moradiaCatId, responsibleMemberId: firstMemberId),
      ]);
    } else if (_cents > 0) {
      final part = _cents ~/ 4;
      final rest = _cents - (part * 4);
      _draftItems.addAll([
        _DraftExpenseItem(title: 'Taxa Condomínio Ordinária', cents: part + rest, categoryId: moradiaCatId),
        _DraftExpenseItem(title: 'Consumo de Água', cents: part, categoryId: contasCatId),
        _DraftExpenseItem(title: 'Gás Encanado', cents: part, categoryId: contasCatId),
        _DraftExpenseItem(title: 'Fundo de Obras / Reserva', cents: part, categoryId: moradiaCatId, responsibleMemberId: firstMemberId),
      ]);
    } else {
      _draftItems.addAll([
        _DraftExpenseItem(title: 'Taxa Condomínio Ordinária', cents: 0, categoryId: moradiaCatId),
        _DraftExpenseItem(title: 'Consumo de Água', cents: 0, categoryId: contasCatId),
        _DraftExpenseItem(title: 'Gás Encanado', cents: 0, categoryId: contasCatId),
        _DraftExpenseItem(title: 'Fundo de Obras / Reserva', cents: 0, categoryId: moradiaCatId, responsibleMemberId: firstMemberId),
      ]);
    }
  }

  Future<void> _submit() async {
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor, digite o nome da despesa')),
      );
      return;
    }

    if (_cents <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('O valor deve ser maior que zero')),
      );
      return;
    }

    if (_isItemized) {
      if (_draftItems.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Adicione pelo menos um sub-item ou desative o boleto composto.')),
        );
        return;
      }
      final itemsSumCents = _draftItems.fold<int>(0, (acc, item) => acc + item.cents);
      if (itemsSumCents != _cents) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red.shade700,
            content: Text(
              'A soma dos sub-itens (${Money(itemsSumCents).format()}) deve ser igual ao valor total do boleto (${Money(_cents).format()}).',
            ),
          ),
        );
        return;
      }
    }

    final state = context.read<FinanceCubit>().state;
    final catId = _selectedCategoryId ?? state.categories.firstOrNull?.id ?? '';
    final paidById = _selectedPaidByMemberId ?? state.members.firstOrNull?.id ?? sl<AuthRepository>().currentUser?.id ?? '';
    final pmId = _selectedPaymentMethodId ?? state.paymentMethods.firstOrNull?.id ?? '';

    // Determina a regra de rateio de forma resiliente
    final category = state.categories.where((c) => c.id == catId).firstOrNull;
    SplitRule rule;
    if (category != null && (category.hasOwner || _selectedSplitType == SplitType.categoryOwner)) {
      rule = SplitRule.singleResponsible(category.ownerMemberId ?? paidById);
    } else {
      if (state.members.isNotEmpty) {
        final percentMap = <String, double>{};
        for (final m in state.members) {
          percentMap[m.id] = m.defaultSplitPercent;
        }
        rule = SplitRule.percentage(percentMap);
      } else {
        rule = SplitRule.singleResponsible(paidById);
      }
    }

    final now = DateTime.now();
    DateTime expenseDate = _selectedDate;
    DateTime? dueDate;

    final selectedPm = state.paymentMethods.where((p) => p.id == pmId).firstOrNull;
    final isHouseMethod = selectedPm == null
        ? (pmId == 'pm_caixa')
        : (selectedPm.ownerMemberId == null || selectedPm.id == 'pm_caixa');
    final paidOutOfPocket = !isHouseMethod;

    if (_isRecurring) {
      final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
      final safeDay = _dueDay.clamp(1, daysInMonth);
      dueDate = DateTime(now.year, now.month, safeDay);
      expenseDate = _expenseStatus == ExpenseStatus.paid ? now : dueDate;
    } else if (selectedPm != null &&
        selectedPm.type == PaymentMethodType.card &&
        selectedPm.closingDay != null &&
        selectedPm.dueDay != null) {
      dueDate = CreditCardInvoiceCalculator.calculateInvoiceDueDate(
        purchaseDate: _selectedDate,
        closingDay: selectedPm.closingDay!,
        dueDay: selectedPm.dueDay!,
      );
    } else {
      if (_expenseStatus == ExpenseStatus.pending) {
        dueDate = _selectedDate;
      }
    }

    if (widget.expenseToEdit != null) {
      final oldExpense = widget.expenseToEdit!;
      RecurrenceScope chosenScope = RecurrenceScope.thisInstanceOnly;
      if (oldExpense.isRecurring) {
        final scope = await showRecurrenceScopeDialog(
          context: context,
          itemTitle: oldExpense.title,
          isDelete: false,
          isExpense: true,
        );
        if (scope == null) return;
        chosenScope = scope;
      }

      final expenseId = oldExpense.id;
      final List<HouseExpenseItem> items = _isItemized
          ? _draftItems.asMap().entries.map((entry) {
              final idx = entry.key;
              final draft = entry.value;
              final itemTitle = draft.titleController.text.trim().isEmpty
                  ? 'Sub-item #${idx + 1}'
                  : draft.titleController.text.trim();
              return HouseExpenseItem(
                id: 'item_${expenseId}_$idx',
                expenseId: expenseId,
                title: itemTitle,
                amount: Money(draft.cents),
                categoryId: draft.categoryId ?? catId,
                responsibleMemberId: draft.responsibleMemberId,
                splitRule: draft.responsibleMemberId != null
                    ? SplitRule.singleResponsible(draft.responsibleMemberId!)
                    : null,
              );
            }).toList()
          : const [];

      final updatedExpense = oldExpense.copyWith(
        title: _titleController.text.trim(),
        amount: Money(_cents),
        date: expenseDate,
        dueDate: dueDate,
        categoryId: catId,
        paidByMemberId: paidById,
        paymentMethodId: pmId,
        splitRule: rule,
        paidOutOfPocket: paidOutOfPocket,
        status: _expenseStatus,
        // Conta que estava pendente e foi marcada como paga agora
        paidAt: _expenseStatus == ExpenseStatus.paid && oldExpense.isPending
            ? DateTime.now()
            : null,
        clearPaidAt: _expenseStatus == ExpenseStatus.pending,
        isRecurring: _isRecurring,
        isVariable: _isVariable,
        dueDay: _isRecurring ? _dueDay : null,
        items: items,
        projectId: _selectedProjectId,
      );

      if (!mounted) return;
      await context.read<FinanceCubit>().updateExpense(updatedExpense, scope: chosenScope);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Despesa atualizada com sucesso! ✏️'),
        ),
      );
      return;
    }

    final expenseId = 'exp_${DateTime.now().millisecondsSinceEpoch}';
    final List<HouseExpenseItem> items = _isItemized
        ? _draftItems.asMap().entries.map((entry) {
              final idx = entry.key;
              final draft = entry.value;
              final itemTitle = draft.titleController.text.trim().isEmpty
                  ? 'Sub-item #${idx + 1}'
                  : draft.titleController.text.trim();
              return HouseExpenseItem(
                id: 'item_${expenseId}_$idx',
                expenseId: expenseId,
                title: itemTitle,
                amount: Money(draft.cents),
                categoryId: draft.categoryId ?? catId,
                responsibleMemberId: draft.responsibleMemberId,
                splitRule: draft.responsibleMemberId != null
                    ? SplitRule.singleResponsible(draft.responsibleMemberId!)
                    : null,
              );
            }).toList()
          : const [];

    final expense = HouseExpense(
      id: expenseId,
      title: _titleController.text.trim(),
      amount: Money(_cents),
      date: expenseDate,
      dueDate: dueDate,
      categoryId: catId,
      paidByMemberId: paidById,
      paymentMethodId: pmId,
      splitRule: rule,
      paidOutOfPocket: paidOutOfPocket,
      status: _expenseStatus,
      isRecurring: _isRecurring,
      isVariable: _isVariable,
      dueDay: _isRecurring ? _dueDay : null,
      items: items,
      projectId: _selectedProjectId,
    );

    context.read<FinanceCubit>().addExpense(expense);
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_isRecurring
            ? 'Despesa recorrente cadastrada com sucesso! 🔁'
            : (_isItemized
                ? 'Boleto composto lançado com ${items.length} sub-itens! 🏢'
                : 'Gasto da casa lançado com sucesso! 🎉')),
      ),
    );
  }

  Future<void> _confirmAndDelete() async {
    final exp = widget.expenseToEdit;
    if (exp == null) return;

    RecurrenceScope scope = RecurrenceScope.thisInstanceOnly;
    if (exp.isRecurring) {
      final chosenScope = await showRecurrenceScopeDialog(
        context: context,
        itemTitle: exp.title,
        isDelete: true,
        isExpense: true,
      );
      if (chosenScope == null) return;
      scope = chosenScope;
    } else {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Excluir Despesa'),
          content: Text('Tem certeza que deseja excluir "${exp.title}"?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.debtRed,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Excluir'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    if (!mounted) return;
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final cubit = context.read<FinanceCubit>();

    await cubit.deleteExpense(exp.id, scope: scope);
    if (mounted) {
      nav.pop();
      messenger.showSnackBar(
        SnackBar(content: Text('Despesa "${exp.title}" excluída com sucesso! 🗑️')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return BlocBuilder<FinanceCubit, FinanceState>(
      builder: (context, state) {
        if (state.members.isNotEmpty &&
            (_selectedPaidByMemberId == null ||
                !state.members.any((m) => m.id == _selectedPaidByMemberId))) {
          _selectedPaidByMemberId = state.members.first.id;
        }
        if (state.categories.isNotEmpty &&
            (_selectedCategoryId == null ||
                !state.categories.any((c) => c.id == _selectedCategoryId))) {
          _selectedCategoryId = state.categories.first.id;
        }
        if (state.paymentMethods.isNotEmpty &&
            (_selectedPaymentMethodId == null ||
                !state.paymentMethods.any((pm) => pm.id == _selectedPaymentMethodId))) {
          _selectedPaymentMethodId = state.paymentMethods.first.id;
        }

        final selectedCategory = state.categories.where(
          (c) => c.id == _selectedCategoryId,
        ).firstOrNull ?? (state.categories.isNotEmpty
            ? state.categories.first
            : const ExpenseCategory(id: '', name: '', icon: '', colorHex: ''));

        return Scaffold(
          appBar: AppBar(
            title: Text(
              widget.expenseToEdit != null
                  ? 'Editar Despesa'
                  : (_isRecurring ? 'Nova Despesa Recorrente' : 'Gasto da Casa'),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            leading: IconButton(
              icon: const Icon(Icons.close_rounded),
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              if (widget.expenseToEdit != null)
                IconButton(
                  tooltip: 'Excluir despesa',
                  icon: const Icon(Icons.delete_outline_rounded, color: AppColors.debtRed),
                  onPressed: _confirmAndDelete,
                ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              // Campo ATM Contínuo de Valor
              MoneyInputField(
                label: _isRecurring && _isVariable ? 'Valor Estimado do Mês' : 'Valor da Despesa',
                initialValue: Money(_cents),
                primaryColor: AppColors.primary,
                quickAddCents: const [1000, 2000, 5000, 10000], // +10, +20, +50, +100
                onChanged: (money) {
                  setState(() {
                    _cents = money.cents;
                  });
                },
              ),
              const SizedBox(height: 20),

              // Input de Nome / Descrição
              TextField(
                controller: _titleController,
                decoration: InputDecoration(
                  labelText: 'O que foi pago?',
                  hintText: 'Ex: Supermercado, Aluguel, Luz, Netflix',
                  prefixIcon: const Icon(Icons.receipt_long_outlined),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 20),

              // Data e Situação da Despesa (Retroativa, Atual ou Em Atraso) para compras avulsas
              if (!_isRecurring) ...[
                _buildDateAndStatusCard(theme),
                const SizedBox(height: 20),
              ],

              // Seção de Recorrência (Assinaturas / Contas Fixas / Variáveis)
              Material(
                color: _isRecurring
                    ? AppColors.primary.withValues(alpha: 0.06)
                    : theme.cardColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: _isRecurring
                        ? AppColors.primary.withValues(alpha: 0.4)
                        : theme.dividerColor,
                    width: _isRecurring ? 1.5 : 1,
                  ),
                ),
                child: Column(
                  children: [
                    SwitchListTile(
                      secondary: Icon(
                        Icons.repeat_rounded,
                        color: _isRecurring ? AppColors.primary : Colors.grey,
                      ),
                      title: const Text(
                        'Repetir todo mês (Recorrente)',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      subtitle: Text(
                        _isRecurring
                            ? (_isVariable
                                ? 'Conta de consumo (Luz, Água, Gás)'
                                : 'Assinatura fixa (Netflix, Internet, Aluguel)')
                            : 'Ative para contas fixas ou assinaturas mensais',
                        style: const TextStyle(fontSize: 12),
                      ),
                      value: _isRecurring,
                      onChanged: (val) {
                        setState(() {
                          _isRecurring = val;
                          if (_isRecurring) {
                            _expenseStatus = ExpenseStatus.pending;
                          }
                        });
                      },
                    ),
                    if (_isRecurring) ...[
                      const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Tipo de Recorrência: Fixa vs Variável
                            const Text(
                              'Tipo de Conta',
                              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: ChoiceChip(
                                    avatar: const Icon(Icons.lock_clock_rounded, size: 16),
                                    label: const Center(child: Text('Valor Fixo')),
                                    selected: !_isVariable,
                                    selectedColor: AppColors.primary.withValues(alpha: 0.15),
                                    onSelected: (selected) {
                                      if (selected) setState(() => _isVariable = false);
                                    },
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: ChoiceChip(
                                    avatar: const Icon(Icons.trending_up_rounded, size: 16),
                                    label: const Center(child: Text('Valor Variável')),
                                    selected: _isVariable,
                                    selectedColor: AppColors.primary.withValues(alpha: 0.15),
                                    onSelected: (selected) {
                                      if (selected) setState(() => _isVariable = true);
                                    },
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),

                            // Dia do Vencimento
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Dia do Vencimento',
                                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: DropdownButton<int>(
                                    value: _dueDay,
                                    underline: const SizedBox(),
                                    isDense: true,
                                    items: List.generate(31, (i) => i + 1).map((day) {
                                      return DropdownMenuItem<int>(
                                        value: day,
                                        child: Text('Todo dia $day',
                                            style: const TextStyle(fontWeight: FontWeight.bold)),
                                      );
                                    }).toList(),
                                    onChanged: (val) {
                                      if (val != null) setState(() => _dueDay = val);
                                    },
                                  ),
                                ),
                              ],
                            ),
                              const SizedBox(height: 14),

                              // Situação no Ciclo Atual
                              const Text(
                                'Situação no Ciclo Atual',
                                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: ChoiceChip(
                                      avatar: const Icon(Icons.check_circle_outline, size: 16),
                                      label: const Center(child: Text('Já Paga')),
                                      selected: _expenseStatus == ExpenseStatus.paid,
                                      selectedColor: AppColors.creditGreen.withValues(alpha: 0.15),
                                      onSelected: (selected) {
                                        if (selected) setState(() => _expenseStatus = ExpenseStatus.paid);
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: ChoiceChip(
                                      avatar: const Icon(Icons.schedule_rounded, size: 16),
                                      label: const Center(child: Text('A Vencer')),
                                      selected: _expenseStatus == ExpenseStatus.pending,
                                      selectedColor: AppColors.folegoWarning.withValues(alpha: 0.2),
                                      onSelected: (selected) {
                                        if (selected) setState(() => _expenseStatus = ExpenseStatus.pending);
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                ),
              ),
              const SizedBox(height: 20),

              // Seção de Segmentação / Boleto Composto
              Material(
                color: _isItemized
                    ? AppColors.primary.withValues(alpha: 0.04)
                    : theme.cardColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: _isItemized
                        ? AppColors.primary.withValues(alpha: 0.4)
                        : theme.dividerColor,
                    width: _isItemized ? 1.5 : 1,
                  ),
                ),
                child: Column(
                  children: [
                    SwitchListTile(
                      secondary: Icon(
                        Icons.account_tree_outlined,
                        color: _isItemized ? AppColors.primary : Colors.grey,
                      ),
                      title: const Text(
                        'Desmembrar Sub-itens (Boleto Composto)',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      subtitle: Text(
                        _isItemized
                            ? 'Segmentado em água, condomínio, gás, obras...'
                            : 'Ative para discriminar condomínio com água, gás, obras ou donos diferentes',
                        style: const TextStyle(fontSize: 12),
                      ),
                      value: _isItemized,
                      onChanged: (val) {
                        setState(() {
                          _isItemized = val;
                          if (_isItemized && _draftItems.isEmpty) {
                            _applyCondoPreset(state);
                          }
                        });
                      },
                    ),
                    if (_isItemized) ...[
                      const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildItemizedBalanceBanner(theme),
                            const SizedBox(height: 14),
                            ..._draftItems.asMap().entries.map((entry) {
                              final index = entry.key;
                              final item = entry.value;
                              return _buildDraftItemCard(theme, state, index, item);
                            }),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    icon: const Icon(Icons.add_rounded, size: 18),
                                    label: const Text('Adicionar Sub-item'),
                                    onPressed: () {
                                      setState(() {
                                        final sum = _draftItems.fold<int>(0, (acc, i) => acc + i.cents);
                                        final remaining = _cents > sum ? _cents - sum : 0;
                                        _draftItems.add(_DraftExpenseItem(
                                          title: '',
                                          cents: remaining,
                                          categoryId: _selectedCategoryId,
                                        ));
                                      });
                                    },
                                  ),
                                ),
                                const SizedBox(width: 8),
                                OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _applyCondoPreset(state);
                                    });
                                  },
                                  child: const Text('Preset Condomínio'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Seletor de Categoria
              Text('Categoria', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              if (state.categories.isEmpty)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline_rounded, color: Colors.amber, size: 20),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Nenhuma categoria encontrada. Uma categoria geral será atribuída.',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: state.categories.map((cat) {
                    final isSelected = cat.id == _selectedCategoryId;
                    return ChoiceChip(
                      label: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(cat.name),
                          if (cat.hasOwner) ...[
                            const SizedBox(width: 4),
                            const Icon(Icons.person_rounded, size: 14),
                          ],
                        ],
                      ),
                      selected: isSelected,
                      selectedColor: AppColors.primary.withValues(alpha: 0.15),
                      onSelected: (selected) {
                        if (selected) {
                          setState(() {
                            _selectedCategoryId = cat.id;
                          });
                        }
                      },
                    );
                  }).toList(),
                ),
              if (selectedCategory.hasOwner) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline_rounded, color: AppColors.accent, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Categoria com Responsável: Alocado 100% para o dono da categoria.',
                          style: theme.textTheme.bodySmall?.copyWith(color: AppColors.accent),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),

              // Quem Pagou
              Text('Quem Pagou / É Responsável?', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              if (state.members.isEmpty)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.person_outline_rounded, color: AppColors.primary, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Registrando como: ${sl<AuthRepository>().currentUser?.fullName ?? "Você"}',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                )
              else
                Row(
                  children: state.members.map((m) {
                    final isSelected = m.id == _selectedPaidByMemberId;
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            backgroundColor: isSelected ? AppColors.primary.withValues(alpha: 0.12) : null,
                            side: BorderSide(
                              color: isSelected ? AppColors.primary : theme.dividerColor,
                              width: isSelected ? 2 : 1,
                            ),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          onPressed: () {
                            setState(() {
                              _selectedPaidByMemberId = m.id;
                            });
                          },
                          child: Text(
                            m.name,
                            style: TextStyle(
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              color: isSelected ? AppColors.primary : null,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              const SizedBox(height: 20),

              // Vincular a Projeto / Viagem (Opcional)
              Text('Vincular a Projeto / Viagem (Opcional)', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              DropdownButtonFormField<String?>(
                key: const Key('add_expense_project_dropdown'),
                initialValue: _selectedProjectId,
                isExpanded: true,
                decoration: InputDecoration(
                  hintText: 'Nenhum projeto (Gasto Geral da Casa)',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  prefixIcon: const Icon(Icons.flight_takeoff_rounded),
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Nenhum projeto (Gasto Geral da Casa)', overflow: TextOverflow.ellipsis),
                  ),
                  if (_selectedProjectId != null && !_availableProjects.any((p) => p.id == _selectedProjectId))
                    DropdownMenuItem<String?>(
                      value: _selectedProjectId,
                      child: Text('Projeto Selecionado ($_selectedProjectId)', overflow: TextOverflow.ellipsis),
                    ),
                  ..._availableProjects.map((p) {
                    final tag = p.type == ProjectType.trip ? '🏖️ (Viagem)' : '🛠️ (Projeto)';
                    return DropdownMenuItem<String?>(
                      value: p.id,
                      child: Text('${p.title} $tag', overflow: TextOverflow.ellipsis),
                    );
                  }),
                ],
                onChanged: (val) {
                  setState(() {
                    _selectedProjectId = val;
                  });
                },
              ),
              const SizedBox(height: 20),

              // Forma de Pagamento
              Text('Forma de Pagamento', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Builder(
                builder: (context) {
                  final currentPm = state.paymentMethods
                      .where((p) => p.id == _selectedPaymentMethodId)
                      .firstOrNull;
                  final isHouse = currentPm == null
                      ? (_selectedPaymentMethodId == 'pm_caixa')
                      : (currentPm.ownerMemberId == null || currentPm.id == 'pm_caixa');

                  return DropdownButtonFormField<String>(
                    initialValue: _selectedPaymentMethodId,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      prefixIcon: const Icon(Icons.credit_card_rounded),
                      helperText: isHouse
                          ? 'Meio da Casa: despesa conjunta (sem reembolso pessoal)'
                          : null,
                    ),
                    hint: const Text('Selecione uma forma de pagamento'),
                    items: state.paymentMethods.isNotEmpty
                        ? state.paymentMethods.map((pm) {
                            return DropdownMenuItem(
                              value: pm.id,
                              child: Text(pm.name),
                            );
                          }).toList()
                        : const [
                            DropdownMenuItem(
                              value: 'pm_pix',
                              child: Text('Pix / Transferência (Padrão)'),
                            ),
                          ],
                    onChanged: (val) {
                      setState(() {
                        _selectedPaymentMethodId = val;
                        final pm = state.paymentMethods.where((p) => p.id == val).firstOrNull;
                        if (pm?.ownerMemberId != null) {
                          _selectedPaidByMemberId = pm!.ownerMemberId;
                        }
                      });
                    },
                  );
                },
              ),
              const SizedBox(height: 16),

              // Comprovante ou Cupom Fiscal (Fase 4.1)
              _buildReceiptAttachmentSection(theme),

              const SizedBox(height: 24),

              // Botão de Lançar / Salvar
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 2,
                  ),
                  onPressed: _submit,
                  child: Text(
                    widget.expenseToEdit != null
                        ? 'Salvar Alterações'
                        : (_isRecurring ? 'Salvar Despesa Recorrente' : 'Lançar Gasto da Casa'),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              if (widget.expenseToEdit != null) ...[
                const SizedBox(height: 12),
                SizedBox(
                  height: 48,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.debtRed,
                      side: BorderSide(color: AppColors.debtRed.withValues(alpha: 0.5)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    icon: const Icon(Icons.delete_outline_rounded, size: 20),
                    label: const Text(
                      'Excluir Esta Despesa',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                    onPressed: _confirmAndDelete,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildItemizedBalanceBanner(ThemeData theme) {
    final itemsSumCents = _draftItems.fold<int>(0, (acc, i) => acc + i.cents);
    final diffCents = _cents - itemsSumCents;

    if (diffCents == 0 && itemsSumCents > 0) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.creditGreen.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.creditGreen.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: AppColors.creditGreen, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Total conferido: ${Money(itemsSumCents).format()} de ${Money(_cents).format()} (100% batendo ✅)',
                style: const TextStyle(
                  color: AppColors.creditGreen,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (diffCents > 0) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.folegoWarning.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.folegoWarning.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.info_outline_rounded, color: AppColors.folegoWarning, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Soma: ${Money(itemsSumCents).format()} • Faltam ${Money(diffCents).format()} para fechar os ${Money(_cents).format()}',
                    style: const TextStyle(
                      color: AppColors.folegoWarning,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            if (_draftItems.isNotEmpty) ...[
              const SizedBox(height: 6),
              InkWell(
                onTap: () {
                  setState(() {
                    _draftItems.last.cents += diffCents;
                  });
                },
                child: Text(
                  '+ Ajustar restante (${Money(diffCents).format()}) no último sub-item',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: Colors.red, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Soma: ${Money(itemsSumCents).format()} • Ultrapassou em ${Money(-diffCents).format()} o boleto (${Money(_cents).format()})',
              style: const TextStyle(
                color: Colors.red,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDraftItemCard(
    ThemeData theme,
    FinanceState state,
    int index,
    _DraftExpenseItem item,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Sub-item #${index + 1}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.red),
                onPressed: () {
                  setState(() {
                    item.dispose();
                    _draftItems.removeAt(index);
                  });
                },
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: item.titleController,
                  decoration: InputDecoration(
                    labelText: 'Nome do sub-item',
                    hintText: 'Ex: Água, Gás, Taxa',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: MoneyInputField(
                  label: 'Valor',
                  initialValue: Money(item.cents),
                  primaryColor: AppColors.primary,
                  onChanged: (money) {
                    setState(() {
                      item.cents = money.cents;
                    });
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('Responsável: ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
              const SizedBox(width: 6),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: theme.dividerColor),
                  ),
                  child: DropdownButton<String?>(
                    value: item.responsibleMemberId,
                    isDense: true,
                    isExpanded: true,
                    underline: const SizedBox(),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Rateio Geral da Casa', style: TextStyle(fontSize: 12)),
                      ),
                      ...state.members.map((m) {
                        return DropdownMenuItem<String?>(
                          value: m.id,
                          child: Text('100% ${m.name}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                        );
                      }),
                    ],
                    onChanged: (val) {
                      setState(() {
                        item.responsibleMemberId = val;
                      });
                    },
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDateAndStatusCard(ThemeData theme) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final selectedDay = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
    final isPast = selectedDay.isBefore(today);
    final isRetroactivePending = isPast && _expenseStatus == ExpenseStatus.pending;
    final daysDiff = today.difference(selectedDay).inDays;

    String dateContextText;
    if (selectedDay == today) {
      dateContextText = 'Hoje';
    } else if (isPast) {
      dateContextText = daysDiff == 1 ? 'Ontem' : 'Há $daysDiff dias';
    } else {
      final futureDays = selectedDay.difference(today).inDays;
      dateContextText = futureDays == 1 ? 'Amanhã' : 'Em $futureDays dias';
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isRetroactivePending
            ? AppColors.debtRed.withValues(alpha: 0.05)
            : theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isRetroactivePending
              ? AppColors.debtRed.withValues(alpha: 0.4)
              : theme.dividerColor,
          width: isRetroactivePending ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.calendar_month_rounded,
                    size: 18,
                    color: isRetroactivePending ? AppColors.debtRed : AppColors.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _expenseStatus == ExpenseStatus.pending
                        ? 'Data de Vencimento'
                        : 'Data do Pagamento',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ],
              ),
              InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _selectedDate,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2035),
                  );
                  if (picked != null) {
                    setState(() => _selectedDate = picked);
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Text(
                        '${DateFormat('dd/MM/yyyy').format(_selectedDate)} ($dateContextText)',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.edit_calendar_rounded, size: 14, color: AppColors.primary),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Situação no Ciclo Atual
          const Text(
            'Situação no Ciclo Atual',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ChoiceChip(
                  avatar: const Icon(Icons.check_circle_outline, size: 16),
                  label: const Center(child: Text('Já Paga')),
                  selected: _expenseStatus == ExpenseStatus.paid,
                  selectedColor: AppColors.creditGreen.withValues(alpha: 0.15),
                  onSelected: (selected) {
                    if (selected) setState(() => _expenseStatus = ExpenseStatus.paid);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ChoiceChip(
                  avatar: const Icon(Icons.schedule_rounded, size: 16),
                  label: const Center(child: Text('A Vencer')),
                  selected: _expenseStatus == ExpenseStatus.pending,
                  selectedColor: AppColors.folegoWarning.withValues(alpha: 0.2),
                  onSelected: (selected) {
                    if (selected) setState(() => _expenseStatus = ExpenseStatus.pending);
                  },
                ),
              ),
            ],
          ),

          if (isRetroactivePending) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.debtRed.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.debtRed.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, size: 18, color: AppColors.debtRed),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '⚠️ Conta Vencida / Em Atraso (venceu há $daysDiff dias). Ficará como compromisso pendente no Fôlego da casa até ser paga.',
                      style: const TextStyle(
                        color: AppColors.debtRed,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }



  Widget _buildReceiptAttachmentSection(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _attachedReceiptName != null
              ? AppColors.creditGreen.withValues(alpha: 0.5)
              : Colors.grey.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: (_attachedReceiptName != null ? AppColors.creditGreen : AppColors.primary)
                  .withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              _attachedReceiptName != null ? Icons.receipt_long_rounded : Icons.camera_alt_outlined,
              color: _attachedReceiptName != null ? AppColors.creditGreen : AppColors.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _attachedReceiptName != null ? 'Cupom Anexado' : 'Comprovante / Cupom Fiscal',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                Text(
                  _attachedReceiptName ?? 'Anexe a foto da nota ou comprovante de pagamento',
                  style: TextStyle(
                    fontSize: 11,
                    color: _attachedReceiptName != null ? AppColors.creditGreen : Colors.grey,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (_attachedReceiptName != null)
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 18, color: Colors.grey),
              tooltip: 'Remover cupom',
              onPressed: () {
                setState(() => _attachedReceiptName = null);
              },
            )
          else
            TextButton.icon(
              onPressed: () {
                setState(() {
                  _attachedReceiptName = 'cupom_fiscal_${DateTime.now().millisecondsSinceEpoch}.jpg';
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Foto do cupom/comprovante vinculada com sucesso! 📸'),
                    backgroundColor: AppColors.creditGreen,
                  ),
                );
              },
              icon: const Icon(Icons.upload_file_rounded, size: 16),
              label: const Text('Anexar', style: TextStyle(fontSize: 12)),
            ),
        ],
      ),
    );
  }
}
