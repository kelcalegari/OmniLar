import '../../../../core/domain/enums/recurrence.dart';
import '../entities/calendar_event.dart';

/// Quantas ocorrências futuras são criadas para cada frequência de repetição.
int _futureOccurrencesCount(RecurrenceFrequency frequency) {
  switch (frequency) {
    case RecurrenceFrequency.daily:
      return 14;
    case RecurrenceFrequency.weekly:
      return 8;
    case RecurrenceFrequency.biweekly:
      return 4;
    case RecurrenceFrequency.monthly:
      return 6;
    case RecurrenceFrequency.yearly:
      return 2;
    case RecurrenceFrequency.none:
      return 0;
  }
}

/// Mesmo dia e horário de [start] em outro mês; em meses mais curtos usa o
/// último dia (31/01 vira 28/02, e não 03/03).
DateTime _sameDayOfMonth(DateTime start, int year, int month) {
  final lastDay = DateTime(year, month + 1, 0).day;
  final day = start.day > lastDay ? lastDay : start.day;
  return DateTime(year, month, day, start.hour, start.minute);
}

/// Inícios das próximas ocorrências de um evento recorrente, sem contar a
/// primeira (o próprio [event]). Respeita [CalendarEvent.recurrenceEndDate].
List<DateTime> futureOccurrenceStarts(CalendarEvent event) {
  final start = event.startTime;
  final starts = <DateTime>[];

  for (int i = 1; i <= _futureOccurrencesCount(event.recurrenceFrequency); i++) {
    final DateTime nextStart;
    switch (event.recurrenceFrequency) {
      case RecurrenceFrequency.daily:
        nextStart = start.add(Duration(days: i));
        break;
      case RecurrenceFrequency.weekly:
        nextStart = start.add(Duration(days: 7 * i));
        break;
      case RecurrenceFrequency.biweekly:
        nextStart = start.add(Duration(days: 14 * i));
        break;
      case RecurrenceFrequency.monthly:
        nextStart = _sameDayOfMonth(start, start.year, start.month + i);
        break;
      case RecurrenceFrequency.yearly:
        nextStart = _sameDayOfMonth(start, start.year + i, start.month);
        break;
      case RecurrenceFrequency.none:
        nextStart = start;
        break;
    }

    if (event.recurrenceEndDate != null && nextStart.isAfter(event.recurrenceEndDate!)) {
      break;
    }
    starts.add(nextStart);
  }

  return starts;
}
