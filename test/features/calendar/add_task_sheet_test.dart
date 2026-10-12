import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:omni_lar/core/di/service_locator.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/core/widgets/money_input_field.dart';
import 'package:omni_lar/features/calendar/presentation/cubit/calendar_cubit.dart';
import 'package:omni_lar/features/calendar/presentation/widgets/add_task_sheet.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('pt_BR', null);
    if (!sl.isRegistered<CalendarCubit>()) {
      await initServiceLocator();
    }
  });

  group('AddTaskSheet - Formatação ATM de Custo Estimado', () {
    testWidgets('Campo Custo estimado formata 1 -> 0,01 e salva tarefa com valor correto', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final cubit = sl<CalendarCubit>();
      await cubit.loadCalendarData();
      final initialCount = cubit.state.tasks.length;

      await tester.pumpWidget(
        BlocProvider<CalendarCubit>.value(
          value: cubit,
          child: MaterialApp(
            home: Builder(
              builder: (ctx) => Scaffold(
                body: ElevatedButton(
                  onPressed: () => AddTaskSheet.show(ctx, 'member_carlos'),
                  child: const Text('Abrir'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();

      expect(find.text('Nova Tarefa do Lar'), findsOneWidget);
      expect(find.text('Custo estimado (opcional)'), findsOneWidget);
      expect(find.byType(MoneyTextFormField), findsOneWidget);

      // Preenche título
      final titleField = find.widgetWithText(TextFormField, 'O que precisa ser feito? *');
      await tester.enterText(titleField, 'Trocar torneira do banheiro');
      await tester.pumpAndSettle();

      // Encontra o campo de custo (TextField interno do MoneyTextFormField)
      final costTextField = find.descendant(
        of: find.byType(MoneyTextFormField),
        matching: find.byType(TextField),
      );

      // Digita '1' -> deve virar R$ 0,01
      await tester.enterText(costTextField, '1');
      await tester.pumpAndSettle();
      expect(find.text(const Money(1).format()), findsOneWidget);

      // Digita '5' -> deve virar R$ 0,15
      final currentFormatted1 = const Money(1).format();
      await tester.enterText(costTextField, '${currentFormatted1}5');
      await tester.pumpAndSettle();
      expect(find.text(const Money(15).format()), findsOneWidget);

      // Digita '0' -> deve virar R$ 1,50
      final currentFormatted2 = const Money(15).format();
      await tester.enterText(costTextField, '${currentFormatted2}0');
      await tester.pumpAndSettle();
      expect(find.text(const Money(150).format()), findsOneWidget);

      // Digita '0' -> deve virar R$ 15,00
      final currentFormatted3 = const Money(150).format();
      await tester.enterText(costTextField, '${currentFormatted3}0');
      await tester.pumpAndSettle();
      expect(find.text(const Money(1500).format()), findsOneWidget);

      // Salva a tarefa
      await tester.tap(find.text('Salvar Tarefa'));
      await tester.pumpAndSettle();

      // Tarefa foi adicionada com cost = Money(1500)
      expect(cubit.state.tasks.length, equals(initialCount + 1));
      final created = cubit.state.tasks.firstWhere((t) => t.title == 'Trocar torneira do banheiro');
      expect(created.cost, isNotNull);
      expect(created.cost?.cents, equals(1500));
    });

    testWidgets('Salva tarefa com campo de custo opcional vazio sem lançar custo', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final cubit = sl<CalendarCubit>();
      final initialCount = cubit.state.tasks.length;

      await tester.pumpWidget(
        BlocProvider<CalendarCubit>.value(
          value: cubit,
          child: MaterialApp(
            home: Builder(
              builder: (ctx) => Scaffold(
                body: ElevatedButton(
                  onPressed: () => AddTaskSheet.show(ctx, 'member_carlos'),
                  child: const Text('Abrir'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();

      final titleField = find.widgetWithText(TextFormField, 'O que precisa ser feito? *');
      await tester.enterText(titleField, 'Varrer a varanda');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Salvar Tarefa'));
      await tester.pumpAndSettle();

      expect(cubit.state.tasks.length, equals(initialCount + 1));
      final created = cubit.state.tasks.firstWhere((t) => t.title == 'Varrer a varanda');
      expect(created.cost, isNull);
    });

    testWidgets('Traz todos os integrantes da casa como opção de responsável', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        BlocProvider<CalendarCubit>.value(
          value: sl<CalendarCubit>(),
          child: MaterialApp(
            home: Builder(
              builder: (ctx) => Scaffold(
                body: ElevatedButton(
                  onPressed: () => AddTaskSheet.show(ctx, 'member_carlos'),
                  child: const Text('Abrir'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();

      // Confirma que os integrantes da casa estão disponíveis
      expect(find.text('Responsável pela Tarefa:'), findsOneWidget);
      expect(find.text('Carlos'), findsOneWidget);
      expect(find.text('Marina'), findsOneWidget);
      expect(find.text('Qualquer um'), findsOneWidget);
    });
  });
}
