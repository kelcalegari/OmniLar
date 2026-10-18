import '../../../../core/errors/failures.dart';
import '../../domain/entities/card_invoice.dart';
import '../../domain/entities/house_initial_balance.dart';
import '../../domain/entities/house_settings.dart';
import '../../domain/entities/house_member.dart';
import '../../domain/entities/category.dart';
import '../../domain/entities/payment_method.dart';
import '../../domain/entities/house_expense.dart';
import '../../domain/entities/house_expense_item.dart';
import '../../domain/entities/contribution.dart';
import '../../domain/entities/split_rule.dart';
import '../../domain/entities/financial_cycle_summary.dart';
import '../../domain/entities/opening_inflows.dart';
import '../../domain/entities/savings_vault.dart';
import '../../domain/entities/third_party_receipt.dart';
import '../../domain/entities/house_inflow.dart';
import '../../domain/entities/audit_entry.dart';
import '../../../../core/domain/enums/recurrence.dart';
import '../../../../core/domain/value_objects/money.dart';
import '../../../../core/domain/value_objects/financial_cycle.dart';
import '../../domain/services/credit_card_invoice_calculator.dart';
import '../../domain/services/cycle_expense_filter.dart';
import 'finance_datasource.dart';

class MockFinanceDataSource implements FinanceDataSource {
  /// Empréstimos que o Caixa liberou no ciclo (vêm do P2P de demonstração).
  Future<Money> Function(FinancialCycle cycle)? houseLoansFundedIn;

  /// Há fechamento antes de [cycle]? No modo demo os fechamentos ficam com o
  /// fechamento de demonstração; sem resposta, conta como primeiro ciclo.
  Future<bool> Function(FinancialCycle cycle)? hasSettlementBefore;

  /// O dia cai num ciclo fechado? Como no banco (0096), entrada de fora nesse
  /// dia é recusada. Sem resposta, todo ciclo está aberto.
  Future<bool> Function(DateTime day)? isDateInClosedCycle;

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
      isVariableSpend: true,
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
      isVariableSpend: true,
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
        // Compra no cartão: fica na fatura (fecha dia 28, vence dia 5) até ela ser paga
        dueDate: CreditCardInvoiceCalculator.calculateInvoiceDueDate(
          purchaseDate: cycleStart.add(const Duration(days: 1)),
          closingDay: 28,
          dueDay: 5,
        ),
        categoryId: 'cat_carro', // Dono 100% Carlos
        paidByMemberId: 'member_carlos',
        paymentMethodId: 'pm_card_carlos',
        splitRule: const SplitRule.singleResponsible('member_carlos'),
        status: ExpenseStatus.pending,
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
  Future<Money> getOpeningBalance(FinancialCycle cycle) async =>
      await _rolledSurplus(cycle) +
      await getVaultReturnsForCycle(cycle) +
      HouseInflow.total(_houseInflows, cycle: cycle);

  /// Como no banco: sem fechamento anterior, o primeiro ciclo da casa começa
  /// com o saldo que ela já tinha na conta (0093).
  Future<Money> _rolledSurplus(FinancialCycle cycle) async {
    final hasPrevious = await hasSettlementBefore?.call(cycle) ?? false;
    return _initialBalance.rolledSurplusFor(cycle, hasPreviousSettlement: hasPrevious);
  }

  @override
  Future<DateTime?> getHouseStartDate() async {
    // A casa demo existe há uns seis meses
    final now = DateTime.now();
    final dates = [
      DateTime(now.year, now.month - 6, now.day),
      for (final e in _expenses.where((e) => e.projectId == null)) ...[e.date, ?e.dueDate],
      for (final c in _contributions) c.date,
    ];
    return dates.reduce((a, b) => a.isBefore(b) ? a : b);
  }

  @override
  Future<Money> getVaultReturnsForCycle(FinancialCycle cycle) async {
    final cents = _savingsTransactions
        .where((t) => t.cycleStartDate != null && cycle.contains(t.cycleStartDate!))
        .fold<int>(0, (acc, t) => acc + (t.isWithdraw ? t.amount.cents : -t.amount.cents));
    return Money(cents);
  }

  /// No modo demo há os resgates e o saldo inicial da conta: a sobra dos
  /// outros ciclos fica com o fechamento de demonstração.
  @override
  Future<OpeningInflows> getOpeningInflows(FinancialCycle cycle) async {
    final cents = <String, int>{};
    for (final t in _savingsTransactions) {
      if (t.cycleStartDate == null || !cycle.contains(t.cycleStartDate!)) continue;
      cents[t.vaultId] = (cents[t.vaultId] ?? 0) + (t.isWithdraw ? t.amount.cents : -t.amount.cents);
    }
    return OpeningInflows(
      rolledSurplus: await _rolledSurplus(cycle),
      vaultWithdrawalsByVault: {for (final e in cents.entries) e.key: Money(e.value)},
      vaultNames: {for (final v in _savingsVaults) v.id: v.name},
      thirdParty: HouseInflow.total(_houseInflows, cycle: cycle),
    );
  }

  @override
  Future<List<Contribution>> getContributionsForCycle(FinancialCycle cycle) async {
    return _contributions.where((c) => cycle.contains(c.date)).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  @override
  Future<FinancialCycleSummary> getCycleSummary(
    FinancialCycle cycle, {
    List<HouseExpense>? expenses,
    List<Contribution>? contributions,
  }) async {
    final cycleExpenses = expenses ?? await getExpensesForCycle(cycle);
    final cycleContributions = contributions ?? await getContributionsForCycle(cycle);

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

    // Empréstimos que o Caixa liberou no ciclo também saíram dele
    final loansFunded = await houseLoansFundedIn?.call(cycle) ?? const Money.zero();

    // Fôlego = Dinheiro da casa no início + Aportes - (Despesas Pagas + Contas a vencer do ciclo)
    final folego =
        await getOpeningBalance(cycle) + totalContrib - (totalPaid + committedFuture) - loansFunded;

    return FinancialCycleSummary(
      cycle: cycle,
      totalContributions: totalContrib,
      totalExpensesPaid: totalPaid,
      committedFutureExpenses: committedFuture,
      folego: folego,
      memberContributions: memberContribs,
      memberExpensesPaid: memberPaid,
      vaultReturns: await getVaultReturnsForCycle(cycle),
      houseLoansFunded: loansFunded,
      openingInflows: await getOpeningInflows(cycle),
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

  /// No modo demo só há um aparelho: nada muda por fora.
  @override
  Stream<void> watchHouseChanges() => const Stream.empty();

  @override
  Future<void> updateCategory(ExpenseCategory category) async {
    final index = _categories.indexWhere((c) => c.id == category.id);
    if (index == -1) return;
    final oldOwnerId = _categories[index].ownerMemberId;
    _categories[index] = category;
    if (oldOwnerId != category.ownerMemberId) {
      _applyCategoryOwnerToOpenExpenses(category, oldOwnerId);
    }
  }

  /// Como o gatilho do banco (migration 0051): despesas ainda não fechadas da
  /// categoria passam a seguir o dono novo; sem dono, voltam ao rateio da casa.
  void _applyCategoryOwnerToOpenExpenses(ExpenseCategory category, String? oldOwnerId) {
    final newOwnerId = category.ownerMemberId;
    for (var i = 0; i < _expenses.length; i++) {
      var e = _expenses[i];
      if (e.settledAt != null || e.isProjectExpense) continue;

      if (e.items.any((it) => it.categoryId == category.id)) {
        e = e.copyWith(
          items: [
            for (final it in e.items)
              if (it.categoryId == category.id &&
                  (it.responsibleMemberId == null || it.responsibleMemberId == oldOwnerId))
                HouseExpenseItem(
                  id: it.id,
                  expenseId: it.expenseId,
                  title: it.title,
                  amount: it.amount,
                  categoryId: it.categoryId,
                  responsibleMemberId: newOwnerId,
                  splitRule: newOwnerId != null ? SplitRule.singleResponsible(newOwnerId) : null,
                )
              else
                it,
          ],
        );
      }

      if (e.categoryId == category.id) {
        if (newOwnerId != null) {
          e = e.copyWith(splitRule: SplitRule.singleResponsible(newOwnerId));
        } else if (e.splitRule.type == SplitType.categoryOwner &&
            e.splitRule.singleResponsibleMemberId == oldOwnerId) {
          e = e.copyWith(
            splitRule: SplitRule.percentage({
              for (final m in _members) m.id: m.defaultSplitPercent,
            }),
          );
        }
      }
      _expenses[i] = e;
    }
  }

  @override
  Future<void> deleteCategory(String categoryId, {String? moveToCategoryId}) async {
    if (moveToCategoryId != null) {
      if (moveToCategoryId == categoryId || !_categories.any((c) => c.id == moveToCategoryId)) {
        throw const ServerFailure('Escolha outra categoria para receber os lançamentos.');
      }
      // Os lançamentos passam para a outra categoria; o rateio de cada um não muda
      for (var i = 0; i < _expenses.length; i++) {
        final e = _expenses[i];
        _expenses[i] = e.copyWith(
          categoryId: e.categoryId == categoryId ? moveToCategoryId : null,
          items: e.items
              .map((it) => it.categoryId == categoryId ? it.copyWith(categoryId: moveToCategoryId) : it)
              .toList(),
        );
      }
    }
    final inUse = _expenses.where((e) =>
        e.categoryId == categoryId || e.items.any((i) => i.categoryId == categoryId)).length;
    if (inUse > 0) {
      throw ServerFailure(categoryInUseMessage(inUse));
    }
    _categories.removeWhere((c) => c.id == categoryId);
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

  Map<String, dynamic> _houseSettingsRow = {};

  @override
  Future<HouseSettings> getHouseSettings() async => HouseSettings.fromJson(_houseSettingsRow);

  @override
  Future<HouseSettings> updateHouseSettings(Map<String, dynamic> changes) async {
    _houseSettingsRow = {..._houseSettingsRow, ...changes};
    return HouseSettings.fromJson(_houseSettingsRow);
  }

  HouseInitialBalance _initialBalance = const HouseInitialBalance();

  /// Lançamento do saldo inicial na Reserva: gravar de novo corrige este.
  String? _initialReserveTransactionId;

  @override
  Future<HouseInitialBalance> getHouseInitialBalance() async => _initialBalance;

  @override
  Future<HouseInitialBalance> setHouseInitialBalance({
    required Money reserve,
    required Money cash,
    required DateTime cycleStart,
  }) async {
    if (reserve.isNegative || cash.isNegative) {
      throw const ServerFailure('O saldo inicial não pode ser negativo.');
    }
    final txIndex = _savingsTransactions.indexWhere((t) => t.id == _initialReserveTransactionId);
    final old = txIndex == -1 ? null : _savingsTransactions[txIndex];
    if (reserve.cents != (old?.amount.cents ?? 0)) {
      // A mesma caixinha do lançamento anterior; sem ele, a Reserva da Casa
      var vaultIndex = old == null
          ? _savingsVaults.indexWhere((v) => v.name == 'Reserva da Casa')
          : _savingsVaults.indexWhere((v) => v.id == old.vaultId);
      if (vaultIndex == -1 && old == null) vaultIndex = _savingsVaults.isEmpty ? -1 : 0;
      if (vaultIndex == -1) throw const ServerFailure('Caixinha não encontrada nesta casa.');
      final vault = _savingsVaults[vaultIndex];
      final balance = vault.currentBalance.cents + reserve.cents - (old?.amount.cents ?? 0);
      if (balance < 0) {
        throw ServerFailure('A caixinha "${vault.name}" já usou parte do saldo inicial e ficaria negativa.');
      }
      _savingsVaults[vaultIndex] = vault.copyWith(currentBalance: Money(balance));
      if (old != null) _savingsTransactions.removeAt(txIndex);
      _initialReserveTransactionId = null;
      if (!reserve.isZero) {
        final tx = SavingsTransaction(
          id: old?.id ?? 'tx_initial_${DateTime.now().microsecondsSinceEpoch}',
          vaultId: vault.id,
          memberId: old?.memberId ?? 'member_carlos',
          amount: reserve,
          type: 'deposit',
          description: 'Saldo inicial da casa',
          date: old?.date ?? DateTime.now(),
        );
        _savingsTransactions.add(tx);
        _initialReserveTransactionId = tx.id;
      }
    }
    _initialBalance = HouseInitialBalance(
      reserve: reserve,
      cash: cash,
      cashCycleStart: cash.isZero ? null : DateTime(cycleStart.year, cycleStart.month, cycleStart.day),
    );
    return _initialBalance;
  }

  // --- Caixinhas & Metas da Casa (Dinheiro Blindado) ---
  @override
  Future<List<SavingsVault>> getSavingsVaults() async {
    return List.unmodifiable(_savingsVaults);
  }

  @override
  Future<List<SavingsTransaction>> getVaultTransactions(String vaultId, {int limit = 50, DateTime? before}) async {
    final list = _savingsTransactions
        .where((t) => t.vaultId == vaultId && (before == null || t.date.isBefore(before)))
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    return list.take(limit).toList();
  }

  @override
  Future<void> updateSavingsVault(SavingsVault vault) async {
    if (vault.name.trim().isEmpty) throw const ServerFailure('Dê um nome à caixinha.');
    final index = _savingsVaults.indexWhere((v) => v.id == vault.id);
    if (index == -1) throw const ServerFailure('Caixinha não encontrada nesta casa.');
    // O saldo só muda por movimentação
    _savingsVaults[index] = vault.copyWith(currentBalance: _savingsVaults[index].currentBalance);
  }

  @override
  Future<void> deleteSavingsVault(String vaultId) async {
    final index = _savingsVaults.indexWhere((v) => v.id == vaultId);
    if (index == -1) throw const ServerFailure('Caixinha não encontrada nesta casa.');
    if (_savingsVaults[index].currentBalance.cents != 0) {
      throw const ServerFailure('Esvazie a caixinha antes de excluir: resgate ou transfira o saldo.');
    }
    _savingsVaults.removeAt(index);
  }

  @override
  Future<void> transferBetweenVaults({
    required String fromVaultId,
    required String toVaultId,
    required Money amount,
    required String description,
  }) async {
    if (description.trim().isEmpty) throw const ServerFailure('Informe o motivo da transferência.');
    if (amount.cents <= 0) throw const ServerFailure('O valor deve ser maior que zero.');
    if (fromVaultId == toVaultId) throw const ServerFailure('Escolha outra caixinha para receber o valor.');
    final from = _savingsVaults.indexWhere((v) => v.id == fromVaultId);
    final to = _savingsVaults.indexWhere((v) => v.id == toVaultId);
    if (from == -1 || to == -1) throw const ServerFailure('Caixinha não encontrada nesta casa.');
    if (_savingsVaults[from].currentBalance.cents < amount.cents) {
      throw const ServerFailure('Saldo insuficiente na caixinha.');
    }
    _savingsVaults[from] = _savingsVaults[from].copyWith(currentBalance: _savingsVaults[from].currentBalance - amount);
    _savingsVaults[to] = _savingsVaults[to].copyWith(currentBalance: _savingsVaults[to].currentBalance + amount);
    final now = DateTime.now();
    _savingsTransactions.add(SavingsTransaction(
      id: 'tx_${now.microsecondsSinceEpoch}_out',
      vaultId: fromVaultId,
      memberId: 'member_carlos',
      amount: amount,
      type: 'withdraw',
      description: description.trim(),
      date: now,
      counterpartVaultId: toVaultId,
    ));
    _savingsTransactions.add(SavingsTransaction(
      id: 'tx_${now.microsecondsSinceEpoch}_in',
      vaultId: toVaultId,
      memberId: 'member_carlos',
      amount: amount,
      type: 'deposit',
      description: description.trim(),
      date: now,
      counterpartVaultId: fromVaultId,
    ));
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
    DateTime? fromCycleStart,
  }) async {
    if (description.trim().isEmpty) {
      throw const ServerFailure('Informe o motivo do depósito.');
    }
    final index = _savingsVaults.indexWhere((v) => v.id == vaultId);
    if (index != -1) {
      // Como no banco: do Caixa do ciclo só sai o que as caixinhas devolveram a ele
      if (fromCycleStart != null) {
        final available = await getVaultReturnsForCycle(
          FinancialCycle(start: fromCycleStart, end: fromCycleStart),
        );
        if (amount.cents > available.cents) {
          throw ServerFailure(
            'O Caixa do ciclo só tem ${available.format()} vindo das caixinhas para devolver.',
          );
        }
      }
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
        cycleStartDate: fromCycleStart,
      ));
    }
  }

  @override
  Future<void> withdrawFromVault({
    required String vaultId,
    required String memberId,
    required Money amount,
    required String description,
    DateTime? returnToCycleStart,
  }) async {
    final index = _savingsVaults.indexWhere((v) => v.id == vaultId);
    if (index != -1) {
      final current = _savingsVaults[index];
      if (description.trim().isEmpty) {
        throw const ServerFailure('Informe o motivo do resgate.');
      }
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
        cycleStartDate: returnToCycleStart,
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
    bool paidByHouse = false,
  }) async {
    bool sameDay(DateTime a, DateTime b) =>
        a.year == b.year && a.month == b.month && a.day == b.day;
    final card = _paymentMethods.where((p) => p.id == paymentMethodId).firstOrNull;

    for (int i = 0; i < _expenses.length; i++) {
      final e = _expenses[i];
      if (e.paymentMethodId == paymentMethodId &&
          e.dueDate != null &&
          e.paidAt == null &&
          e.settledAt == null &&
          !e.isProjectExpense &&
          !e.isRecurring &&
          sameDay(e.dueDate!, invoiceDueDate)) {
        // Como no banco: pelo titular há reembolso; pelo Caixa (ou cartão sem dono), não
        _expenses[i] = e.copyWith(
          status: ExpenseStatus.paid,
          paidAt: paidAt,
          paidOutOfPocket: !paidByHouse && card?.ownerMemberId != null,
        );
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
          due.day == invoiceDueDate.day &&
          e.settledAt == null &&
          !e.isProjectExpense &&
          !e.isRecurring) {
        // A fatura volta a ficar em aberto
        _expenses[i] = e.copyWith(
          status: ExpenseStatus.pending,
          clearPaidAt: true,
          paidOutOfPocket: false,
        );
      }
    }
  }

  final Map<String, CardInvoiceCode> _invoiceCodes = {};

  @override
  Future<List<CardInvoiceCode>> getCardInvoiceCodes() async => _invoiceCodes.values.toList();

  @override
  Future<void> saveCardInvoiceCode({
    required String paymentMethodId,
    required DateTime invoiceDueDate,
    String? barcode,
  }) async {
    final key = CardInvoiceCode.keyOf(paymentMethodId, invoiceDueDate);
    if (barcode == null || barcode.trim().isEmpty) {
      _invoiceCodes.remove(key);
    } else {
      _invoiceCodes[key] = CardInvoiceCode(
        paymentMethodId: paymentMethodId,
        dueDate: DateTime(invoiceDueDate.year, invoiceDueDate.month, invoiceDueDate.day),
        barcode: barcode.trim(),
      );
    }
  }

  final List<ThirdPartyReceipt> _thirdPartyReceipts = [];
  int _receiptSequence = 0;

  @override
  Future<List<ThirdPartyReceipt>> getThirdPartyReceipts() async =>
      [..._thirdPartyReceipts]..sort((a, b) => b.receivedOn.compareTo(a.receivedOn));

  @override
  Future<void> registerThirdPartyReceipt({
    required String payerName,
    required Money amount,
    required DateTime receivedOn,
    required String vaultId,
    String? paymentMethodId,
    String? description,
  }) async {
    final payer = payerName.trim();
    if (payer.isEmpty) throw const ServerFailure('Informe quem pagou.');
    if (amount.cents <= 0) throw const ServerFailure('O valor deve ser maior que zero.');
    if (!_savingsVaults.any((v) => v.id == vaultId)) {
      throw const ServerFailure('Caixinha não encontrada nesta casa.');
    }
    final note = description?.trim();
    // Como no banco: a entrada e o depósito na caixinha andam juntos
    await depositToVault(
      vaultId: vaultId,
      memberId: _members.first.id,
      amount: amount,
      description: 'Repasse de $payer${note == null || note.isEmpty ? '' : ': $note'}',
    );
    _thirdPartyReceipts.add(ThirdPartyReceipt(
      id: 'receipt_${++_receiptSequence}',
      payerName: payer,
      description: note == null || note.isEmpty ? null : note,
      amount: amount,
      receivedOn: DateTime(receivedOn.year, receivedOn.month, receivedOn.day),
      vaultId: vaultId,
      paymentMethodId: paymentMethodId,
    ));
  }

  @override
  Future<void> useThirdPartyReceipts({
    required List<String> receiptIds,
    required ThirdPartyReceiptUse use,
    String? paymentMethodId,
    DateTime? invoiceDueDate,
  }) async {
    final targets = [
      for (final id in receiptIds) _thirdPartyReceipts.where((r) => r.id == id).firstOrNull,
    ];
    if (targets.any((r) => r == null)) {
      throw const ServerFailure('Entrada de terceiros não encontrada nesta casa.');
    }
    for (final receipt in targets.cast<ThirdPartyReceipt>()) {
      if (receipt.isUsed) throw ServerFailure('O repasse de ${receipt.payerName} já foi usado.');
    }
    for (final receipt in targets.cast<ThirdPartyReceipt>()) {
      await withdrawFromVault(
        vaultId: receipt.vaultId,
        memberId: _members.first.id,
        amount: receipt.amount,
        description: use == ThirdPartyReceiptUse.housePaid
            ? 'Repasse de ${receipt.payerName} usado na fatura'
            : 'Repasse de ${receipt.payerName} entregue a quem pagou a fatura',
      );
      final index = _thirdPartyReceipts.indexOf(receipt);
      _thirdPartyReceipts[index] = receipt.markUsed(
        use: use,
        paymentMethodId: paymentMethodId,
        dueDate: invoiceDueDate,
        at: DateTime.now(),
      );
    }
  }

  @override
  Future<void> reopenThirdPartyReceipts({
    List<String>? receiptIds,
    String? paymentMethodId,
    DateTime? invoiceDueDate,
  }) async {
    bool sameDay(DateTime? a, DateTime? b) =>
        a != null && b != null && a.year == b.year && a.month == b.month && a.day == b.day;
    for (var i = 0; i < _thirdPartyReceipts.length; i++) {
      final receipt = _thirdPartyReceipts[i];
      if (!receipt.isUsed) continue;
      final matches = receiptIds != null
          ? receiptIds.contains(receipt.id)
          : receipt.usedPaymentMethodId == paymentMethodId && sameDay(receipt.usedDueDate, invoiceDueDate);
      if (!matches) continue;
      await depositToVault(
        vaultId: receipt.vaultId,
        memberId: _members.first.id,
        amount: receipt.amount,
        description: 'Repasse de ${receipt.payerName} voltou para a caixinha',
      );
      _thirdPartyReceipts[i] = receipt.reopened();
    }
  }

  @override
  Future<void> deleteThirdPartyReceipt(String receiptId) async {
    final receipt = _thirdPartyReceipts.where((r) => r.id == receiptId).firstOrNull;
    if (receipt == null) throw const ServerFailure('Entrada de terceiros não encontrada nesta casa.');
    if (receipt.isUsed) throw const ServerFailure('Desfaça o uso do repasse antes de excluí-lo.');
    await withdrawFromVault(
      vaultId: receipt.vaultId,
      memberId: _members.first.id,
      amount: receipt.amount,
      description: 'Repasse de ${receipt.payerName} excluído',
    );
    _thirdPartyReceipts.remove(receipt);
  }

  // --- Entradas de fora (0096) ---
  final List<HouseInflow> _houseInflows = [];
  int _inflowSequence = 0;

  Future<void> _checkHouseInflow(HouseInflow inflow) async {
    if (inflow.amount.cents <= 0) throw const ServerFailure('O valor deve ser maior que zero.');
    if (inflow.description.trim().isEmpty) throw const ServerFailure('Diga do que é a entrada.');
    if (await isDateInClosedCycle?.call(inflow.receivedOn) ?? false) {
      throw const ServerFailure(
        'O ciclo desse dia já foi fechado. Reabra o ciclo no Fechamento para mexer nas entradas dele.',
      );
    }
  }

  @override
  Future<List<HouseInflow>> getHouseInflowsForCycle(FinancialCycle cycle) async =>
      _houseInflows.where((i) => cycle.contains(i.receivedOn)).toList()
        ..sort((a, b) => b.receivedOn.compareTo(a.receivedOn));

  @override
  Future<void> addHouseInflow(HouseInflow inflow) async {
    await _checkHouseInflow(inflow);
    _houseInflows.add(HouseInflow(
      id: 'inflow_${++_inflowSequence}',
      amount: inflow.amount,
      receivedOn: inflow.receivedOn,
      description: inflow.description.trim(),
      source: inflow.source,
      expenseId: inflow.expenseId,
      createdBy: inflow.createdBy ?? _members.first.id,
    ));
  }

  @override
  Future<void> updateHouseInflow(HouseInflow inflow) async {
    final index = _houseInflows.indexWhere((i) => i.id == inflow.id);
    if (index < 0) throw const ServerFailure('Entrada de fora não encontrada nesta casa.');
    // O dia antigo e o novo precisam estar em ciclo aberto
    await _checkHouseInflow(_houseInflows[index]);
    await _checkHouseInflow(inflow);
    _houseInflows[index] = _houseInflows[index].copyWith(
      amount: inflow.amount,
      receivedOn: inflow.receivedOn,
      description: inflow.description.trim(),
      source: inflow.source,
      expenseId: inflow.expenseId,
      clearExpense: inflow.expenseId == null,
    );
  }

  @override
  Future<void> deleteHouseInflow(String inflowId) async {
    final inflow = _houseInflows.where((i) => i.id == inflowId).firstOrNull;
    if (inflow == null) throw const ServerFailure('Entrada de fora não encontrada nesta casa.');
    await _checkHouseInflow(inflow);
    _houseInflows.remove(inflow);
  }
}
