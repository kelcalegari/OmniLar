import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/features/finance/domain/entities/house_expense.dart';
import 'package:omni_lar/features/finance/domain/entities/split_rule.dart';
import 'package:omni_lar/features/finance/presentation/widgets/expense_detail_desktop_pane.dart';

void main() {
  testWidgets('Painel de detalhes do gasto renderiza dentro de uma área rolável', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: ExpenseDetailDesktopPane(
                    expense: HouseExpense(
                      id: 'e1',
                      title: 'Maçãs',
                      amount: const Money(1000),
                      date: DateTime(2026, 10, 12),
                      categoryId: 'c',
                      paidByMemberId: 'm',
                      paymentMethodId: 'pm',
                      splitRule: const SplitRule.percentage(null),
                    ),
                    members: const [],
                    onClose: () {},
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Maçãs'), findsOneWidget);
  });
}
