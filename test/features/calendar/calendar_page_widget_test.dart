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

  group('CalendarPage - Visões de Dia, Semana, Mês e Lista', () {
    testWidgets('Inicia na Visão Dia com Mini Calendário e sem Tarefas',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildCalendarPage());
      await tester.pumpAndSettle();

      // Botões de alternância de modo
      expect(find.text('Dia'), findsOneWidget);
      expect(find.text('Semana'), findsOneWidget);
      expect(find.text('Mês'), findsOneWidget);
      expect(find.text('Lista'), findsOneWidget);

      // Mini Calendário presente
      expect(find.byType(MiniCalendarCard), findsOneWidget);

      // Apenas compromissos na agenda, sem tarefas
      expect(find.text('Compromissos agendados'), findsOneWidget);
      expect(find.text('Tarefas'), findsNothing);
    });

    testWidgets('Alterna para Visão Semana e renderiza WeekCalendarView',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildCalendarPage());
      await tester.pumpAndSettle();

      // Alterna para Semana
      await tester.tap(find.text('Semana'));
      await tester.pumpAndSettle();

      // WeekCalendarView deve estar visível
      expect(find.byType(WeekCalendarView), findsOneWidget);
      expect(find.byType(MiniCalendarCard), findsNothing);
    });

    testWidgets('Alterna para Visão Mês e renderiza grade MonthCalendarView',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildCalendarPage());
      await tester.pumpAndSettle();

      // Alterna para Mês
      await tester.tap(find.text('Mês'));
      await tester.pumpAndSettle();

      // MonthCalendarView deve estar visível
      expect(find.byType(MonthCalendarView), findsOneWidget);
      expect(find.byType(MiniCalendarCard), findsNothing);
    });

    testWidgets('Alterna para Visão Lista e renderiza mini calendário e lista corrida de compromissos',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildCalendarPage());
      await tester.pumpAndSettle();

      // Alterna para Lista
      await tester.tap(find.text('Lista'));
      await tester.pumpAndSettle();

      // Mini Calendar está presente na Visão Lista, enquanto grades de Semana e Mês ficam ocultadas
      expect(find.byType(MiniCalendarCard), findsOneWidget);
      expect(find.byType(MonthCalendarView), findsNothing);
      expect(find.byType(WeekCalendarView), findsNothing);
      // Exibe cabeçalho de lista
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
