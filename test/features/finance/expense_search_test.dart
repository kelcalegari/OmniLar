import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/features/finance/domain/entities/house_expense.dart';
import 'package:omni_lar/features/finance/domain/entities/house_expense_item.dart';
import 'package:omni_lar/features/finance/domain/entities/split_rule.dart';
import 'package:omni_lar/features/finance/domain/services/expense_search.dart';

void main() {
  final expense = HouseExpense(
    id: 'exp_1',
    title: 'Condomínio Edifício Solar',
    amount: const Money(31240),
    date: DateTime(2026, 10, 10),
    categoryId: 'cat_moradia',
    paidByMemberId: 'member_carlos',
    paymentMethodId: 'pm_caixa',
    splitRule: const SplitRule.percentage({'member_carlos': 50, 'member_marina': 50}),
    items: const [
      HouseExpenseItem(id: 'it_1', expenseId: 'exp_1', title: 'Fundo de reserva', amount: Money(5000)),
    ],
  );

  bool matches(String query) => expenseMatchesSearch(
        expense,
        query,
        categoryName: 'Moradia',
        payerName: 'Carlos Silva',
        paymentMethodName: 'Nubank',
      );

  test('Acha pelo título sem acento e sem diferenciar maiúsculas', () {
    expect(matches('condominio'), isTrue);
    expect(matches('EDIFÍCIO solar'), isTrue);
  });

  test('Acha pela categoria, por quem pagou, pela forma de pagamento e pelos itens', () {
    expect(matches('moradia'), isTrue);
    expect(matches('carlos'), isTrue);
    expect(matches('nubank'), isTrue);
    expect(matches('reserva'), isTrue);
  });

  test('Acha pelo valor', () {
    expect(matches('312,40'), isTrue);
  });

  test('Todas as palavras precisam aparecer', () {
    expect(matches('condominio mercado'), isFalse);
    expect(matches('marina'), isFalse);
  });

  test('Busca vazia mostra tudo', () {
    expect(matches('   '), isTrue);
  });
}
