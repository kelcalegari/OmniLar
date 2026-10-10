import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/domain/enums/recurrence.dart';
import 'package:omni_lar/features/calendar/data/datasources/mock_calendar_datasource.dart';
import 'package:omni_lar/features/calendar/domain/entities/calendar_event.dart';

void main() {
  group('MockCalendarDataSource - Eventos Recorrentes & Escopos', () {
    late MockCalendarDataSource dataSource;

    setUp(() {
      dataSource = MockCalendarDataSource();
    });

    test('addEvent com RecurrenceFrequency.weekly projeta instâncias da série', () async {
      final initialEvents = await dataSource.getEvents();
      final initialCount = initialEvents.length;

      final baseTime = DateTime(2026, 10, 15, 19, 0);
      final recurringEvent = CalendarEvent(
        id: 'test_weekly_dinner',
        title: 'Jantar Semanal da Casa',
        startTime: baseTime,
        endTime: baseTime.add(const Duration(hours: 2)),
        createdByMemberId: 'member_carlos',
        recurrenceFrequency: RecurrenceFrequency.weekly,
      );

      await dataSource.addEvent(recurringEvent);

      final updatedEvents = await dataSource.getEvents();
      final seriesEvents = updatedEvents.where((e) => e.title == 'Jantar Semanal da Casa').toList();

      // Projeta 1 mestre + 8 instâncias = 9 eventos na série
      expect(seriesEvents.length, equals(9));
      expect(updatedEvents.length, equals(initialCount + 9));
      expect(seriesEvents.every((e) => e.seriesId != null), isTrue);
    });

    test('updateEvent com scope thisInstanceOnly desvincula apenas esta ocorrência como exceção', () async {
      final baseTime = DateTime(2026, 11, 1, 10, 0);
      final recurringEvent = CalendarEvent(
        id: 'test_series_event',
        title: 'Faxina Geral',
        startTime: baseTime,
        endTime: baseTime.add(const Duration(hours: 3)),
        createdByMemberId: 'member_marina',
        recurrenceFrequency: RecurrenceFrequency.weekly,
      );

      await dataSource.addEvent(recurringEvent);
      final series = (await dataSource.getEvents()).where((e) => e.title == 'Faxina Geral').toList();
      final instanceToEdit = series[1]; // segunda ocorrência

      final modified = instanceToEdit.copyWith(
        title: 'Faxina Especial (Mudança de Horário)',
        location: 'Área Externa',
      );

      await dataSource.updateEvent(modified, scope: RecurrenceScope.thisInstanceOnly);

      final eventsAfter = await dataSource.getEvents();
      final edited = eventsAfter.firstWhere((e) => e.id == instanceToEdit.id);

      expect(edited.title, equals('Faxina Especial (Mudança de Horário)'));
      expect(edited.isRecurringException, isTrue);
      expect(edited.seriesId, isNull);

      // As outras instâncias continuam com o título original
      final others = eventsAfter.where((e) => e.title == 'Faxina Geral').toList();
      expect(others.length, equals(8));
    });

    test('updateEvent com scope thisAndFuture altera da data em diante mantendo as anteriores', () async {
      final baseTime = DateTime(2026, 12, 1, 14, 0);
      final recurringEvent = CalendarEvent(
        id: 'test_meeting',
        title: 'Reunião de Condomínio',
        startTime: baseTime,
        endTime: baseTime.add(const Duration(hours: 1)),
        createdByMemberId: 'member_carlos',
        recurrenceFrequency: RecurrenceFrequency.monthly,
      );

      await dataSource.addEvent(recurringEvent);
      final series = (await dataSource.getEvents()).where((e) => e.title == 'Reunião de Condomínio').toList()
        ..sort((a, b) => a.startTime.compareTo(b.startTime));

      // Edita a partir do 3º mês
      final target = series[2];
      final modified = target.copyWith(title: 'Reunião Extraordinária do Bloco');

      await dataSource.updateEvent(modified, scope: RecurrenceScope.thisAndFuture);

      final eventsAfter = await dataSource.getEvents();
      final oldTitles = eventsAfter.where((e) => e.title == 'Reunião de Condomínio').toList();
      final newTitles = eventsAfter.where((e) => e.title == 'Reunião Extraordinária do Bloco').toList();

      expect(oldTitles.length, equals(2)); // os 2 primeiros meses intactos
      expect(newTitles.length, equals(5)); // do 3º mês até o 7º mês (total 7 da série mensal)
    });

    test('deleteEvent com scope thisInstanceOnly remove apenas uma data da repetição', () async {
      final baseTime = DateTime(2026, 10, 20, 8, 0);
      final recurringEvent = CalendarEvent(
        id: 'test_daily_routine',
        title: 'Regar as Plantas',
        startTime: baseTime,
        endTime: baseTime.add(const Duration(minutes: 30)),
        createdByMemberId: 'member_marina',
        recurrenceFrequency: RecurrenceFrequency.daily,
      );

      await dataSource.addEvent(recurringEvent);
      final series = (await dataSource.getEvents()).where((e) => e.title == 'Regar as Plantas').toList();
      final totalBefore = series.length;

      final oneInstance = series.first;
      await dataSource.deleteEvent(oneInstance.id, scope: RecurrenceScope.thisInstanceOnly);

      final seriesAfter = (await dataSource.getEvents()).where((e) => e.title == 'Regar as Plantas').toList();
      expect(seriesAfter.length, equals(totalBefore - 1));
      expect(seriesAfter.any((e) => e.id == oneInstance.id), isFalse);
    });

    test('deleteEvent com scope thisAndFuture remove desta data em diante mantendo histórico', () async {
      final baseTime = DateTime(2026, 10, 1, 9, 0);
      final recurringEvent = CalendarEvent(
        id: 'test_gym',
        title: 'Treino em Conjunto',
        startTime: baseTime,
        endTime: baseTime.add(const Duration(hours: 1)),
        createdByMemberId: 'member_carlos',
        recurrenceFrequency: RecurrenceFrequency.weekly,
      );

      await dataSource.addEvent(recurringEvent);
      final series = (await dataSource.getEvents()).where((e) => e.title == 'Treino em Conjunto').toList()
        ..sort((a, b) => a.startTime.compareTo(b.startTime));

      // Exclui a partir da 4ª semana
      final cutEvent = series[3];
      await dataSource.deleteEvent(cutEvent.id, scope: RecurrenceScope.thisAndFuture);

      final seriesAfter = (await dataSource.getEvents()).where((e) => e.title == 'Treino em Conjunto').toList();
      expect(seriesAfter.length, equals(3)); // manteve as 3 primeiras
    });

    test('deleteEvent com scope allInstances remove toda a série', () async {
      final baseTime = DateTime(2026, 10, 5, 10, 0);
      final recurringEvent = CalendarEvent(
        id: 'test_delete_all',
        title: 'Aula de Yoga',
        startTime: baseTime,
        endTime: baseTime.add(const Duration(hours: 1)),
        createdByMemberId: 'member_marina',
        recurrenceFrequency: RecurrenceFrequency.weekly,
      );

      await dataSource.addEvent(recurringEvent);
      final series = (await dataSource.getEvents()).where((e) => e.title == 'Aula de Yoga').toList();
      expect(series.isNotEmpty, isTrue);

      await dataSource.deleteEvent(series.first.id, scope: RecurrenceScope.allInstances);

      final seriesAfter = (await dataSource.getEvents()).where((e) => e.title == 'Aula de Yoga').toList();
      expect(seriesAfter.isEmpty, isTrue);
    });
  });
}
