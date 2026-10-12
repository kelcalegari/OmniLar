import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mocktail/mocktail.dart';
import 'package:omni_lar/core/domain/value_objects/financial_cycle.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/core/di/service_locator.dart';
import 'package:omni_lar/features/finance/domain/entities/house_expense.dart';
import 'package:omni_lar/features/finance/domain/entities/split_rule.dart';
import 'package:omni_lar/features/finance/domain/repositories/finance_repository.dart';
import 'package:omni_lar/features/finance/presentation/cubit/finance_cubit.dart';
import 'package:omni_lar/features/finance/presentation/pages/add_expense_page.dart';

class MockFinanceRepository extends Mock implements FinanceRepository {}

void main() {
  setUpAll(() async {
    registerFallbackValue(
      FinancialCycle.fromDate(date: DateTime.now(), cycleStartDay: 5),
    );
    registerFallbackValue(
      HouseExpense(
        id: 'fallback',
        title: 'fallback',
        amount: const Money(100),
        date: DateTime.now(),
        categoryId: '',
        paidByMemberId: '',
        paymentMethodId: '',
        splitRule: const SplitRule.percentage({}),
      ),
    );
    if (!sl.isRegistered<FinanceCubit>()) {
      await initServiceLocator();
    }
  });

  testWidgets('AddExpensePage não lança StateError No element quando categories está vazia', (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final mockRepo = MockFinanceRepository();
    when(() => mockRepo.getCategories()).thenAnswer((_) async => []);
    when(() => mockRepo.getMembers()).thenAnswer((_) async => []);
    when(() => mockRepo.getPaymentMethods()).thenAnswer((_) async => []);
    when(() => mockRepo.getCycleSummary(any())).thenAnswer((_) async => throw Exception('summary error'));
    when(() => mockRepo.getExpensesForCycle(any())).thenAnswer((_) async => []);
    when(() => mockRepo.getContributionsForCycle(any())).thenAnswer((_) async => []);
    when(() => mockRepo.getSavingsVaults()).thenAnswer((_) async => []);
    when(() => mockRepo.addExpense(any())).thenAnswer((_) async {});

    final cubit = FinanceCubit(mockRepo);
    await cubit.loadCycleData(
      cycle: FinancialCycle.fromDate(date: DateTime.now(), cycleStartDay: 5),
    );

    // Garante que cubit possui categorias vazias
    expect(cubit.state.categories, isEmpty);

    await tester.pumpWidget(
      BlocProvider<FinanceCubit>.value(
        value: cubit,
        child: const MaterialApp(
          home: AddExpensePage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Deve exibir aviso amigável de categorias vazias sem quebrar
    expect(find.text('Nenhuma categoria encontrada. Uma categoria geral será atribuída.'), findsOneWidget);

    // Preenche valor e descrição
    await tester.enterText(find.byType(TextField).first, '5000'); // R$ 50,00
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'O que foi pago?'), 'Mercado Sem Categoria');
    await tester.pumpAndSettle();

    // Clica em lançar despesa
    final submitButton = find.text('Lançar Gasto da Casa');
    await tester.ensureVisible(submitButton);
    await tester.tap(submitButton);
    await tester.pumpAndSettle();

    // Verifica que addExpense foi chamado com sucesso no repositório sem lançar exceção
    verify(() => mockRepo.addExpense(any())).called(1);
  });
}
