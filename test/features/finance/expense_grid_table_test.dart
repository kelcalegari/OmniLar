import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/features/finance/domain/entities/house_expense.dart';
import 'package:omni_lar/features/finance/domain/entities/split_rule.dart';
import 'package:omni_lar/features/finance/presentation/widgets/expense_grid_table.dart';

HouseExpense _expense(String id, String title, int cents, DateTime date) => HouseExpense(
      id: id,
      title: title,
      amount: Money(cents),
      date: date,
      categoryId: 'cat',
      paidByMemberId: 'member',
      paymentMethodId: 'pm',
      splitRule: const SplitRule.percentage({'member': 100}),
    );

void main() {
  final expenses = [
    _expense('a', 'Padaria', 1500, DateTime(2026, 10, 12)),
    _expense('b', 'Aluguel', 200000, DateTime(2026, 10, 5)),
    _expense('c', 'Mercado', 31240, DateTime(2026, 10, 8)),
  ];

  Future<String?> pump(WidgetTester tester) async {
    String? selected;
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => ExpenseGridTable(
            expenses: expenses,
            categories: const [],
            members: const [],
            paymentMethods: const [],
            selectedExpenseId: selected,
            onSelect: (id) => setState(() => selected = id),
          ),
        ),
      ),
    ));
    return selected;
  }

  List<String> titlesInOrder(WidgetTester tester) {
    final titles = ['Padaria', 'Aluguel', 'Mercado'];
    final positions = {for (final t in titles) t: tester.getTopLeft(find.text(t)).dy};
    return titles..sort((a, b) => positions[a]!.compareTo(positions[b]!));
  }

  testWidgets('Começa pela data mais recente e ordena pelo valor ao tocar na coluna', (tester) async {
    await pump(tester);
    expect(titlesInOrder(tester), ['Padaria', 'Mercado', 'Aluguel']);

    await tester.tap(find.text('Valor'));
    await tester.pumpAndSettle();
    expect(titlesInOrder(tester), ['Padaria', 'Mercado', 'Aluguel']);

    await tester.tap(find.text('Valor'));
    await tester.pumpAndSettle();
    expect(titlesInOrder(tester), ['Aluguel', 'Mercado', 'Padaria']);
  });

  testWidgets('Tocar na linha seleciona a despesa', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Mercado'));
    await tester.pumpAndSettle();
    final table = tester.widget<DataTable>(find.byKey(const Key('expense_grid')));
    expect(table.rows.where((r) => r.selected), hasLength(1));
  });
}
