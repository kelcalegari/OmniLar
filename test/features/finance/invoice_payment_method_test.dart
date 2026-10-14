import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/di/service_locator.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/features/auth/presentation/cubit/auth_cubit.dart';
import 'package:omni_lar/features/finance/domain/entities/house_expense.dart';
import 'package:omni_lar/features/finance/domain/entities/split_rule.dart';
import 'package:omni_lar/features/finance/domain/repositories/finance_repository.dart';
import 'package:omni_lar/features/finance/presentation/cubit/finance_cubit.dart';
import 'package:omni_lar/features/finance/presentation/widgets/card_invoice_payment_sheet.dart';
import 'package:omni_lar/features/p2p/presentation/cubit/p2p_cubit.dart';
import 'package:omni_lar/features/reconciliation/presentation/pages/import_page.dart';

void main() {
  setUpAll(() async {
    if (!sl.isRegistered<AuthCubit>()) {
      await initServiceLocator();
    }
    await sl<AuthCubit>().signInDemo(memberId: 'member_carlos');
    await sl<FinanceCubit>().loadCycleData();
  });

  Future<void> payWith(WidgetTester tester, {required String id, String? option}) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final cubit = sl<FinanceCubit>();
    final card = cubit.state.paymentMethods.firstWhere((p) => p.id == 'pm_card_carlos');
    final due = DateTime.now().add(Duration(days: 40 + id.length));
    await tester.runAsync(() => cubit.addExpense(HouseExpense(
          id: id,
          title: 'Compra $id',
          amount: const Money(8000),
          date: DateTime.now(),
          dueDate: due,
          categoryId: 'cat_moradia',
          paymentMethodId: card.id,
          paidByMemberId: 'member_carlos',
          splitRule: const SplitRule.percentage({'member_carlos': 60.0, 'member_marina': 40.0}),
          status: ExpenseStatus.pending,
        )));

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CardInvoicePaymentSheet(
          card: card,
          initialDueDate: due,
          memberNames: const {'member_carlos': 'Carlos'},
          repository: sl<FinanceRepository>(),
          financeCubit: cubit,
          cycleSchedule: cubit.cycleSchedule,
          isCycleClosed: (_) async => false,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final dropdown = find.byKey(const Key('invoice_payment_method'));
    expect(dropdown, findsOneWidget);
    if (option != null) {
      await tester.tap(dropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining(option).last);
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('Registrar pagamento'));
    await tester.pumpAndSettle();
  }

  HouseExpense saved(String id) =>
      sl<FinanceCubit>().state.expenses.firstWhere((e) => e.id == id, orElse: () => throw 'sem $id');

  Future<HouseExpense> stored(WidgetTester tester, String id) async {
    final repository = sl<FinanceRepository>();
    final cycle = sl<FinanceCubit>().cycleSchedule.cycleFor(DateTime.now());
    final rows = (await tester.runAsync(() => repository.getExpensesForCycle(cycle)))!;
    return rows.where((e) => e.id == id).firstOrNull ?? saved(id);
  }

  testWidgets('pagar a fatura com o meio do titular: ele é reembolsado', (tester) async {
    await payWith(tester, id: 'fatura_titular');
    final expense = await stored(tester, 'fatura_titular');
    expect(expense.paidAt, isNotNull);
    expect(expense.paidOutOfPocket, isTrue);
  });

  testWidgets('pagar a fatura com um meio da casa: sai do Caixa, sem reembolso', (tester) async {
    await payWith(tester, id: 'fatura_casa_x', option: '(da casa)');
    final expense = await stored(tester, 'fatura_casa_x');
    expect(expense.paidAt, isNotNull);
    expect(expense.paidOutOfPocket, isFalse);
  });

  testWidgets('importação: "Fatura já paga?" com meio da casa marca pago pelo Caixa', (tester) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MultiBlocProvider(
      providers: [
        BlocProvider<FinanceCubit>.value(value: sl<FinanceCubit>()),
        BlocProvider<P2PCubit>.value(value: sl<P2PCubit>()),
      ],
      child: const MaterialApp(home: ImportPage(initialSourceId: 'pm_card_carlos')),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Usar fatura de exemplo'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Fatura já paga?'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    // O titular e os meios da casa aparecem; o de outra moradora, não
    expect(find.text('Com que meio foi paga?'), findsOneWidget);
    expect(find.textContaining('reembolsado no fechamento'), findsWidgets);
    expect(find.textContaining('Marina'), findsNothing);
    await tester.tap(find.textContaining('(da casa)').first);
    await tester.pumpAndSettle();

    expect(find.textContaining('pelo Caixa'), findsOneWidget);
  });
}
