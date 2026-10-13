import '../../../../core/errors/failures.dart';
import '../../domain/entities/card_invoice.dart';
import '../../domain/entities/house_member.dart';
import '../../domain/entities/category.dart';
import '../../domain/entities/payment_method.dart';
import '../../domain/entities/house_expense.dart';
import '../../domain/entities/house_expense_item.dart';
import '../../domain/entities/contribution.dart';
import '../../domain/entities/split_rule.dart';
import '../../domain/entities/financial_cycle_summary.dart';
import '../../domain/entities/savings_vault.dart';
import '../../domain/entities/audit_entry.dart';
import '../../../../core/domain/enums/recurrence.dart';
import '../../../../core/domain/value_objects/money.dart';
import '../../../../core/domain/value_objects/financial_cycle.dart';
import '../../domain/services/credit_card_invoice_calculator.dart';
import '../../domain/services/cycle_expense_filter.dart';
import 'finance_datasource.dart';

class MockFinanceDataSource implements FinanceDataSource {
  final List<AuditEntry> _auditLogs = [];
  final List<HouseMember> _members = [
    const HouseMember(
      id: 'member_carlos',
      name: 'Carlos',
      role: 'owner',
      defaultSplitPercent: 60.0,
      pixKey: 'carlos@omnilar.com',
    ),
    const HouseMember(
      id: 'member_marina',
      name: 'Marina',
      role: 'admin',
      defaultSplitPercent: 40.0,
      pixKey: 'marina@omnilar.com',
    ),
  ];

  final List<ExpenseCategory> _categories = [
    const ExpenseCategory(
      id: 'cat_mercado',
      name: 'Supermercado',
      icon: 'shopping_cart_outlined',
      colorHex: '#10B981',
    ),
    const ExpenseCategory(
      id: 'cat_moradia',
      name: 'Moradia / Aluguel',
      icon: 'home_outlined',
      colorHex: '#3B82F6',
    ),
    const ExpenseCategory(
      id: 'cat_contas',
      name: 'Contas (Luz, Água, Net)',
      icon: 'bolt_outlined',
      colorHex: '#F59E0B',
    ),
    const ExpenseCategory(
      id: 'cat_carro',
      name: 'Carro (Combustível)',
      icon: 'directions_car_outlined',
      colorHex: '#EC4899',
      ownerMemberId: 'member_carlos', // Categoria com Dono: 100% Carlos
    ),
    const ExpenseCategory(
      id: 'cat_lazer',
      name: 'Lazer e Restaurantes',
      icon: 'restaurant_outlined',
      colorHex: '#8B5CF6',
    ),
  ];

  final List<PaymentMethod> _paymentMethods = [
    const PaymentMethod(
      id: 'pm_caixa',
      name: 'Conta Conjunta (Caixa da Casa)',
      type: PaymentMethodType.account,
    ),
    const PaymentMethod(
      id: 'pm_vr_marina',
      name: 'VR Marina (Vale Refeição)',
      type: PaymentMethodType.vr,
      ownerMemberId: 'member_marina',
    ),
    const PaymentMethod(
      id: 'pm_card_carlos',
      name: 'Nubank Carlos',
      type: PaymentMethodType.card,
      ownerMemberId: 'member_carlos',
      closingDay: 28,
      dueDay: 5,
    ),
    const PaymentMethod(
      id: 'pm_card_marina',
      name: 'Itaú Marina',
      type: PaymentMethodType.card,
      ownerMemberId: 'member_marina',
      closingDay: 20,
      dueDay: 27,
    ),
  ];

  final List<Contribution> _contributions = [];
  final List<HouseExpense> _expenses = [];

  MockFinanceDataSource() {
    final now = DateTime.now();
    final currentCycle = FinancialCycle.fromDate(
      date: now,
      cycleStartDay: 5,
    );
    final cycleStart = currentCycle.startDate;

    // Aportes de exemplo do ciclo atual (no início do ciclo)
    _contributions.addAll([
      Contribution(
        id: 'contrib_1',
        memberId: 'member_carlos',
        amount: const Money(300000), // R$ 3.000,00
        date: cycleStart,
      ),
      Contribution(
        id: 'contrib_2',
        memberId: 'member_marina',
        amount: const Money(200000), // R$ 2.000,00
        date: cycleStart,
      ),
    ]);

    // Despesas de exemplo
    _expenses.addAll([
      HouseExpense(
        id: 'exp_1',
        title: 'Aluguel do Apartamento',
        amount: const Money(220000), // R$ 2.200,00
        date: cycleStart.add(const Duration(days: 1)),
        categoryId: 'cat_moradia',
        paidByMemberId: 'member_carlos',
        paymentMethodId: 'pm_caixa',
        splitRule: const SplitRule.percentage({'member_carlos': 60.0, 'member_marina': 40.0}),
        status: ExpenseStatus.paid,
        isRecurring: true,
        isVariable: false,
        dueDay: 6,
      ),
      HouseExpense(
        id: 'exp_2',
        title: 'Compras Pão de Açúcar',
        amount: const Money(48560), // R$ 485,60
        date: cycleStart.add(const Duration(days: 1)),
        categoryId: 'cat_mercado',
        paidByMemberId: 'member_marina',
        paymentMethodId: 'pm_vr_marina',
        splitRule: const SplitRule.percentage({'member_carlos': 60.0, 'member_marina': 40.0}),
        status: ExpenseStatus.paid,
      ),
      HouseExpense(
        id: 'exp_3',
        title: 'Abastecimento Posto Shell',
        amount: const Money(18000), // R$ 180,00
        date: cycleStart.add(const Duration(days: 1)),
        dueDate: cycleStart.add(const Duration(days: 1)),
        categoryId: 'cat_carro', // Dono 100% Carlos
        paidByMemberId: 'member_carlos',
        paymentMethodId: 'pm_card_carlos',
        splitRule: const SplitRule.singleResponsible('member_carlos'),
        status: ExpenseStatus.paid,
      ),
      // Contas recorrentes futuras / provisionadas
      HouseExpense(
        id: 'exp_4',
        title: 'Conta de Luz (Enel)',
        amount: const Money(21000), // R$ 210,00 estimado
        date: cycleStart.add(const Duration(days: 15)),
        dueDate: cycleStart.add(const Duration(days: 15)),
        categoryId: 'cat_contas',
        paidByMemberId: 'member_carlos',
        paymentMethodId: 'pm_caixa',
        splitRule: const SplitRule.percentage({'member_carlos': 60.0, 'member_marina': 40.0}),
        status: ExpenseStatus.pending,
        isRecurring: true,
        isVariable: true,
        dueDay: 20,
      ),
      HouseExpense(
        id: 'exp_5',
        title: 'Internet Fibra',
        amount: const Money(12000), // R$ 120,00 fixo
        date: cycleStart.add(const Duration(days: 20)),
        dueDate: cycleStart.add(const Duration(days: 20)),
        categoryId: 'cat_contas',
        paidByMemberId: 'member_marina',
        paymentMethodId: 'pm_caixa',
        splitRule: const SplitRule.percentage({'member_carlos': 60.0, 'member_marina': 40.0}),
        status: ExpenseStatus.pending,
        isRecurring: true,
        isVariable: false,
        dueDay: 25,
      ),
      HouseExpense(
        id: 'exp_6',
        title: 'Netflix Assinatura',
        amount: const Money(5590), // R$ 55,90 fixo
        date: cycleStart.add(const Duration(days: 5)),
        dueDate: cycleStart.add(const Duration(days: 5)),
        categoryId: 'cat_lazer',
        paidByMemberId: 'member_marina',
        paymentMethodId: 'pm_card_marina',
        splitRule: const SplitRule.percentage({'member_carlos': 60.0, 'member_marina': 40.0}),
        status: ExpenseStatus.paid,
        isRecurring: true,
        isVariable: false,
        dueDay: 10,
      ),
      HouseExpense(
        id: 'exp_7',
        title: 'Condomínio Edifício Solar',
        amount: const Money(85000), // R$ 850,00 total
        date: cycleStart.add(const Duration(days: 5)),
        dueDate: cycleStart.add(const Duration(days: 5)),
        categoryId: 'cat_moradia',
        paidByMemberId: 'member_carlos',
        paymentMethodId: 'pm_caixa',
        splitRule: const SplitRule.percentage({'member_carlos': 60.0, 'member_marina': 40.0}),
        status: ExpenseStatus.paid,
        isRecurring: true,
        isVariable: true,
        dueDay: 10,
        items: const [
          HouseExpenseItem(
            id: 'item_1',
            expenseId: 'exp_7',
            title: 'Taxa Condomínio Ordinária',
            amount: Money(50000), // R$ 500,00
            categoryId: 'cat_moradia',
          ),
          HouseExpenseItem(
            id: 'item_2',
            expenseId: 'exp_7',
            title: 'Consumo de Água',
            amount: Money(12000), // R$ 120,00
            categoryId: 'cat_contas',
          ),
          HouseExpenseItem(
            id: 'item_3',
            expenseId: 'exp_7',
            title: 'Gás Encanado',
            amount: Money(8000), // R$ 80,00
            categoryId: 'cat_contas',
          ),
          HouseExpenseItem(
            id: 'item_4',
            expenseId: 'exp_7',
            title: 'Fundo de Reserva & Obras',
            amount: Money(15000), // R$ 150,00
            categoryId: 'cat_moradia',
            responsibleMemberId: 'member_carlos', // 100% Carlos (Proprietário)
            splitRule: SplitRule.singleResponsible('member_carlos'),
          ),
        ],
      ),
      // Despesas de Projetos Compartilhados (NÃO entram no Caixa da Casa nem no fechamento do ciclo)
      HouseExpense(
        id: 'exp_proj_1',
        title: 'Casa de Praia (Airbnb)',
        amount: const Money(180000), // R$ 1.800,00
        date: now.subtract(const Duration(days: 40)), // Pago em ciclo anterior (reserva antecipada)
        categoryId: 'cat_lazer',
        paidByMemberId: 'member_carlos',
        paymentMethodId: 'pm_card_carlos',
        splitRule: const SplitRule.percentage(null), // Rateio padrão do projeto
        status: ExpenseStatus.paid,
        projectId: 'proj_trip_praia',
      ),
      HouseExpense(
        id: 'exp_proj_2',
        title: 'Combustível Ida e Volta',
        amount: const Money(42000), // R$ 420,00
        date: now,
        categoryId: 'cat_lazer',
        paidByMemberId: 'member_marina',
        paymentMethodId: 'pm_card_marina',
        splitRule: const SplitRule.percentage(null),
        status: ExpenseStatus.paid,
        projectId: 'proj_trip_praia',
      ),
      HouseExpense(
        id: 'exp_proj_3',
        title: 'Bancada de Granito',
        amount: const Money(320000), // R$ 3.200,00
        date: now.subtract(const Duration(days: 10)),
        categoryId: 'cat_moradia',
        paidByMemberId: 'member_marina',
        paymentMethodId: 'pm_card_marina',
        splitRule: const SplitRule.percentage(null),
        status: ExpenseStatus.paid,
        projectId: 'proj_reforma_cozinha',
      ),
    ]);
  }

  @override
  Future<List<HouseMember>> getMembers() async => List.unmodifiable(_members);
  @override
  Future<List<ExpenseCategory>> getCategories() async => List.unmodifiable(_categories);
  @override
  Future<List<PaymentMethod>> getPaymentMethods() async => List.unmodifiable(_paymentMethods);

  @override
  Future<List<HouseExpense>> getExpensesForCycle(FinancialCycle cycle) async {
    // Como no banco: ciclo atual ou futuro ganha as contas recorrentes que faltam
    if (!cycle.endDate.isBefore(DateTime.now())) _generateRecurringExpenses(cycle.endDate);
    return _expenses.where((e) {
      final isCard = _paymentMethods.any((pm) => pm.id == e.paymentMethodId && pm.type == PaymentMethodType.card);
      return expenseBelongsToCycle(e, cycle, isCardPayment: isCard);
    }).toList()
      ..sort((a, b) => b.effectiveDueDate.compareTo(a.effectiveDueDate));
  }

  /// Último vencimento já gerado por série: uma ocorrência excluída com "só
  /// esta" não é recriada.
  final Map<String, DateTime> _lastGeneratedDue = {};

  /// Cria a ocorrência de cada mês das séries ativas até [until], no máximo
  /// três meses à frente. A série é a primeira despesa (matriz) mais as
  /// ocorrências ligadas a ela por `recurringSeriesId`.
  void _generateRecurringExpenses(DateTime until) {
    final now = DateTime.now();
    final cap = DateTime(now.year, now.month + 3, now.day);
    final limit = until.isAfter(cap) ? cap : until;

    final seriesHeads = _expenses
        .where((e) =>
            e.isRecurring && e.isActive && e.recurringSeriesId == null && e.projectId == null)
        .toList();
    for (final head in seriesHeads) {
      final occurrences =
          _expenses.where((e) => e.id == head.id || e.recurringSeriesId == head.id).toList();
      var lastDue = occurrences
          .map((e) => e.effectiveDueDate)
          .reduce((a, b) => a.isAfter(b) ? a : b);
      final generated = _lastGeneratedDue[head.id];
      if (generated != null && generated.isAfter(lastDue)) lastDue = generated;

      for (var guard = 0; guard < 12; guard++) {
        // Modelo: a ocorrência mais recente que ainda existe (inclusive o dia de vencimento)
        final template = _expenses
            .where((e) => e.id == head.id || e.recurringSeriesId == head.id)
            .reduce((a, b) => a.effectiveDueDate.isAfter(b.effectiveDueDate) ? a : b);
        final dueDay = template.dueDay ?? head.dueDay ?? head.effectiveDueDate.day;
        final lastDayOfNextMonth = DateTime(lastDue.year, lastDue.month + 2, 0).day;
        final nextDue = DateTime(
          lastDue.year,
          lastDue.month + 1,
          dueDay > lastDayOfNextMonth ? lastDayOfNextMonth : dueDay,
        );
        if (nextDue.isAfter(limit)) break;

        final newId = 'exp_rec_${head.id}_${nextDue.year}_${nextDue.month}';
        _expenses.add(
          HouseExpense(
            id: newId,
            title: template.title,
            amount: template.amount,
            date: nextDue,
            dueDate: nextDue,
            categoryId: template.categoryId,
            paidByMemberId: template.paidByMemberId,
            paymentMethodId: template.paymentMethodId,
            splitRule: template.splitRule,
            status: ExpenseStatus.pending,
            isRecurring: true,
            isVariable: template.isVariable,
            dueDay: dueDay,
            paidOutOfPocket: template.paidOutOfPocket,
            notes: template.notes,
            items: [
              for (final item in template.items)
                HouseExpenseItem(
                  id: '${newId}_${item.id}',
                  expenseId: newId,
                  title: item.title,
                  amount: item.amount,
                  categoryId: item.categoryId,
                  responsibleMemberId: item.responsibleMemberId,
                  splitRule: item.splitRule,
                ),
            ],
            recurringSeriesId: head.id,
          ),
        );
        _lastGeneratedDue[head.id] = nextDue;
        lastDue = nextDue;
      }
    }
  }

  /// Todas as despesas do projeto, de qualquer ciclo (viagens e obras atravessam meses).
  @override
  Future<List<HouseExpense>> getExpensesForProject(String projectId) async {
    return _expenses.where((e) => e.projectId == projectId).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  @override
  Future<Money> getOpeningBalance(FinancialCycle cycle) async => const Money.zero();

  @override
  Future<List<Contribution>> getContributionsForCycle(FinancialCycle cycle) async {
    return _contributions.where((c) => cycle.contains(c.date)).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  @override
  Future<FinancialCycleSummary> getCycleSummary(FinancialCycle cycle) async {
    final cycleExpenses = await getExpensesForCycle(cycle);
    final cycleContributions = await getContributionsForCycle(cycle);

    Money totalContrib = const Money.zero();
    final memberContribs = <String, Money>{};
    for (final c in cycleContributions) {
      totalContrib += c.amount;
      memberContribs[c.memberId] = (memberContribs[c.memberId] ?? const Money.zero()) + c.amount;
    }

    Money totalPaid = const Money.zero();
    Money committedFuture = const Money.zero();
    final memberPaid = <String, Money>{};

    for (final exp in cycleExpenses) {
      if (exp.isPaid) {
        totalPaid += exp.amount;
        memberPaid[exp.paidByMemberId] = (memberPaid[exp.paidByMemberId] ?? const Money.zero()) + exp.amount;
      } else {
        committedFuture += exp.amount;
      }
    }

    // Fôlego = Total de Aportes - (Despesas Pagas + Contas a vencer do ciclo)
    final folego = totalContrib - (totalPaid + committedFuture);

    return FinancialCycleSummary(
      cycle: cycle,
      totalContributions: totalContrib,
      totalExpensesPaid: totalPaid,
      committedFutureExpenses: committedFuture,
      folego: folego,
      memberContributions: memberContribs,
      memberExpensesPaid: memberPaid,
    );
  }

  @override
  Future<void> addExpense(HouseExpense expense) async {
    HouseExpense toAdd = expense;
    if (toAdd.dueDate == null && toAdd.paymentMethodId.isNotEmpty) {
      final pm = _paymentMethods.where((p) => p.id == toAdd.paymentMethodId).firstOrNull;
      if (pm != null && pm.type == PaymentMethodType.card && pm.closingDay != null && pm.dueDay != null) {
        toAdd = toAdd.copyWith(
          dueDate: CreditCardInvoiceCalculator.calculateInvoiceDueDate(
            purchaseDate: toAdd.date,
            closingDay: pm.closingDay!,
            dueDay: pm.dueDay!,
          ),
        );
      }
    }
    _expenses.insert(0, toAdd);
    _auditLogs.add(AuditEntry(
      id: 'aud_${DateTime.now().millisecondsSinceEpoch}_${expense.id}',
      actorId: expense.paidByMemberId,
      actorName: _members.firstWhere((m) => m.id == expense.paidByMemberId, orElse: () => _members.first).name,
      entityType: 'house_expenses',
      entityId: expense.id,
      action: 'create',
      diff: {'title': expense.title, 'amount_cents': expense.amount.cents},
      createdAt: DateTime.now(),
    ));
  }

  @override
  Future<void> updateExpense(
    HouseExpense expense, {
    RecurrenceScope scope = RecurrenceScope.thisInstanceOnly,
  }) async {
    final index = _expenses.indexWhere((e) => e.id == expense.id);
    if (index == -1) {
      _expenses.insert(0, expense);
      return;
    }
    final current = _expenses[index];
    _auditLogs.add(AuditEntry(
      id: 'aud_${DateTime.now().millisecondsSinceEpoch}_${expense.id}',
      actorId: expense.paidByMemberId,
      actorName: _members.firstWhere((m) => m.id == expense.paidByMemberId, orElse: () => _members.first).name,
      entityType: 'house_expenses',
      entityId: expense.id,
      action: 'update',
      diff: {'title': expense.title, 'amount_cents': expense.amount.cents},
      createdAt: DateTime.now(),
    ));

    switch (scope) {
      case RecurrenceScope.thisInstanceOnly:
        _expenses[index] = expense.isPending ? expense.copyWith(clearPaidAt: true) : expense;
        break;

      case RecurrenceScope.thisAndFuture:
        final seriesId = current.recurringSeriesId ?? (current.isRecurring ? current.id : null);
        if (seriesId != null) {
          // Como no banco: "esta e as próximas" vale a partir do vencimento
          final fromDate = current.dueDate ?? current.date;
          for (int i = 0; i < _expenses.length; i++) {
            final e = _expenses[i];
            final matches = e.recurringSeriesId == seriesId || e.id == seriesId;
            if (matches && !(e.dueDate ?? e.date).isBefore(fromDate)) {
              _expenses[i] = e.copyWith(
                title: expense.title,
                amount: expense.amount,
                categoryId: expense.categoryId,
                paymentMethodId: expense.paymentMethodId,
                splitRule: expense.splitRule,
                isVariable: expense.isVariable,
                dueDay: expense.dueDay,
              );
            }
          }
        } else {
          _expenses[index] = expense.isPending ? expense.copyWith(clearPaidAt: true) : expense;
        }
        break;

      case RecurrenceScope.allInstances:
        final seriesId = current.recurringSeriesId ?? (current.isRecurring ? current.id : null);
        if (seriesId != null) {
          for (int i = 0; i < _expenses.length; i++) {
            final e = _expenses[i];
            final matches = e.recurringSeriesId == seriesId || e.id == seriesId;
            if (matches) {
              _expenses[i] = e.copyWith(
                title: expense.title,
                amount: expense.amount,
                categoryId: expense.categoryId,
                paymentMethodId: expense.paymentMethodId,
                splitRule: expense.splitRule,
                isVariable: expense.isVariable,
                dueDay: expense.dueDay,
              );
            }
          }
        } else {
          _expenses[index] = expense.isPending ? expense.copyWith(clearPaidAt: true) : expense;
        }
        break;
    }
  }

  @override
  Future<void> deleteExpense(
    String expenseId, {
    RecurrenceScope scope = RecurrenceScope.thisInstanceOnly,
  }) async {
    final index = _expenses.indexWhere((e) => e.id == expenseId);
    if (index == -1) return;
    final current = _expenses[index];
    _auditLogs.add(AuditEntry(
      id: 'aud_${DateTime.now().millisecondsSinceEpoch}_$expenseId',
      actorId: current.paidByMemberId,
      actorName: _members.firstWhere((m) => m.id == current.paidByMemberId, orElse: () => _members.first).name,
      entityType: 'house_expenses',
      entityId: expenseId,
      action: 'soft_delete',
      diff: {'title': current.title, 'amount_cents': current.amount.cents},
      createdAt: DateTime.now(),
    ));

    switch (scope) {
      case RecurrenceScope.thisInstanceOnly:
        _expenses.removeAt(index);
        break;

      case RecurrenceScope.thisAndFuture:
        final seriesId = current.recurringSeriesId ?? (current.isRecurring ? current.id : null);
        if (seriesId != null) {
          // Como no banco: "esta e as próximas" vale a partir do vencimento
          final fromDate = current.dueDate ?? current.date;
          for (int i = 0; i < _expenses.length; i++) {
            if (_expenses[i].id == seriesId) {
              _expenses[i] = _expenses[i].copyWith(isActive: false);
            }
          }
          _expenses.removeWhere((e) {
            final matches = e.recurringSeriesId == seriesId || e.id == seriesId;
            return matches && !(e.dueDate ?? e.date).isBefore(fromDate);
          });
        } else {
          _expenses.removeAt(index);
        }
        break;

      case RecurrenceScope.allInstances:
        final seriesId = current.recurringSeriesId ?? (current.isRecurring ? current.id : null);
        if (seriesId != null) {
          _expenses.removeWhere((e) => e.recurringSeriesId == seriesId || e.id == seriesId);
        } else {
          _expenses.removeAt(index);
        }
        break;
    }
  }

  @override
  Future<List<HouseExpense>> getRecurringExpenses() async {
    // Série ativa: vale a primeira despesa dela (matriz); sem matriz, a própria ocorrência
    final headActive = {
      for (final e in _expenses)
        if (e.isRecurring && e.recurringSeriesId == null) e.id: e.isActive,
    };
    return _expenses
        .where((e) => e.isRecurring && (headActive[e.recurringSeriesId ?? e.id] ?? e.isActive))
        .toList();
  }

  @override
  Future<void> addContribution(Contribution contribution) async {
    _contributions.insert(0, contribution);
  }

  @override
  Future<void> addCategory(ExpenseCategory category) async {
    _categories.add(category);
  }

  final List<SavingsVault> _savingsVaults = [
    SavingsVault(
      id: 'vault_reserva',
      name: 'Reserva de Emergência da Casa',
      targetAmount: const Money(600000), // R$ 6.000,00
      currentBalance: const Money(340000), // R$ 3.400,00 (56%)
      icon: 'shield',
      colorHex: '#10B981',
      createdAt: DateTime.now().subtract(const Duration(days: 90)),
    ),
    SavingsVault(
      id: 'vault_viagem',
      name: 'Viagem de Férias do Casal',
      targetAmount: const Money(300000), // R$ 3.000,00
      currentBalance: const Money(180000), // R$ 1.800,00 (60%)
      icon: 'flight',
      colorHex: '#3B82F6',
      createdAt: DateTime.now().subtract(const Duration(days: 45)),
    ),
    SavingsVault(
      id: 'vault_reforma',
      name: 'Reforma e Móveis Novos',
      targetAmount: const Money(200000), // R$ 2.000,00
      currentBalance: const Money(85000), // R$ 850,00 (42%)
      icon: 'home',
      colorHex: '#8B5CF6',
      createdAt: DateTime.now().subtract(const Duration(days: 30)),
    ),
  ];

  final List<SavingsTransaction> _savingsTransactions = [];

  @override
  Future<void> addPaymentMethod(PaymentMethod paymentMethod) async {
    _paymentMethods.add(paymentMethod);
  }

  @override
  Future<void> updatePaymentMethod(PaymentMethod paymentMethod) async {
    final index = _paymentMethods.indexWhere((p) => p.id == paymentMethod.id);
    if (index != -1) {
      _paymentMethods[index] = paymentMethod;
    }
  }

  @override
  Future<void> deletePaymentMethod(String paymentMethodId) async {
    _paymentMethods.removeWhere((p) => p.id == paymentMethodId);
  }

  String _splitModel = 'percentage';

  @override
  Future<String> getHouseSplitModel() async => _splitModel;

  @override
  Future<void> updateHouseSplitModel({
    required String splitModel,
    required Map<String, double> percentages,
    required Map<String, int> fixedAmountsCents,
  }) async {
    _splitModel = splitModel;
    for (int i = 0; i < _members.length; i++) {
      final m = _members[i];
      final newPercent = percentages[m.id] ?? m.defaultSplitPercent;
      final newFixed = fixedAmountsCents[m.id] ?? m.defaultFixedAmountCents;
      _members[i] = m.copyWith(
        defaultSplitPercent: newPercent,
        defaultFixedAmountCents: newFixed,
      );
    }
  }

  // --- Caixinhas & Metas da Casa (Dinheiro Blindado) ---
  @override
  Future<List<SavingsVault>> getSavingsVaults() async {
    return List.unmodifiable(_savingsVaults);
  }

  @override
  Future<List<SavingsTransaction>> getVaultTransactions(String vaultId) async {
    return _savingsTransactions.where((t) => t.vaultId == vaultId).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  @override
  Future<void> createSavingsVault(SavingsVault vault) async {
    _savingsVaults.add(vault);
  }

  @override
  Future<void> depositToVault({
    required String vaultId,
    required String memberId,
    required Money amount,
    required String description,
  }) async {
    final index = _savingsVaults.indexWhere((v) => v.id == vaultId);
    if (index != -1) {
      final current = _savingsVaults[index];
      _savingsVaults[index] = current.copyWith(
        currentBalance: current.currentBalance + amount,
      );
      _savingsTransactions.add(SavingsTransaction(
        id: 'tx_${DateTime.now().millisecondsSinceEpoch}',
        vaultId: vaultId,
        memberId: memberId,
        amount: amount,
        type: 'deposit',
        description: description,
        date: DateTime.now(),
      ));
    }
  }

  @override
  Future<void> withdrawFromVault({
    required String vaultId,
    required String memberId,
    required Money amount,
    required String description,
  }) async {
    final index = _savingsVaults.indexWhere((v) => v.id == vaultId);
    if (index != -1) {
      final current = _savingsVaults[index];
      // Como no banco: resgate acima do saldo é recusado, não zera a caixinha
      if (amount.cents > current.currentBalance.cents) {
        throw const ServerFailure('Saldo insuficiente na caixinha.');
      }
      _savingsVaults[index] = current.copyWith(
        currentBalance: current.currentBalance - amount,
      );
      _savingsTransactions.add(SavingsTransaction(
        id: 'tx_${DateTime.now().millisecondsSinceEpoch}',
        vaultId: vaultId,
        memberId: memberId,
        amount: amount,
        type: 'withdraw',
        description: description,
        date: DateTime.now(),
      ));
    }
  }

  @override
  Future<List<AuditEntry>> getAuditLog({String? entityId, int limit = 50}) async {
    var logs = _auditLogs;
    if (entityId != null) {
      logs = logs.where((l) => l.entityId == entityId).toList();
    }
    return logs.reversed.take(limit).toList();
  }

  @override
  Future<List<CardInvoice>> getOpenCardInvoices(String paymentMethodId) async =>
      CardInvoice.groupOpenInvoices(paymentMethodId, _expenses);

  @override
  Future<void> payCardInvoice({
    required String paymentMethodId,
    required DateTime invoiceDueDate,
    required DateTime paidAt,
  }) async {
    bool sameDay(DateTime a, DateTime b) =>
        a.year == b.year && a.month == b.month && a.day == b.day;

    for (int i = 0; i < _expenses.length; i++) {
      final e = _expenses[i];
      if (e.paymentMethodId == paymentMethodId &&
          e.dueDate != null &&
          e.paidAt == null &&
          sameDay(e.dueDate!, invoiceDueDate)) {
        _expenses[i] = e.copyWith(paidAt: paidAt);
      }
    }
  }

  @override
  Future<List<CardInvoice>> getPaidCardInvoices(String paymentMethodId) async =>
      CardInvoice.groupPaidInvoices(paymentMethodId, _expenses);

  @override
  Future<void> undoCardInvoicePayment({
    required String paymentMethodId,
    required DateTime invoiceDueDate,
  }) async {
    for (int i = 0; i < _expenses.length; i++) {
      final e = _expenses[i];
      final due = e.dueDate;
      if (e.paymentMethodId == paymentMethodId &&
          e.paidAt != null &&
          due != null &&
          due.year == invoiceDueDate.year &&
          due.month == invoiceDueDate.month &&
          due.day == invoiceDueDate.day) {
        _expenses[i] = e.copyWith(clearPaidAt: true);
      }
    }
  }
}
