import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/domain/value_objects/financial_cycle.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/features/finance/data/datasources/mock_finance_datasource.dart';
import 'package:omni_lar/features/finance/domain/entities/category.dart';
import 'package:omni_lar/features/finance/domain/entities/house_expense.dart';
import 'package:omni_lar/features/finance/domain/entities/house_expense_item.dart';
import 'package:omni_lar/features/finance/domain/entities/house_member.dart';
import 'package:omni_lar/features/finance/domain/entities/split_rule.dart';
import 'package:omni_lar/features/finance/domain/services/cycle_funding_estimator.dart';
import 'package:omni_lar/features/finance/domain/services/expense_launch_defaults.dart';
import 'package:omni_lar/features/settlement/domain/services/global_clearing_engine.dart';

void main() {
  final cycle = FinancialCycle.fromDate(date: DateTime(2026, 10, 12), cycleStartDay: 9);
  const members = [
    HouseMember(id: 'ana', name: 'Ana', defaultFixedAmountCents: 100000, defaultSplitPercent: 50),
    HouseMember(id: 'bia', name: 'Bia', defaultFixedAmountCents: 100000, defaultSplitPercent: 50),
  ];
  final targets = {for (final m in members) m.id: Money(m.defaultFixedAmountCents!)};

  // Despesa de R$ 300 numa categoria da Bia, com dois sub-itens sem responsável
  final itemizedOwnerExpense = HouseExpense(
    id: 'carro',
    title: 'Carro',
    amount: const Money(30000),
    date: DateTime(2026, 10, 12),
    categoryId: 'cat_carro',
    paidByMemberId: 'ana',
    paymentMethodId: 'pm_caixa',
    splitRule: const SplitRule.singleResponsible('bia'),
    items: const [
      HouseExpenseItem(id: 'i1', expenseId: 'carro', title: 'Óleo', amount: Money(10000)),
      HouseExpenseItem(id: 'i2', expenseId: 'carro', title: 'Pneu', amount: Money(20000)),
    ],
  );

  group('Categoria com dono sobrepõe o rateio da casa', () {
    test('Aportes fixos: despesa com sub-itens é cobrada do dono, fora do balde', () {
      final summary = const GlobalClearingEngine().computeSettlement(
        cycle: cycle,
        members: members,
        expenses: [itemizedOwnerExpense],
        contributions: const [],
        loans: const [],
        customContributionTargets: targets,
      );

      final ana = summary.memberBalances.firstWhere((b) => b.memberId == 'ana');
      final bia = summary.memberBalances.firstWhere((b) => b.memberId == 'bia');
      expect(ana.contributionDue.cents, 100000);
      expect(bia.contributionDue.cents, 100000 + 30000);
      expect(summary.bucketDeficit.cents, 0);
    });

    test('Aportes fixos: sub-item marcado para outro morador continua dele', () {
      final mixed = itemizedOwnerExpense.copyWith(
        items: const [
          HouseExpenseItem(id: 'i1', expenseId: 'carro', title: 'Óleo', amount: Money(10000)),
          HouseExpenseItem(
            id: 'i2',
            expenseId: 'carro',
            title: 'Lavagem da Ana',
            amount: Money(20000),
            responsibleMemberId: 'ana',
            splitRule: SplitRule.singleResponsible('ana'),
          ),
        ],
      );
      final summary = const GlobalClearingEngine().computeSettlement(
        cycle: cycle,
        members: members,
        expenses: [mixed],
        contributions: const [],
        loans: const [],
        customContributionTargets: targets,
      );

      final ana = summary.memberBalances.firstWhere((b) => b.memberId == 'ana');
      final bia = summary.memberBalances.firstWhere((b) => b.memberId == 'bia');
      expect(ana.contributionDue.cents, 100000 + 20000);
      expect(bia.contributionDue.cents, 100000 + 10000);
    });

    test('Planejador em aportes fixos mostra a mesma cota do fechamento', () {
      final simpleOwnerExpense = HouseExpense(
        id: 'seguro',
        title: 'Seguro',
        amount: const Money(5000),
        date: DateTime(2026, 10, 12),
        categoryId: 'cat_carro',
        paidByMemberId: 'ana',
        paymentMethodId: 'pm_caixa',
        splitRule: const SplitRule.singleResponsible('bia'),
      );
      final expenses = [itemizedOwnerExpense, simpleOwnerExpense];

      final estimate = const CycleFundingEstimator().calculateEstimate(
        cycle: cycle,
        members: members,
        categories: const [],
        currentCycleExpenses: expenses,
        historicalExpenses: const [],
        currentCycleContributions: const [],
      );
      final summary = const GlobalClearingEngine().computeSettlement(
        cycle: cycle,
        members: members,
        expenses: expenses,
        contributions: const [],
        loans: const [],
        customContributionTargets: targets,
      );

      for (final m in members) {
        final quote = estimate.memberQuotes.firstWhere((q) => q.memberId == m.id);
        final due = summary.memberBalances.firstWhere((b) => b.memberId == m.id).contributionDue;
        expect(quote.recommendedAmount.cents, due.cents, reason: m.name);
      }
      expect(
        estimate.memberQuotes.firstWhere((q) => q.memberId == 'bia').recommendedAmount.cents,
        100000 + 35000,
      );
    });

    test('Sub-item em categoria com dono é do dono, salvo outro morador marcado', () {
      const carro = ExpenseCategory(
        id: 'cat_carro',
        name: 'Carro',
        icon: 'car',
        colorHex: '#000000',
        ownerMemberId: 'bia',
      );
      const mercado = ExpenseCategory(id: 'cat_mercado', name: 'Mercado', icon: 'm', colorHex: '#000000');

      expect(
        ExpenseLaunchDefaults.itemResponsible(chosenMemberId: null, itemCategory: carro),
        'bia',
      );
      expect(
        ExpenseLaunchDefaults.itemResponsible(chosenMemberId: 'ana', itemCategory: carro),
        'ana',
      );
      expect(
        ExpenseLaunchDefaults.itemResponsible(chosenMemberId: null, itemCategory: mercado),
        isNull,
      );
    });
  });

  group('Trocar o dono da categoria vale para as despesas em aberto', () {
    Future<HouseExpense> addExpense(
      MockFinanceDataSource ds, {
      required String id,
      DateTime? settledAt,
    }) async {
      final members = await ds.getMembers();
      final e = HouseExpense(
        id: id,
        title: id,
        amount: const Money(20000),
        date: DateTime(2026, 10, 12),
        categoryId: 'cat_teste',
        paidByMemberId: members.first.id,
        paymentMethodId: 'pm_caixa',
        splitRule: SplitRule.percentage({for (final m in members) m.id: m.defaultSplitPercent}),
        settledAt: settledAt,
        items: [
          HouseExpenseItem(
            id: '${id}_i1',
            expenseId: id,
            title: 'Item',
            amount: const Money(20000),
            categoryId: 'cat_teste',
          ),
        ],
      );
      await ds.addExpense(e);
      return e;
    }

    Future<HouseExpense> find(MockFinanceDataSource ds, String id) async {
      final cycle = FinancialCycle.fromDate(date: DateTime(2026, 10, 12), cycleStartDay: 5);
      return (await ds.getExpensesForCycle(cycle)).firstWhere((e) => e.id == id);
    }

    const base = ExpenseCategory(id: 'cat_teste', name: 'Teste', icon: 'c', colorHex: '#000000');
    ExpenseCategory withOwner(String? ownerId) => ExpenseCategory(
          id: base.id,
          name: base.name,
          icon: base.icon,
          colorHex: base.colorHex,
          ownerMemberId: ownerId,
        );

    test('Definir o dono muda a despesa aberta e preserva a já fechada', () async {
      final ds = MockFinanceDataSource();
      final owner = (await ds.getMembers()).last.id;
      await ds.addCategory(base);
      await addExpense(ds, id: 'aberta');
      await addExpense(ds, id: 'fechada', settledAt: DateTime(2026, 10, 20));

      await ds.updateCategory(withOwner(owner));

      final open = await find(ds, 'aberta');
      expect(open.splitRule.type, SplitType.categoryOwner);
      expect(open.splitRule.singleResponsibleMemberId, owner);
      expect(open.items.single.responsibleMemberId, owner);

      final settled = await find(ds, 'fechada');
      expect(settled.splitRule.type, SplitType.percentage);
      expect(settled.items.single.responsibleMemberId, isNull);
    });

    test('Tirar o dono devolve a despesa aberta ao rateio da casa', () async {
      final ds = MockFinanceDataSource();
      final owner = (await ds.getMembers()).last.id;
      await ds.addCategory(base);
      await addExpense(ds, id: 'aberta');
      await ds.updateCategory(withOwner(owner));

      await ds.updateCategory(withOwner(null));

      final open = await find(ds, 'aberta');
      expect(open.splitRule.type, SplitType.percentage);
      expect(open.items.single.responsibleMemberId, isNull);
    });
  });
}
