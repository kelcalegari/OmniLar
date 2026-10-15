import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/di/service_locator.dart';
import 'package:omni_lar/core/errors/failures.dart';
import 'package:omni_lar/features/finance/data/datasources/mock_finance_datasource.dart';
import 'package:omni_lar/features/finance/data/repositories/finance_repository_impl.dart';
import 'package:omni_lar/features/finance/domain/entities/house_expense.dart';
import 'package:omni_lar/features/finance/presentation/cubit/finance_cubit.dart';
import 'package:omni_lar/features/finance/presentation/pages/add_expense_page.dart';

/// Fonte de demonstração em que gravar uma despesa falha, como sem conexão.
class _FailingDataSource extends MockFinanceDataSource {
  @override
  Future<void> addExpense(HouseExpense expense) async {
    throw const ServerFailure('sem conexão');
  }
}

void main() {
  setUpAll(() async {
    if (!sl.isRegistered<FinanceCubit>()) {
      await initServiceLocator();
    }
  });

  test('Gravar despesa diz se deu certo', () async {
    final ok = FinanceCubit(FinanceRepositoryImpl(MockFinanceDataSource()));
    final failing = FinanceCubit(FinanceRepositoryImpl(_FailingDataSource()));
    await ok.loadCycleData();
    await failing.loadCycleData();
    final expense = ok.state.expenses.first.copyWith(id: 'nova', title: 'Teste');

    expect(await ok.addExpense(expense), isTrue);
    expect(await failing.addExpense(expense), isFalse);
    expect(failing.state.errorMessage, contains('sem conexão'));
  });

  testWidgets('Despesa que não gravou: o formulário fica aberto e avisa a falha', (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final cubit = FinanceCubit(FinanceRepositoryImpl(_FailingDataSource()));
    await cubit.loadCycleData();

    await tester.pumpWidget(
      BlocProvider<FinanceCubit>.value(
        value: cubit,
        child: const MaterialApp(home: AddExpensePage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '5000');
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'O que foi pago?'), 'Mercado');
    await tester.pumpAndSettle();

    final submit = find.text('Lançar Gasto da Casa');
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();

    // Continua no formulário, com o aviso de falha e sem o de sucesso
    expect(find.byType(AddExpensePage), findsOneWidget);
    expect(find.textContaining('sem conexão'), findsOneWidget);
    expect(find.textContaining('lançado com sucesso'), findsNothing);
  });
}
