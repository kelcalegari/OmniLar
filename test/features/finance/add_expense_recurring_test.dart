import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:omni_lar/core/di/service_locator.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/features/finance/presentation/cubit/finance_cubit.dart';
import 'package:omni_lar/features/finance/presentation/pages/add_expense_page.dart';

void main() {
  setUpAll(() async {
    if (!sl.isRegistered<FinanceCubit>()) {
      await initServiceLocator();
    }
  });

  Widget buildAddExpensePage({bool isRecurringDefault = false}) {
    return BlocProvider<FinanceCubit>.value(
      value: sl<FinanceCubit>(),
      child: MaterialApp(
        home: AddExpensePage(isRecurringDefault: isRecurringDefault),
      ),
    );
  }

  group('AddExpensePage - Despesas Recorrentes (Fixas e Variáveis)', () {
    testWidgets('Exibe switch de recorrência e opções de Fixa/Variável quando ativado', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await sl<FinanceCubit>().loadCycleData();

      await tester.pumpWidget(buildAddExpensePage());
      await tester.pumpAndSettle();

      // Switch de recorrência visível
      final switchFinder = find.text('Repetir todo mês (Recorrente)');
      expect(switchFinder, findsOneWidget);

      // Clica no switch para ativar recorrência
      await tester.tap(switchFinder);
      await tester.pumpAndSettle();

      // Opções expandidas
      expect(find.text('Valor Fixo'), findsOneWidget);
      expect(find.text('Valor Variável'), findsOneWidget);
      expect(find.text('Dia do Vencimento'), findsOneWidget);
      expect(find.text('Situação no Ciclo Atual'), findsOneWidget);
      expect(find.text('Salvar Despesa Recorrente'), findsOneWidget);
    });

    testWidgets('Inicia diretamente no modo recorrente quando isRecurringDefault for true', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await sl<FinanceCubit>().loadCycleData();

      await tester.pumpWidget(buildAddExpensePage(isRecurringDefault: true));
      await tester.pumpAndSettle();

      expect(find.text('Nova Despesa Recorrente'), findsOneWidget);
      expect(find.text('Valor Fixo'), findsOneWidget);
      expect(find.text('Valor Variável'), findsOneWidget);
      expect(find.text('Salvar Despesa Recorrente'), findsOneWidget);
    });

    testWidgets('Pode cadastrar uma conta de consumo variável como a vencer', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final cubit = sl<FinanceCubit>();
      await cubit.loadCycleData();

      await tester.pumpWidget(buildAddExpensePage(isRecurringDefault: true));
      await tester.pumpAndSettle();

      // Digita o valor
      await tester.enterText(find.byType(TextField).first, '18550'); // R$ 185,50
      await tester.pumpAndSettle();

      // Digita o título
      await tester.enterText(find.widgetWithText(TextField, 'O que foi pago?'), 'Conta de Gás');
      await tester.pumpAndSettle();

      // Seleciona Valor Variável
      await tester.tap(find.text('Valor Variável'));
      await tester.pumpAndSettle();

      // Salva
      await tester.tap(find.text('Salvar Despesa Recorrente'));
      await tester.pumpAndSettle();

      // Verifica no estado
      final added = cubit.state.expenses.firstWhere((e) => e.title == 'Conta de Gás');
      expect(added.isRecurring, isTrue);
      expect(added.isVariable, isTrue);
      expect(added.isPending, isTrue);
      expect(added.amount.cents, equals(18550));

      // Pode marcar como paga
      await cubit.markExpenseAsPaid(added.id, actualAmount: const Money(19000));
      final updated = cubit.state.expenses.firstWhere((e) => e.id == added.id);
      expect(updated.isPaid, isTrue);
      expect(updated.amount.cents, equals(19000));
    });
  });
}
