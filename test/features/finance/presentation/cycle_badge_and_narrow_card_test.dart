import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/di/service_locator.dart';
import 'package:omni_lar/core/domain/value_objects/cycle_schedule.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/features/finance/domain/entities/financial_cycle_summary.dart';
import 'package:omni_lar/features/finance/domain/entities/house_expense.dart';
import 'package:omni_lar/features/finance/domain/entities/split_rule.dart';
import 'package:omni_lar/features/finance/presentation/cubit/finance_cubit.dart';
import 'package:omni_lar/features/finance/presentation/widgets/expense_timeline_item.dart';
import 'package:omni_lar/features/finance/presentation/widgets/folego_gauge_card.dart';

void main() {
  setUpAll(() async {
    if (!sl.isRegistered<FinanceCubit>()) {
      await initServiceLocator();
    }
  });

  group('Selo do cartão do Fôlego', () {
    final schedule = CycleSchedule(5);
    final current = schedule.cycleFor(DateTime.now());
    final past = schedule.previous(schedule.previous(current));

    Future<void> show(WidgetTester tester, {required bool currentCycle, bool? settled}) async {
      final cycle = currentCycle ? current : past;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: FolegoGaugeCard(
              summary: FinancialCycleSummary(
                cycle: cycle,
                totalContributions: const Money.zero(),
                totalExpensesPaid: const Money.zero(),
                committedFutureExpenses: const Money.zero(),
                folego: const Money.zero(),
                memberContributions: const {},
                memberExpensesPaid: const {},
              ),
              cycle: cycle,
              onPreviousCycle: () {},
              onNextCycle: () {},
              isCycleSettled: settled,
            ),
          ),
        ),
      ));
    }

    testWidgets('no ciclo atual mostra a saúde do caixa', (tester) async {
      await show(tester, currentCycle: true);
      expect(find.text('Saudável'), findsOneWidget);
    });

    testWidgets('em ciclo passado mostra se está fechado ou em aberto', (tester) async {
      await show(tester, currentCycle: false, settled: true);
      expect(find.text('Saudável'), findsNothing);
      expect(find.text('Fechado'), findsOneWidget);

      await show(tester, currentCycle: false, settled: false);
      expect(find.text('Em aberto'), findsOneWidget);

      // Enquanto a situação não chega, nenhum selo
      await show(tester, currentCycle: false);
      expect(find.byKey(const Key('folego_status_badge')), findsNothing);
    });
  });

  testWidgets('mostra saldo anterior e empréstimos que entram na conta do fôlego', (tester) async {
    final cycle = CycleSchedule(5).cycleFor(DateTime.now());
    Future<void> show({required Money loans, required Money folego}) => tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: FolegoGaugeCard(
                summary: FinancialCycleSummary(
                  cycle: cycle,
                  totalContributions: const Money.zero(),
                  totalExpensesPaid: const Money.zero(),
                  committedFutureExpenses: const Money(127758),
                  folego: folego,
                  memberContributions: const {},
                  memberExpensesPaid: const {},
                  houseLoansFunded: loans,
                ),
                cycle: cycle,
                onPreviousCycle: () {},
                onNextCycle: () {},
              ),
            ),
          ),
        ));

    // Sem sobra nem empréstimos, as linhas extras não aparecem
    await show(loans: const Money.zero(), folego: const Money(-127758));
    expect(find.byKey(const Key('folego_extra_metrics')), findsNothing);

    // -1.277,58 a vencer - 1.325,28 de empréstimos = -2.602,86
    await show(loans: const Money(132528), folego: const Money(-260286));
    expect(find.byKey(const Key('folego_extra_metrics')), findsOneWidget);
    expect(find.text('Empréstimos'), findsOneWidget);
    expect(find.text(const Money(132528).format()), findsOneWidget);
    expect(find.text('Saldo Anterior'), findsOneWidget);
  });

  testWidgets('em tela estreita o valor e o "Pagar" descem para baixo do título', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    final expense = HouseExpense(
      id: 'conta_estreita',
      title: 'Internet',
      amount: const Money(9990),
      date: DateTime.now(),
      dueDate: DateTime.now().add(const Duration(days: 5)),
      categoryId: 'cat_moradia',
      paymentMethodId: 'pm_caixa',
      paidByMemberId: 'member_carlos',
      splitRule: const SplitRule.percentage({'member_carlos': 60.0, 'member_marina': 40.0}),
      status: ExpenseStatus.pending,
    );

    Future<double> amountBelowTitleBy(double width) async {
      tester.view.physicalSize = Size(width, 800);
      await tester.pumpWidget(BlocProvider<FinanceCubit>.value(
        value: sl<FinanceCubit>(),
        child: MaterialApp(home: Scaffold(body: ExpenseTimelineItem(expense: expense))),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('expense_pay_conta_estreita')), findsOneWidget);
      return tester.getTopLeft(find.byKey(const Key('expense_amount_conta_estreita'))).dy -
          tester.getTopLeft(find.text('Internet')).dy;
    }

    expect(await amountBelowTitleBy(600), lessThan(10));
    expect(await amountBelowTitleBy(320), greaterThan(30));
  });
}
