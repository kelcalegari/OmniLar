import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:omni_lar/core/di/service_locator.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/core/domain/value_objects/financial_cycle.dart';
import 'package:omni_lar/features/finance/data/datasources/mock_finance_datasource.dart';
import 'package:omni_lar/features/finance/domain/entities/house_expense.dart';
import 'package:omni_lar/features/finance/domain/entities/split_rule.dart';
import 'package:omni_lar/features/finance/presentation/cubit/finance_cubit.dart';
import 'package:omni_lar/features/finance/presentation/pages/add_expense_page.dart';
import 'package:omni_lar/features/finance/presentation/widgets/expense_timeline_item.dart';

void main() {
  setUpAll(() async {
    if (!sl.isRegistered<FinanceCubit>()) {
      await initServiceLocator();
    }
  });

  group('HouseExpense - Regras de Atraso e Vencimento Retroativo', () {
    test('Calcula isOverdue e daysOverdue corretamente para despesa pendente passada', () {
      final pastDate = DateTime.now().subtract(const Duration(days: 10));
      final expense = HouseExpense(
        id: 'exp-retro-1',
        title: 'Boleto Atrasado',
        amount: const Money(15000),
        date: pastDate,
        dueDate: pastDate,
        categoryId: 'cat_moradia',
        paymentMethodId: 'pm_caixa',
        paidByMemberId: 'member_carlos',
        splitRule: const SplitRule.percentage({'member_carlos': 60.0, 'member_marina': 40.0}),
        status: ExpenseStatus.pending,
      );

      expect(expense.isOverdue, isTrue);
      expect(expense.daysOverdue, greaterThanOrEqualTo(9));
      expect(expense.effectiveDueDate, pastDate);
    });

    test('isOverdue é false se a despesa já estiver paga, mesmo com data no passado', () {
      final pastDate = DateTime.now().subtract(const Duration(days: 15));
      final expense = HouseExpense(
        id: 'exp-retro-2',
        title: 'Boleto Quitado',
        amount: const Money(15000),
        date: pastDate,
        dueDate: pastDate,
        categoryId: 'cat_moradia',
        paymentMethodId: 'pm_caixa',
        paidByMemberId: 'member_carlos',
        splitRule: const SplitRule.percentage({'member_carlos': 60.0, 'member_marina': 40.0}),
        status: ExpenseStatus.paid,
      );

      expect(expense.isOverdue, isFalse);
      expect(expense.daysOverdue, 0);
    });

    test('isOverdue é false para despesa com vencimento no futuro', () {
      final futureDate = DateTime.now().add(const Duration(days: 5));
      final expense = HouseExpense(
        id: 'exp-fut-1',
        title: 'Conta Futura',
        amount: const Money(10000),
        date: DateTime.now(),
        dueDate: futureDate,
        categoryId: 'cat_moradia',
        paymentMethodId: 'pm_caixa',
        paidByMemberId: 'member_carlos',
        splitRule: const SplitRule.percentage({'member_carlos': 60.0, 'member_marina': 40.0}),
        status: ExpenseStatus.pending,
      );

      expect(expense.isOverdue, isFalse);
      expect(expense.daysOverdue, 0);
    });
  });

  group('MockFinanceDataSource - Carry-forward de Contas Atrasadas', () {
    late MockFinanceDataSource dataSource;

    setUp(() {
      dataSource = MockFinanceDataSource();
    });

    test('Inclui despesa pendente de ciclo passado nos compromissos do ciclo atual', () async {
      final currentCycle = FinancialCycle.fromDate(date: DateTime.now(), cycleStartDay: 5);
      final pastCycleDate = currentCycle.startDate.subtract(const Duration(days: 20));

      final overdueExpense = HouseExpense(
        id: 'overdue-test-1',
        title: 'Energia Mês Passado',
        amount: const Money(35000),
        date: pastCycleDate,
        dueDate: pastCycleDate,
        categoryId: 'cat_servicos',
        paymentMethodId: 'pm_caixa',
        paidByMemberId: 'member_carlos',
        splitRule: const SplitRule.percentage({'member_carlos': 60.0, 'member_marina': 40.0}),
        status: ExpenseStatus.pending,
      );

      await dataSource.addExpense(overdueExpense);

      final cycleExpenses = await dataSource.getExpensesForCycle(currentCycle);
      expect(cycleExpenses.any((e) => e.id == 'overdue-test-1'), isTrue);

      // Quita a conta atrasada
      final updatedPaid = overdueExpense.copyWith(
        status: ExpenseStatus.paid,
        amount: const Money(35000),
        date: DateTime.now(),
      );
      await dataSource.updateExpense(updatedPaid);
      final updatedExpenses = await dataSource.getExpensesForCycle(currentCycle);
      final updated = updatedExpenses.firstWhere((e) => e.id == 'overdue-test-1');
      expect(updated.isPending, isFalse);
    });
  });

  group('AddExpensePage - Seleção Retroativa e Aviso de Atraso', () {
    Widget buildAddExpensePage() {
      return BlocProvider<FinanceCubit>.value(
        value: sl<FinanceCubit>(),
        child: const MaterialApp(
          home: AddExpensePage(),
        ),
      );
    }

    testWidgets('Exibe card de Data e Situação e opções de Pago / Pendente', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await sl<FinanceCubit>().loadCycleData();

      await tester.pumpWidget(buildAddExpensePage());
      await tester.pumpAndSettle();

      // Card de data e status está presente
      expect(find.text('Situação no Ciclo Atual'), findsOneWidget);
      expect(find.text('Já Paga'), findsOneWidget);
      expect(find.text('A Vencer'), findsOneWidget);

      // Clica em 'A Vencer'
      await tester.tap(find.text('A Vencer'));
      await tester.pumpAndSettle();

      // Verifica que o estado foi atualizado e agora o título é Data de Vencimento
      expect(find.text('Data de Vencimento'), findsOneWidget);
    });
  });

  group('ExpenseTimelineItem - Renderização de Badge Vencida/Atrasada', () {
    testWidgets('Exibe badge "Atrasada" quando despesa está vencida e pendente', (tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final overdueExpense = HouseExpense(
        id: 'exp-timeline-overdue',
        title: 'Condomínio Atrasado',
        amount: const Money(45000),
        date: DateTime.now().subtract(const Duration(days: 7)),
        dueDate: DateTime.now().subtract(const Duration(days: 7)),
        categoryId: 'cat_moradia',
        paymentMethodId: 'pm_caixa',
        paidByMemberId: 'member_carlos',
        splitRule: const SplitRule.percentage({'member_carlos': 60.0, 'member_marina': 40.0}),
        status: ExpenseStatus.pending,
      );

      await tester.pumpWidget(
        BlocProvider<FinanceCubit>.value(
          value: sl<FinanceCubit>(),
          child: MaterialApp(
            home: Scaffold(
              body: ExpenseTimelineItem(expense: overdueExpense),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Deve exibir badge de atraso
      expect(find.textContaining('Atrasada (7d)'), findsOneWidget);
      expect(find.text('Pagar'), findsOneWidget);
    });

    testWidgets('Exibe "A vencer" quando pendente mas ainda no prazo', (tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final upcomingExpense = HouseExpense(
        id: 'exp-timeline-upcoming',
        title: 'Internet do Mês',
        amount: const Money(12000),
        date: DateTime.now(),
        dueDate: DateTime.now().add(const Duration(days: 10)),
        categoryId: 'cat_servicos',
        paymentMethodId: 'pm_caixa',
        paidByMemberId: 'member_carlos',
        splitRule: const SplitRule.percentage({'member_carlos': 60.0, 'member_marina': 40.0}),
        status: ExpenseStatus.pending,
      );

      await tester.pumpWidget(
        BlocProvider<FinanceCubit>.value(
          value: sl<FinanceCubit>(),
          child: MaterialApp(
            home: Scaffold(
              body: ExpenseTimelineItem(expense: upcomingExpense),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('A vencer'), findsOneWidget);
      expect(find.text('Pagar'), findsOneWidget);
    });
  });
}
