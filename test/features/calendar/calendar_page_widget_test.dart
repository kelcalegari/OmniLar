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

  group('CalendarPage - Agenda do Lar (100% Eventos & Compromissos)', () {
    testWidgets('Inicia na Visão Agenda com Mini Calendário e não contém Tarefas',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildCalendarPage());
      await tester.pumpAndSettle();

      // Botões de alternância de modo
      expect(find.text('Visão Agenda'), findsOneWidget);
      expect(find.text('Visão Lista'), findsOneWidget);

      // Mini Calendário presente
      expect(find.byType(MiniCalendarCard), findsOneWidget);

      // Apenas compromissos na agenda, sem tarefas
      expect(find.text('Compromissos agendados'), findsOneWidget);
      expect(find.text('Tarefas'), findsNothing);
    });

    testWidgets('Alterna para Visão Lista e oculta Mini Calendário exibindo lista corrida',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildCalendarPage());
      await tester.pumpAndSettle();

      // Alterna para Visão Lista
      await tester.tap(find.text('Visão Lista'));
      await tester.pumpAndSettle();

      // Mini Calendário é ocultado
      expect(find.byType(MiniCalendarCard), findsNothing);
      // Exibe cabeçalho de lista de compromissos
      expect(find.textContaining('Todos os Compromissos ('), findsOneWidget);
    });

    testWidgets('Alternância de visão funciona também em resolução Desktop',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildCalendarPage());
      await tester.pumpAndSettle();

      // No Desktop, Visão Agenda mostra MiniCalendarCard e timeline lateral
      expect(find.byType(MiniCalendarCard), findsOneWidget);

      // Alterna para Visão Lista via botão no topo
      await tester.tap(find.text('Visão Lista'));
      await tester.pumpAndSettle();

      // MiniCalendarCard sai de cena e entra lista ampla
      expect(find.byType(MiniCalendarCard), findsNothing);
      expect(find.textContaining('Todos os Compromissos ('), findsOneWidget);
    });

    testWidgets('MiniCalendarCard navega pelos dias via botões de chevron e hoje',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildCalendarPage());
      await tester.pumpAndSettle();

      // Navegar para dia anterior
      final prevBtn = find.byTooltip('Dia Anterior');
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
