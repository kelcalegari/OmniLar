import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/di/service_locator.dart';
import 'package:omni_lar/core/domain/enums/recurrence.dart';
import 'package:omni_lar/features/calendar/domain/entities/calendar_event.dart';
import 'package:omni_lar/features/calendar/presentation/cubit/calendar_cubit.dart';
import 'package:omni_lar/features/calendar/presentation/widgets/add_event_sheet.dart';

void main() {
  setUpAll(() async {
    if (!sl.isRegistered<CalendarCubit>()) {
      await initServiceLocator();
    }
  });

  final start = DateTime(2026, 11, 2, 19);
  final series = CalendarEvent(
    id: 'evt_teste_serie',
    title: 'Faxina semanal',
    startTime: start,
    endTime: start.add(const Duration(hours: 1)),
    createdByMemberId: 'member_carlos',
    recurrenceFrequency: RecurrenceFrequency.weekly,
    seriesId: 'serie_teste',
    recurrenceEndDate: DateTime(2026, 12, 28),
  );

  Future<void> openSheet(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    // A fonte de teste (letras quadradas) estoura o dropdown de frequência; só isso é ignorado
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.exceptionAsString().contains('overflowed')) return;
      previous?.call(details);
    };
    addTearDown(() => FlutterError.onError = previous);

    await tester.pumpWidget(BlocProvider.value(
      value: sl<CalendarCubit>(),
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => AddEventSheet.show(context, 'member_carlos', initialEvent: series),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
  }

  Future<void> save(WidgetTester tester) async {
    final button = find.byType(ElevatedButton).last;
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  testWidgets('editar a série mostra a data final atual', (tester) async {
    await openSheet(tester);
    expect(find.text('Repete até 28/12/2026'), findsOneWidget);
    expect(find.byTooltip('Tirar a data final'), findsOneWidget);
  });

  testWidgets('"só esta" com a data final mudada avisa e deixa escolher de novo', (tester) async {
    await openSheet(tester);

    await tester.tap(find.byTooltip('Tirar a data final'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Repete sem data final'), findsOneWidget);

    await save(tester);
    await tester.tap(find.text(RecurrenceScope.thisInstanceOnly.title(isDelete: false)));
    await tester.pumpAndSettle();

    expect(find.text('A data final não muda só esta'), findsOneWidget);
    await tester.tap(find.text('Escolher de novo'));
    await tester.pumpAndSettle();

    // Volta à escolha do alcance; cancelar não grava nada
    expect(find.text(RecurrenceScope.thisAndFuture.title(isDelete: false)), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Repete sem data final'), findsOneWidget);
  });

  testWidgets('"só esta" sem mudar a data final não mostra o aviso', (tester) async {
    await openSheet(tester);

    await save(tester);
    await tester.tap(find.text(RecurrenceScope.thisInstanceOnly.title(isDelete: false)));
    await tester.pumpAndSettle();

    expect(find.text('A data final não muda só esta'), findsNothing);
  });
}
