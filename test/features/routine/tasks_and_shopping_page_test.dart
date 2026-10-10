import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:omni_lar/core/di/service_locator.dart';
import 'package:omni_lar/features/auth/presentation/cubit/auth_cubit.dart';
import 'package:omni_lar/features/calendar/presentation/cubit/calendar_cubit.dart';
import 'package:omni_lar/features/finance/presentation/cubit/finance_cubit.dart';
import 'package:omni_lar/features/routine/presentation/pages/tasks_and_shopping_page.dart';
import 'package:omni_lar/features/shopping/presentation/cubit/shopping_cubit.dart';

void main() {
  setUpAll(() async {
    if (!sl.isRegistered<ShoppingCubit>() || !sl.isRegistered<CalendarCubit>()) {
      await initServiceLocator();
    }
  });

  Widget buildTasksAndShoppingPage({int initialTab = 0}) {
    return MultiBlocProvider(
      providers: [
        BlocProvider.value(value: sl<CalendarCubit>()),
        BlocProvider.value(value: sl<ShoppingCubit>()),
        BlocProvider.value(value: sl<FinanceCubit>()),
        BlocProvider.value(value: sl<AuthCubit>()),
      ],
      child: MaterialApp(
        home: TasksAndShoppingPage(initialTabIndex: initialTab),
      ),
    );
  }

  group('TasksAndShoppingPage - Seção Separada de Tarefas & Compras', () {
    testWidgets('Renderiza abas de Tarefas da Casa e Lista de Compras',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildTasksAndShoppingPage());
      await tester.pumpAndSettle();

      // Verifica abas
      expect(find.textContaining('Tarefas da Casa ('), findsOneWidget);
      expect(find.textContaining('Lista de Compras ('), findsOneWidget);

      // Na aba Tarefas (padrão)
      expect(find.text('Nova Tarefa'), findsOneWidget);
      expect(find.byType(ChoiceChip), findsWidgets);
    });

    testWidgets('Pode alternar para a aba Lista de Compras e adicionar item',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildTasksAndShoppingPage());
      await tester.pumpAndSettle();

      // Clica na aba Lista de Compras
      await tester.tap(find.textContaining('Lista de Compras ('));
      await tester.pumpAndSettle();

      // Campo de adicionar à lista deve estar visível
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Adicionar'), findsOneWidget);

      // Digita um novo item
      await tester.enterText(find.byType(TextField), 'Leite Desnatado');
      await tester.tap(find.text('Adicionar'));
      await tester.pumpAndSettle();

      // O item deve aparecer na lista
      expect(find.text('Leite Desnatado'), findsOneWidget);
    });

    testWidgets('Aba Tarefas permite alternar filtros e marcar conclusão',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildTasksAndShoppingPage(initialTab: 0));
      await tester.pumpAndSettle();

      // Filtra por Concluídas
      await tester.tap(find.textContaining('Concluídas ('));
      await tester.pumpAndSettle();

      // Filtra por Pendentes
      await tester.tap(find.textContaining('Pendentes ('));
      await tester.pumpAndSettle();

      // Deve encontrar checkboxes de tarefas
      expect(find.byType(Checkbox), findsWidgets);
    });
  });
}
