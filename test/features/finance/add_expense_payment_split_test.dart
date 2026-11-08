import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/di/service_locator.dart';
import 'package:omni_lar/core/domain/value_objects/financial_cycle.dart';
import 'package:omni_lar/features/finance/data/datasources/finance_datasource.dart';
import 'package:omni_lar/features/finance/domain/entities/house_expense.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/features/finance/domain/entities/split_rule.dart';
import 'package:omni_lar/features/finance/domain/services/expense_payment_split.dart';
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
      final cycle = FinancialCycle.fromDate(
        date: now.add(Duration(days: offset)),
        cycleStartDay: 5,
      );
      for (final e in await ds.getExpensesForCycle(cycle)) {
        if (e.title == title) found[e.id] = e;
      }
    }
    return found.values.toList();
  }

  testWidgets('Divide a nota entre dois meios e grava uma despesa por meio', (
    tester,
  ) async {
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
    await tester.enterText(
      find.widgetWithText(TextField, 'O que foi pago?'),
      'Nota dividida',
    );
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

    final remaining = tester.widget<Text>(
      find.byKey(const Key('payment_split_main_remaining')),
    );
    expect(remaining.data, contains('100,00'));

    final saveButton = find.widgetWithText(
      ElevatedButton,
      'Lançar Gasto da Casa',
    );
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

  testWidgets('Recusa quando os outros meios cobrem a nota toda', (
    tester,
  ) async {
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
    await tester.enterText(
      find.widgetWithText(TextField, 'O que foi pago?'),
      'Nota errada',
    );
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

    final saveButton = find.widgetWithText(
      ElevatedButton,
      'Lançar Gasto da Casa',
    );
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(find.textContaining('maior que zero'), findsOneWidget);
    expect(await launchedWithTitle('Nota errada'), isEmpty);
  });

  Future<void> pumpEdit(
    WidgetTester tester,
    FinanceCubit cubit,
    HouseExpense edit,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      BlocProvider<FinanceCubit>.value(
        value: cubit,
        child: MaterialApp(home: AddExpensePage(expenseToEdit: edit)),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> save(WidgetTester tester) async {
    final saveButton = find.widgetWithText(ElevatedButton, 'Salvar Alterações');
    await tester.ensureVisible(saveButton);
    await tester.pumpAndSettle();
    await tester.tap(saveButton);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Editar uma parte carrega a nota inteira e troca os valores das partes',
    (tester) async {
      final cubit = sl<FinanceCubit>();
      await cubit.loadCycleData();
      final methods = cubit.state.paymentMethods
          .where((m) => !m.isCreditCard)
          .take(2)
          .toList();
      expect(methods, hasLength(2));

      final note = HouseExpense(
        id: 'edit_nota',
        title: 'Nota para editar',
        amount: const Money(15000),
        date: DateTime.now(),
        categoryId: cubit.state.categories.first.id,
        paidByMemberId: cubit.state.members.first.id,
        paymentMethodId: methods[0].id,
        splitRule: const SplitRule.percentage(null),
      );
      await cubit.addExpenseGroup(
        ExpensePaymentSplit.build(
          note: note,
          parts: [
            PaymentPart(paymentMethodId: methods[0].id, amountCents: 10000),
            PaymentPart(paymentMethodId: methods[1].id, amountCents: 5000),
          ],
          methods: {for (final m in cubit.state.paymentMethods) m.id: m},
          groupId: 'grp_edit',
          partId: (i) => 'edit_nota_$i',
        ),
      );
      await cubit.loadCycleData();
      final before = (await launchedWithTitle('Nota para editar'));
      expect(before, hasLength(2));
      final firstPart = before.firstWhere((p) => p.amount.cents == 10000);

      await pumpEdit(tester, cubit, firstPart);

      // A nota inteira: R$ 150,00 no total; o outro meio com R$ 50,00
      expect(find.byKey(const Key('payment_split_loading')), findsNothing);
      expect(
        tester
            .widget<Text>(find.byKey(const Key('payment_split_main_remaining')))
            .data,
        contains('100,00'),
      );

      final extraAmount = find.descendant(
        of: find.byKey(const Key('payment_split_amount_0')),
        matching: find.byType(TextField),
      );
      await tester.ensureVisible(extraAmount);
      await tester.enterText(extraAmount, '8000'); // R$ 80,00
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(find.byKey(const Key('payment_split_main_remaining')))
            .data,
        contains('70,00'),
      );

      await save(tester);

      final after = await launchedWithTitle('Nota para editar');
      expect(after.map((p) => p.amount.cents).toList()..sort(), [7000, 8000]);
      expect(
        after.map((p) => p.id),
        isNot(contains('edit_nota_0')),
        reason: 'as partes antigas foram trocadas',
      );
      expect(after.map((p) => p.paymentGroupId).toSet(), hasLength(1));
      expect(after.first.paymentGroupId, isNotNull);
    },
  );

  testWidgets('Desligar a divisão ao editar volta a nota para uma despesa só', (
    tester,
  ) async {
    final cubit = sl<FinanceCubit>();
    await cubit.loadCycleData();
    final methods = cubit.state.paymentMethods
        .where((m) => !m.isCreditCard)
        .take(2)
        .toList();

    final note = HouseExpense(
      id: 'undo_nota',
      title: 'Nota para desfazer',
      amount: const Money(9000),
      date: DateTime.now(),
      categoryId: cubit.state.categories.first.id,
      paidByMemberId: cubit.state.members.first.id,
      paymentMethodId: methods[0].id,
      splitRule: const SplitRule.percentage(null),
    );
    await cubit.addExpenseGroup(
      ExpensePaymentSplit.build(
        note: note,
        parts: [
          PaymentPart(paymentMethodId: methods[0].id, amountCents: 6000),
          PaymentPart(paymentMethodId: methods[1].id, amountCents: 3000),
        ],
        methods: {for (final m in cubit.state.paymentMethods) m.id: m},
        groupId: 'grp_undo',
        partId: (i) => 'undo_nota_$i',
      ),
    );
    final part = (await launchedWithTitle('Nota para desfazer')).firstWhere((p) => p.amount.cents == 6000);

    await pumpEdit(tester, cubit, part);
    final splitSwitch = find.byKey(const Key('payment_split_switch'));
    await tester.ensureVisible(splitSwitch);
    await tester.tap(splitSwitch);
    await tester.pumpAndSettle();
    await save(tester);

    final after = await launchedWithTitle('Nota para desfazer');
    expect(after, hasLength(1));
    expect(after.single.amount.cents, 9000);
    expect(after.single.paymentGroupId, isNull);
    expect(after.single.paymentMethodId, methods[0].id);
  });

  testWidgets('Uma despesa avulsa pode passar a ser paga com mais de um meio', (
    tester,
  ) async {
    final cubit = sl<FinanceCubit>();
    await cubit.loadCycleData();
    final methods = cubit.state.paymentMethods
        .where((m) => !m.isCreditCard)
        .take(2)
        .toList();

    final single = HouseExpense(
      id: 'single_nota',
      title: 'Avulsa para dividir',
      amount: const Money(12000),
      date: DateTime.now(),
      categoryId: cubit.state.categories.first.id,
      paidByMemberId: cubit.state.members.first.id,
      paymentMethodId: methods[0].id,
      splitRule: const SplitRule.percentage(null),
    );
    await cubit.addExpense(single);
    final saved = (await launchedWithTitle('Avulsa para dividir')).single;

    await pumpEdit(tester, cubit, saved);
    final splitSwitch = find.byKey(const Key('payment_split_switch'));
    await tester.ensureVisible(splitSwitch);
    await tester.tap(splitSwitch);
    await tester.pumpAndSettle();
    final extraAmount = find.descendant(
      of: find.byKey(const Key('payment_split_amount_0')),
      matching: find.byType(TextField),
    );
    await tester.ensureVisible(extraAmount);
    await tester.enterText(extraAmount, '2000');
    await tester.pumpAndSettle();
    await save(tester);

    final after = await launchedWithTitle('Avulsa para dividir');
    expect(after.map((p) => p.amount.cents).toList()..sort(), [2000, 10000]);
    expect(after.map((p) => p.paymentGroupId).toSet(), hasLength(1));
  });
}
