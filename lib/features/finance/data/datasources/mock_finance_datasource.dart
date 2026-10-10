import '../../domain/entities/house_member.dart';
import '../../domain/entities/category.dart';
import '../../domain/entities/payment_method.dart';
import '../../domain/entities/house_expense.dart';
import '../../domain/entities/contribution.dart';
import '../../domain/entities/split_rule.dart';
import '../../domain/entities/financial_cycle_summary.dart';
import '../../../../core/domain/value_objects/money.dart';
import '../../../../core/domain/value_objects/financial_cycle.dart';

class MockFinanceDataSource {
  final List<HouseMember> _members = [
    const HouseMember(
      id: 'member_carlos',
      name: 'Carlos',
      role: 'owner',
      defaultSplitPercent: 60.0,
    ),
    const HouseMember(
      id: 'member_marina',
      name: 'Marina',
      role: 'admin',
      defaultSplitPercent: 40.0,
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

    // Aportes de exemplo do ciclo atual
    _contributions.addAll([
      Contribution(
        id: 'contrib_1',
        memberId: 'member_carlos',
        amount: const Money(300000), // R$ 3.000,00
        date: DateTime(now.year, now.month, 5),
      ),
      Contribution(
        id: 'contrib_2',
        memberId: 'member_marina',
        amount: const Money(200000), // R$ 2.000,00
        date: DateTime(now.year, now.month, 5),
      ),
    ]);

    // Despesas de exemplo
    _expenses.addAll([
      HouseExpense(
        id: 'exp_1',
        title: 'Aluguel do Apartamento',
        amount: const Money(220000), // R$ 2.200,00
        date: DateTime(now.year, now.month, 6),
        categoryId: 'cat_moradia',
        paidByMemberId: 'member_carlos',
        paymentMethodId: 'pm_caixa',
        splitRule: const SplitRule.percentage({'member_carlos': 60.0, 'member_marina': 40.0}),
        status: ExpenseStatus.paid,
      ),
      HouseExpense(
        id: 'exp_2',
        title: 'Compras Pão de Açúcar',
        amount: const Money(48560), // R$ 485,60
        date: DateTime(now.year, now.month, 6),
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
        date: DateTime(now.year, now.month, 6),
        categoryId: 'cat_carro', // Dono 100% Carlos
        paidByMemberId: 'member_carlos',
        paymentMethodId: 'pm_card_carlos',
        splitRule: const SplitRule.singleResponsible('member_carlos'),
        status: ExpenseStatus.paid,
      ),
      // Conta futura / provisionada
      HouseExpense(
        id: 'exp_4',
        title: 'Conta de Luz (Enel)',
        amount: const Money(21000), // R$ 210,00
        date: DateTime(now.year, now.month, 20),
        dueDate: DateTime(now.year, now.month, 20),
        categoryId: 'cat_contas',
        paidByMemberId: 'member_carlos',
        paymentMethodId: 'pm_caixa',
        splitRule: const SplitRule.percentage({'member_carlos': 60.0, 'member_marina': 40.0}),
        status: ExpenseStatus.pending,
      ),
      HouseExpense(
        id: 'exp_5',
        title: 'Internet Fibra',
        amount: const Money(12000), // R$ 120,00
        date: DateTime(now.year, now.month, 25),
        dueDate: DateTime(now.year, now.month, 25),
        categoryId: 'cat_contas',
        paidByMemberId: 'member_marina',
        paymentMethodId: 'pm_caixa',
        splitRule: const SplitRule.percentage({'member_carlos': 60.0, 'member_marina': 40.0}),
        status: ExpenseStatus.pending,
      ),
    ]);
  }

  Future<List<HouseMember>> getMembers() async => List.unmodifiable(_members);
  Future<List<ExpenseCategory>> getCategories() async => List.unmodifiable(_categories);
  Future<List<PaymentMethod>> getPaymentMethods() async => List.unmodifiable(_paymentMethods);

  Future<List<HouseExpense>> getExpensesForCycle(FinancialCycle cycle) async {
    return _expenses.where((e) => cycle.contains(e.date) || (e.dueDate != null && cycle.contains(e.dueDate!))).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  Future<List<Contribution>> getContributionsForCycle(FinancialCycle cycle) async {
    return _contributions.where((c) => cycle.contains(c.date)).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

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

  Future<void> addExpense(HouseExpense expense) async {
    _expenses.insert(0, expense);
  }

  Future<void> addContribution(Contribution contribution) async {
    _contributions.insert(0, contribution);
  }

  Future<void> addCategory(ExpenseCategory category) async {
    _categories.add(category);
  }

  Future<void> addPaymentMethod(PaymentMethod paymentMethod) async {
    _paymentMethods.add(paymentMethod);
  }
}
