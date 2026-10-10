import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/features/finance/domain/entities/house_expense.dart';
import 'package:omni_lar/features/finance/domain/entities/house_expense_item.dart';
import 'package:omni_lar/features/finance/domain/entities/split_rule.dart';

void main() {
  group('HouseExpenseItem & HouseExpense (Despesas Compostas)', () {
    test('HouseExpenseItem possui propriedades e imutabilidade corretas', () {
      const item = HouseExpenseItem(
        id: 'item_1',
        expenseId: 'exp_1',
        title: 'Água',
        amount: Money(12000),
        categoryId: 'cat_contas',
        responsibleMemberId: 'member_carlos',
        splitRule: SplitRule.singleResponsible('member_carlos'),
      );

      expect(item.id, equals('item_1'));
      expect(item.title, equals('Água'));
      expect(item.amount.cents, equals(12000));
      expect(item.responsibleMemberId, equals('member_carlos'));

      final updated = item.copyWith(amount: const Money(15000));
      expect(updated.amount.cents, equals(15000));
      expect(updated.title, equals('Água'));
    });

    test('HouseExpense calcula isItemized e isItemsBalanced corretamente', () {
      final now = DateTime.now();
      final baseExpense = HouseExpense(
        id: 'exp_condo',
        title: 'Condomínio',
        amount: const Money(85000), // R$ 850,00
        date: now,
        categoryId: 'cat_moradia',
        paidByMemberId: 'member_carlos',
        paymentMethodId: 'pm_caixa',
        splitRule: const SplitRule.percentage({'member_carlos': 60, 'member_marina': 40}),
      );

      // Despesa simples não é itemizada e está balanceada
      expect(baseExpense.isItemized, isFalse);
      expect(baseExpense.isItemsBalanced, isTrue);
      expect(baseExpense.itemsTotalCents, equals(0));

      // Despesa itemizada com sub-itens que batem exatamente os 850,00
      final balancedExpense = baseExpense.copyWith(
        items: const [
          HouseExpenseItem(
            id: 'it_1',
            expenseId: 'exp_condo',
            title: 'Taxa Ordinária',
            amount: Money(50000), // R$ 500,00
          ),
          HouseExpenseItem(
            id: 'it_2',
            expenseId: 'exp_condo',
            title: 'Água',
            amount: Money(12000), // R$ 120,00
          ),
          HouseExpenseItem(
            id: 'it_3',
            expenseId: 'exp_condo',
            title: 'Gás',
            amount: Money(8000), // R$ 80,00
          ),
          HouseExpenseItem(
            id: 'it_4',
            expenseId: 'exp_condo',
            title: 'Fundo Obras',
            amount: Money(15000), // R$ 150,00
          ),
        ],
      );

      expect(balancedExpense.isItemized, isTrue);
      expect(balancedExpense.itemsTotalCents, equals(85000));
      expect(balancedExpense.isItemsBalanced, isTrue);

      // Despesa itemizada desbalanceada (soma dá 700,00 em vez de 850,00)
      final unbalancedExpense = baseExpense.copyWith(
        items: const [
          HouseExpenseItem(
            id: 'it_1',
            expenseId: 'exp_condo',
            title: 'Taxa Ordinária',
            amount: Money(50000),
          ),
          HouseExpenseItem(
            id: 'it_2',
            expenseId: 'exp_condo',
            title: 'Água',
            amount: Money(20000),
          ),
        ],
      );

      expect(unbalancedExpense.isItemized, isTrue);
      expect(unbalancedExpense.itemsTotalCents, equals(70000));
      expect(unbalancedExpense.isItemsBalanced, isFalse);
    });
  });
}
