import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/domain/enums/recurrence.dart';
import 'package:omni_lar/features/calendar/domain/entities/calendar_event.dart';
import 'package:omni_lar/features/calendar/domain/services/event_recurrence.dart';

void main() {
  CalendarEvent event(RecurrenceFrequency frequency, {DateTime? until}) => CalendarEvent(
    id: 'e1',
    title: 'Reunião da casa',
    startTime: DateTime(2026, 1, 31, 19, 30),
    endTime: DateTime(2026, 1, 31, 20, 30),
    createdByMemberId: 'ana',
    recurrenceFrequency: frequency,
    recurrenceEndDate: until,
  );

  group('futureOccurrenceStarts', () {
    test('Evento único não gera ocorrências', () {
      expect(futureOccurrenceStarts(event(RecurrenceFrequency.none)), isEmpty);
    });

    test('Semanal gera 8 ocorrências de 7 em 7 dias no mesmo horário', () {
      final starts = futureOccurrenceStarts(event(RecurrenceFrequency.weekly));

      expect(starts.length, 8);
      expect(starts.first, DateTime(2026, 2, 7, 19, 30));
      expect(starts.last, DateTime(2026, 3, 28, 19, 30));
    });

    test('Mensal mantém o dia e o horário nos meses seguintes', () {
      final starts = futureOccurrenceStarts(event(RecurrenceFrequency.monthly));

      expect(starts.length, 6);
      expect(starts.every((s) => s.hour == 19 && s.minute == 30), isTrue);
      // Fevereiro não tem dia 31: usa o último dia do mês
      expect(starts[0], DateTime(2026, 2, 28, 19, 30));
      expect(starts[1], DateTime(2026, 3, 31, 19, 30));
    });

    test('Respeita a data final da repetição', () {
      final starts = futureOccurrenceStarts(
        event(RecurrenceFrequency.daily, until: DateTime(2026, 2, 3, 23, 59)),
      );

      expect(starts, [
        DateTime(2026, 2, 1, 19, 30),
        DateTime(2026, 2, 2, 19, 30),
        DateTime(2026, 2, 3, 19, 30),
      ]);
    });
  });
}
