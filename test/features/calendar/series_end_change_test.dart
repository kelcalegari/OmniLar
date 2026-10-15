import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/domain/enums/recurrence.dart';
import 'package:omni_lar/features/calendar/data/datasources/mock_calendar_datasource.dart';
import 'package:omni_lar/features/calendar/domain/entities/calendar_event.dart';
import 'package:omni_lar/features/calendar/domain/services/event_recurrence.dart';

void main() {
  final first = DateTime(2026, 3, 2, 19, 0);
  CalendarEvent weekly({DateTime? until}) => CalendarEvent(
        id: 'serie_semanal',
        title: 'Faxina',
        startTime: first,
        endTime: first.add(const Duration(hours: 1)),
        createdByMemberId: 'member_carlos',
        recurrenceFrequency: RecurrenceFrequency.weekly,
        recurrenceEndDate: until,
      );
  List<SeriesOccurrence> series(int count) => [
        for (var i = 0; i < count; i++) (id: 'o$i', start: first.add(Duration(days: 7 * i))),
      ];

  group('seriesEndChange', () {
    test('encurtar tira as ocorrências depois da nova data, a partir da editada', () {
      final change = seriesEndChange(
        occurrences: series(9),
        from: first.add(const Duration(days: 14)),
        edited: weekly(until: DateTime(2026, 3, 23)),
      );
      expect(change.removeIds, ['o4', 'o5', 'o6', 'o7', 'o8']);
      expect(change.addStarts, isEmpty);
    });

    test('estender cria as semanas que faltam, no dia da série', () {
      final change = seriesEndChange(
        occurrences: series(3),
        from: first.add(const Duration(days: 7)),
        edited: weekly(until: DateTime(2026, 4, 6)),
      );
      expect(change.removeIds, isEmpty);
      expect(change.addStarts, [
        DateTime(2026, 3, 23, 19),
        DateTime(2026, 3, 30, 19),
        DateTime(2026, 4, 6, 19),
      ]);
    });
  });

  test('modo demo: editar "esta e as próximas" com outro "repetir até" refaz a série', () async {
    final ds = MockCalendarDataSource();
    await ds.addEvent(weekly(until: DateTime(2026, 4, 27)));
    Future<List<CalendarEvent>> mine() async =>
        [for (final e in await ds.getEvents()) if (e.title == 'Faxina') e]
          ..sort((a, b) => a.startTime.compareTo(b.startTime));
    expect((await mine()).length, 9);

    final third = (await mine())[2];
    await ds.updateEvent(
      third.copyWith(recurrenceEndDate: DateTime(2026, 3, 30)),
      scope: RecurrenceScope.thisAndFuture,
    );
    var events = await mine();
    expect(events.length, 5);
    expect(events.last.startTime, DateTime(2026, 3, 30, 19));
    expect(events.skip(2).every((e) => e.recurrenceEndDate == DateTime(2026, 3, 30)), isTrue);

    await ds.updateEvent(
      events[2].copyWith(recurrenceEndDate: DateTime(2026, 4, 13)),
      scope: RecurrenceScope.thisAndFuture,
    );
    events = await mine();
    expect(events.length, 7);
    expect(events.last.startTime, DateTime(2026, 4, 13, 19));
  });
}
