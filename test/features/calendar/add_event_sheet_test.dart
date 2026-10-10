import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:omni_lar/core/di/service_locator.dart';
import 'package:omni_lar/features/calendar/domain/entities/calendar_event.dart';
import 'package:omni_lar/features/calendar/presentation/cubit/calendar_cubit.dart';
import 'package:omni_lar/features/calendar/presentation/widgets/add_event_sheet.dart';

void main() {
  setUpAll(() async {
    if (!sl.isRegistered<CalendarCubit>()) {
      await initServiceLocator();
    }
  });

  group('AddEventSheet - Submissão e Fechamento', () {
    testWidgets('Preenche título e salva novo evento com sucesso fechando o modal', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final cubit = sl<CalendarCubit>();
      await cubit.loadCalendarData();
      final initialCount = cubit.state.events.length;

      await tester.pumpWidget(
        BlocProvider<CalendarCubit>.value(
          value: cubit,
          child: const MaterialApp(
            home: Scaffold(
              body: AddEventSheet(activeMemberId: 'member_carlos'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Novo Compromisso'), findsOneWidget);
      expect(find.text('Salvar Compromisso'), findsOneWidget);

      // Digita o título
      final titleField = find.byType(TextFormField).first;
      await tester.enterText(titleField, 'Churrasco com os Amigos');
      await tester.pumpAndSettle();

      // Clica em Salvar
      await tester.tap(find.text('Salvar Compromisso'));
      await tester.pumpAndSettle();

      // Verifica se o evento foi adicionado ao cubit
      expect(cubit.state.events.length, equals(initialCount + 1));
      expect(cubit.state.events.any((e) => e.title == 'Churrasco com os Amigos'), isTrue);
    });

    testWidgets('Salva edição de evento existente com initialEvent', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final cubit = sl<CalendarCubit>();
      await cubit.loadCalendarData();

      final existingEvent = CalendarEvent(
        id: 'test_edit_123',
        title: 'Consulta Médica Original',
        startTime: DateTime.now().add(const Duration(days: 1)),
        endTime: DateTime.now().add(const Duration(days: 1, hours: 1)),
        createdByMemberId: 'member_carlos',
      );
      await cubit.addEvent(existingEvent);

      await tester.pumpWidget(
        BlocProvider<CalendarCubit>.value(
          value: cubit,
          child: MaterialApp(
            home: Scaffold(
              body: AddEventSheet(
                activeMemberId: 'member_carlos',
                initialEvent: existingEvent,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Editar Compromisso'), findsOneWidget);
      expect(find.text('Salvar Alterações'), findsOneWidget);

      // Altera o título
      final titleField = find.byType(TextFormField).first;
      await tester.enterText(titleField, 'Consulta Médica Reagendada');
      await tester.pumpAndSettle();

      // Clica em Salvar Alterações
      await tester.tap(find.text('Salvar Alterações'));
      await tester.pumpAndSettle();

      // Verifica se o título foi atualizado
      expect(cubit.state.events.any((e) => e.title == 'Consulta Médica Reagendada'), isTrue);
    });
  });
}
