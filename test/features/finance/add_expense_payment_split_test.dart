import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/di/service_locator.dart';
import 'package:omni_lar/core/domain/value_objects/financial_cycle.dart';
import 'package:omni_lar/features/finance/data/datasources/finance_datasource.dart';
import 'package:omni_lar/features/finance/domain/entities/house_expense.dart';
import 'package:omni_lar/features/finance/presentation/cubit/finance_cubit.dart';
import 'package:omni_lar/features/finance/presentation/pages/add_expense_page.dart';

/// Lançar uma nota paga com mais de um meio (0124): o meio principal fica com
/// o que os outros não cobrem.
void main() {
  setUpAll(() async {
    if (!sl.isRegistered<FinanceCubit>()) {
      await initServiceLocator();
    }
  });

  Future<List<HouseExpense>> launchedWithTitle(String title) async {
    final ds = sl<FinanceDataSource>();
    final now = DateTime.now();
    final found = <String, HouseExpense>{};
    for (final offset in [0, 35, 70]) {
      final cycle = FinancialCycle.fromDate(date: now.add(Duration(days: offset)), cycleStartDay: 5);
      for (final e in await ds.getExpensesForCycle(cycle)) {
        if (e.title == title) found[e.id] = e;
      }
    }
    return found.values.toList();
  }

  testWidgets('Divide a nota entre dois meios e grava uma despesa por meio', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final cubit = sl<FinanceCubit>();
    await cubit.loadCycleData();

    await tester.pumpWidget(
      BlocProvider<FinanceCubit>.value(
        value: cubit,
        child: const MaterialApp(home: AddExpensePage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '15000'); // R$ 150,00
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'O que foi pago?'), 'Nota dividida');
    await tester.pumpAndSettle();

    final splitSwitch = find.byKey(const Key('payment_split_switch'));
    await tester.ensureVisible(splitSwitch);
    await tester.pumpAndSettle();
    await tester.tap(splitSwitch);
    await tester.pumpAndSettle();

    final extraAmount = find.descendant(
      of: find.byKey(const Key('payment_split_amount_0')),
      matching: find.byType(TextField),
    );
    await tester.ensureVisible(extraAmount);
    await tester.enterText(extraAmount, '5000'); // R$ 50,00
    await tester.pumpAndSettle();

    final remaining = tester.widget<Text>(find.byKey(const Key('payment_split_main_remaining')));
    expect(remaining.data, contains('100,00'));

    final saveButton = find.widgetWithText(ElevatedButton, 'Lançar Gasto da Casa');
    await tester.ensureVisible(saveButton);
    await tester.pumpAndSettle();
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    final parts = await launchedWithTitle('Nota dividida');
    expect(parts, hasLength(2));
    expect(parts.map((p) => p.paymentGroupId).toSet(), hasLength(1));
    expect(parts.first.paymentGroupId, isNotNull);
    expect(parts.map((p) => p.amount.cents).toList()..sort(), [5000, 10000]);
    expect(parts.map((p) => p.paymentMethodId).toSet(), hasLength(2));

    // Excluir uma parte apaga a nota inteira
    await cubit.deleteExpense(parts.first.id);
    expect(await launchedWithTitle('Nota dividida'), isEmpty);
  });

  testWidgets('Recusa quando os outros meios cobrem a nota toda', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final cubit = sl<FinanceCubit>();
    await cubit.loadCycleData();

    await tester.pumpWidget(
      BlocProvider<FinanceCubit>.value(
        value: cubit,
        child: const MaterialApp(home: AddExpensePage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '15000');
    await tester.enterText(find.widgetWithText(TextField, 'O que foi pago?'), 'Nota errada');
    await tester.pumpAndSettle();

    final splitSwitch = find.byKey(const Key('payment_split_switch'));
    await tester.ensureVisible(splitSwitch);
    await tester.tap(splitSwitch);
    await tester.pumpAndSettle();

    final extraAmount = find.descendant(
      of: find.byKey(const Key('payment_split_amount_0')),
      matching: find.byType(TextField),
    );
    await tester.ensureVisible(extraAmount);
    await tester.enterText(extraAmount, '15000');
    await tester.pumpAndSettle();

    final saveButton = find.widgetWithText(ElevatedButton, 'Lançar Gasto da Casa');
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(find.textContaining('maior que zero'), findsOneWidget);
    expect(await launchedWithTitle('Nota errada'), isEmpty);
  });
}
