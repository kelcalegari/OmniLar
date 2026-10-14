import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/di/service_locator.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/features/capture/domain/services/boleto_code.dart';
import 'package:omni_lar/features/finance/domain/entities/house_expense.dart';
import 'package:omni_lar/features/finance/domain/entities/split_rule.dart';
import 'package:omni_lar/features/finance/presentation/cubit/finance_cubit.dart';
import 'package:omni_lar/features/finance/presentation/pages/add_expense_page.dart';
import 'package:omni_lar/features/finance/presentation/widgets/expense_timeline_item.dart';

/// Código de barras de boleto bancário válido, com [cents] e fator [factor].
String _bankBarcode({int cents = 12345, int factor = 1500}) {
  final rest = '${factor.toString().padLeft(4, '0')}${cents.toString().padLeft(10, '0')}${'1' * 25}';
  final digit = BoletoCodeReader.bankGeneralDigit('0019$rest');
  return '0019$digit$rest';
}

void main() {
  setUpAll(() async {
    if (!sl.isRegistered<FinanceCubit>()) {
      await initServiceLocator();
    }
  });

  testWidgets('código colado no formulário é conferido e preenche o valor', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    await sl<FinanceCubit>().loadCycleData();

    await tester.pumpWidget(BlocProvider<FinanceCubit>.value(
      value: sl<FinanceCubit>(),
      child: const MaterialApp(home: AddExpensePage()),
    ));
    await tester.pumpAndSettle();

    final field = find.byKey(const Key('expense_barcode'));
    await tester.ensureVisible(field);
    await tester.enterText(field, _bankBarcode());
    await tester.pumpAndSettle();

    expect(find.textContaining('Código conferido'), findsOneWidget);
    expect(find.textContaining(const Money(12345).format()), findsWidgets);

    // Erro de digitação: o dígito verificador não confere
    final wrong = _bankBarcode().replaceRange(30, 31, _bankBarcode()[30] == '1' ? '2' : '1');
    await tester.enterText(field, wrong);
    await tester.pumpAndSettle();
    expect(find.textContaining('não confere'), findsOneWidget);
  });

  testWidgets('conta pendente com código mostra o botão de copiar', (tester) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    HouseExpense bill({String? barcode, ExpenseStatus status = ExpenseStatus.pending}) => HouseExpense(
          id: 'boleto_copiar',
          title: 'Internet',
          amount: const Money(9990),
          date: DateTime.now(),
          dueDate: DateTime.now().add(const Duration(days: 5)),
          categoryId: 'cat_moradia',
          paymentMethodId: 'pm_caixa',
          paidByMemberId: 'member_carlos',
          splitRule: const SplitRule.percentage({'member_carlos': 60.0, 'member_marina': 40.0}),
          status: status,
          barcode: barcode,
        );

    Future<void> show(HouseExpense expense) async {
      await tester.pumpWidget(BlocProvider<FinanceCubit>.value(
        value: sl<FinanceCubit>(),
        child: MaterialApp(home: Scaffold(body: ExpenseTimelineItem(expense: expense))),
      ));
      await tester.pumpAndSettle();
    }

    final copy = find.byKey(const Key('copy_barcode_boleto_copiar'));
    await show(bill(barcode: BoletoCodeReader.read(_bankBarcode()).digitableLine));
    expect(copy, findsOneWidget);

    await show(bill());
    expect(copy, findsNothing);

    await show(bill(barcode: '123', status: ExpenseStatus.paid));
    expect(copy, findsNothing);
  });

  testWidgets('apagar o código ao editar remove o código da conta', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final cubit = sl<FinanceCubit>();
    await cubit.loadCycleData();
    final line = BoletoCodeReader.read(_bankBarcode()).digitableLine;
    await cubit.addExpense(HouseExpense(
      id: 'boleto_apagar',
      title: 'Boleto com código',
      amount: const Money(12345),
      date: DateTime.now(),
      dueDate: DateTime.now().add(const Duration(days: 3)),
      categoryId: 'cat_moradia',
      paymentMethodId: 'pm_caixa',
      paidByMemberId: 'member_carlos',
      splitRule: const SplitRule.percentage({'member_carlos': 60.0, 'member_marina': 40.0}),
      status: ExpenseStatus.pending,
      barcode: line,
    ));
    final saved = cubit.state.expenses.firstWhere((e) => e.id == 'boleto_apagar');
    expect(saved.barcode, line);

    await tester.pumpWidget(BlocProvider<FinanceCubit>.value(
      value: cubit,
      child: MaterialApp(home: Scaffold(body: AddExpensePage(expenseToEdit: saved))),
    ));
    await tester.pumpAndSettle();

    final field = find.byKey(const Key('expense_barcode'));
    await tester.ensureVisible(field);
    await tester.enterText(field, '');
    await tester.pumpAndSettle();

    final save = find.text('Salvar Alterações');
    await tester.scrollUntilVisible(save, 300, scrollable: find.byType(Scrollable).first);
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(cubit.state.expenses.firstWhere((e) => e.id == 'boleto_apagar').barcode, isNull);
  });
}
