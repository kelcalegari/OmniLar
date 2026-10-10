import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:omni_lar/core/di/service_locator.dart';
import 'package:omni_lar/features/auth/presentation/cubit/auth_cubit.dart';
import 'package:omni_lar/features/calendar/presentation/cubit/calendar_cubit.dart';
import 'package:omni_lar/features/calendar/presentation/pages/calendar_page.dart';
import 'package:omni_lar/features/calendar/presentation/widgets/mini_calendar_card.dart';
import 'package:omni_lar/features/calendar/presentation/widgets/month_calendar_view.dart';
import 'package:omni_lar/features/calendar/presentation/widgets/week_calendar_view.dart';

void main() {
  setUpAll(() async {
    if (!sl.isRegistered<CalendarCubit>()) {
      await initServiceLocator();
    }
  });

  Widget buildCalendarPage() {
    return MultiBlocProvider(
      providers: [
        BlocProvider.value(value: sl<CalendarCubit>()),
        BlocProvider.value(value: sl<AuthCubit>()),
      ],
      child: const MaterialApp(
        home: CalendarPage(),
      ),
    );
  }

  group('CalendarPage - Visões de Mês e Lista no Mobile, e 4 Modos no Desktop', () {
    testWidgets('No Mobile (800x1400), inicia na Visão Mês com calendário e compromissos do dia',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildCalendarPage());
      await tester.pumpAndSettle();

      // No mobile, apenas Mês e Lista estão disponíveis (Dia e Semana removidos)
      expect(find.text('Mês'), findsOneWidget);
      expect(find.text('Lista'), findsOneWidget);
      expect(find.text('Dia'), findsNothing);
      expect(find.text('Semana'), findsNothing);

      // Grade mensal elegante presente
      expect(find.byType(MonthCalendarView), findsOneWidget);

      // Compromissos do dia selecionado exibidos logo abaixo do calendário
      expect(find.textContaining('Compromissos ('), findsOneWidget);
      expect(find.text('Tarefas'), findsNothing);
    });

    testWidgets('No Mobile, ao tocar em um dia da grade, atualiza a agenda do dia mantendo o calendário',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildCalendarPage());
      await tester.pumpAndSettle();

      expect(find.byType(MonthCalendarView), findsOneWidget);

      // Clica em um dia da grade do mês (ex: dia 15)
      final dayCell = find.descendant(
        of: find.byType(MonthCalendarView),
        matching: find.text('15'),
      );
      expect(dayCell, findsWidgets);
      await tester.tap(dayCell.first);
      await tester.pumpAndSettle();

      // Permanece na visão com calendário e atualiza a lista de compromissos do dia
      expect(find.byType(MonthCalendarView), findsOneWidget);
      expect(find.textContaining('Compromissos ('), findsOneWidget);
    });

    testWidgets('No Mobile, alterna para Visão Lista e renderiza calendário e lista de todos os compromissos',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildCalendarPage());
      await tester.pumpAndSettle();

      // Alterna para Lista
      await tester.tap(find.text('Lista'));
      await tester.pumpAndSettle();

      // Calendário e lista corrida de compromissos
      expect(find.byType(MonthCalendarView), findsOneWidget);
      expect(find.textContaining('Todos os Compromissos ('), findsOneWidget);
    });

    testWidgets('Em Desktop (1280x800), permite alternar entre Dia, Semana, Mês e Lista',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildCalendarPage());
      await tester.pumpAndSettle();

      // No Desktop, botões têm labels "Visão Dia", "Visão Semana", etc.
      expect(find.text('Visão Dia'), findsOneWidget);
      expect(find.text('Visão Semana'), findsOneWidget);
      expect(find.text('Visão Mês'), findsOneWidget);
      expect(find.text('Visão Lista'), findsOneWidget);

      // Alterna para Visão Mês no Desktop
      await tester.tap(find.text('Visão Mês'));
      await tester.pumpAndSettle();
      expect(find.byType(MonthCalendarView), findsOneWidget);

      // Alterna para Visão Semana no Desktop
      await tester.tap(find.text('Visão Semana'));
      await tester.pumpAndSettle();
      expect(find.byType(WeekCalendarView), findsOneWidget);

      // Alterna para Visão Lista no Desktop
      await tester.tap(find.text('Visão Lista'));
      await tester.pumpAndSettle();
      expect(find.byType(MiniCalendarCard), findsOneWidget);
      expect(find.textContaining('Todos os Compromissos ('), findsOneWidget);
    });

    testWidgets('Navegação de períodos via chevrons e botão Hoje',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildCalendarPage());
      await tester.pumpAndSettle();

      // Navegar para período anterior
      final prevBtn = find.byTooltip('Anterior');
      expect(prevBtn, findsOneWidget);
      await tester.tap(prevBtn);
      await tester.pumpAndSettle();

      // Botão de retornar para Hoje fica disponível
      expect(find.widgetWithText(TextButton, 'Hoje'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Hoje'));
      await tester.pumpAndSettle();
    });
  });
}
