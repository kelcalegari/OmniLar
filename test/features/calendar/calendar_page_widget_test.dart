import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:omni_lar/core/di/service_locator.dart';
import 'package:omni_lar/features/auth/presentation/cubit/auth_cubit.dart';
import 'package:omni_lar/features/calendar/presentation/cubit/calendar_cubit.dart';
import 'package:omni_lar/features/calendar/presentation/pages/calendar_page.dart';
import 'package:omni_lar/features/calendar/presentation/widgets/mini_calendar_card.dart';

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

  group('CalendarPage - Visão Agenda & Visão Lista Toggle Widget Tests', () {
    testWidgets('Exibe seletor de visão (Visão Agenda e Visão Lista) e inicia na Visão Agenda com Mini Calendário',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildCalendarPage());
      await tester.pumpAndSettle();

      // Verifica botões de toggle
      expect(find.text('Visão Agenda'), findsOneWidget);
      expect(find.text('Visão Lista'), findsOneWidget);

      // Na Visão Agenda, o MiniCalendarCard e a legenda de dots devem estar visíveis
      expect(find.byType(MiniCalendarCard), findsOneWidget);
      expect(find.text('Compromissos'), findsWidgets);
      expect(find.text('Tarefas'), findsWidgets);
    });

    testWidgets('Alterna para Visão Lista e exibe as abas tradicionais de compromissos e tarefas',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildCalendarPage());
      await tester.pumpAndSettle();

      // Clica em Visão Lista
      await tester.tap(find.text('Visão Lista'));
      await tester.pumpAndSettle();

      // Na Visão Lista, o MiniCalendarCard não é exibido
      expect(find.byType(MiniCalendarCard), findsNothing);
      // Deve exibir os botões de aba com contadores
      expect(find.textContaining('Compromissos ('), findsOneWidget);
      expect(find.textContaining('Tarefas ('), findsOneWidget);
    });

    testWidgets('MiniCalendarCard permite selecionar dia e navegar pelos dias na timeline',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildCalendarPage());
      await tester.pumpAndSettle();

      // MiniCalendarCard deve estar presente com seus dias
      expect(find.byType(MiniCalendarCard), findsOneWidget);
      expect(find.text('Hoje'), findsWidgets);

      // Clicar no chevron para dia anterior
      final prevDayBtn = find.byTooltip('Dia Anterior');
      expect(prevDayBtn, findsOneWidget);
      await tester.tap(prevDayBtn);
      await tester.pumpAndSettle();

      // Agora que não é mais hoje, o botão de voltar para Hoje aparece na barra
      expect(find.widgetWithText(TextButton, 'Hoje'), findsOneWidget);

      // Clica em Hoje para retornar
      await tester.tap(find.widgetWithText(TextButton, 'Hoje'));
      await tester.pumpAndSettle();
    });
  });
}
