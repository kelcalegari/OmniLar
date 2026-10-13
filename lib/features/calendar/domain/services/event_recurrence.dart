import '../../../../core/domain/enums/recurrence.dart';
import '../entities/calendar_event.dart';

/// Limite de ocorrências de uma série com data final (um ano de evento diário
/// já são 365): protege contra uma data final muito distante.
const int maxOccurrencesWithEndDate = 200;

/// Quantas ocorrências futuras são criadas, sem data final, para cada
/// frequência de repetição.
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
/// primeira (o próprio [event]). Com [CalendarEvent.recurrenceEndDate] a série
/// vai até essa data (inclusive), limitada a [maxOccurrencesWithEndDate]; sem
/// ela, cria o horizonte padrão de cada frequência.
List<DateTime> futureOccurrenceStarts(CalendarEvent event) {
  final start = event.startTime;
  final starts = <DateTime>[];
  if (event.recurrenceFrequency == RecurrenceFrequency.none) return starts;

  final endDate = event.recurrenceEndDate;
  // A data final vale o dia inteiro
  final lastMoment = endDate == null
      ? null
      : DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59);
  final limit = endDate == null
      ? _futureOccurrencesCount(event.recurrenceFrequency)
      : maxOccurrencesWithEndDate;

  for (int i = 1; i <= limit; i++) {
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

    if (lastMoment != null && nextStart.isAfter(lastMoment)) {
      break;
    }
    starts.add(nextStart);
  }

  return starts;
}
