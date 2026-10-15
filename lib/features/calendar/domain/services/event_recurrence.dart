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

/// Uma ocorrência já gravada de uma série.
typedef SeriesOccurrence = ({String id, DateTime start});

/// O que muda numa série ao trocar o "repetir até" editando "esta e as
/// próximas": as ocorrências que passam da nova data saem, e as que faltam até
/// ela entram (sem mexer nas anteriores a [from]).
class SeriesEndChange {
  final List<String> removeIds;
  final List<DateTime> addStarts;

  const SeriesEndChange({this.removeIds = const [], this.addStarts = const []});

  bool get isEmpty => removeIds.isEmpty && addStarts.isEmpty;
}

/// [occurrences] é a série inteira; [from], o início da ocorrência editada; e
/// [edited], o evento com o novo horário, a frequência e a nova data final.
/// Com data final, as novas ocorrências seguem o dia da primeira da série; sem
/// ela, o horizonte padrão a partir da ocorrência editada.
SeriesEndChange seriesEndChange({
  required List<SeriesOccurrence> occurrences,
  required DateTime from,
  required CalendarEvent edited,
}) {
  if (occurrences.isEmpty || edited.recurrenceFrequency == RecurrenceFrequency.none) {
    return const SeriesEndChange();
  }
  final sorted = [...occurrences]..sort((a, b) => a.start.compareTo(b.start));
  final end = edited.recurrenceEndDate;
  final lastMoment = end == null ? null : DateTime(end.year, end.month, end.day, 23, 59, 59);

  final removeIds = [
    if (lastMoment != null)
      for (final o in sorted)
        if (!o.start.isBefore(from) && o.start.isAfter(lastMoment)) o.id,
  ];
  final kept = sorted.where((o) => !removeIds.contains(o.id)).toList();
  final lastKept = kept.isEmpty ? from : kept.last.start;

  final first = sorted.first.start;
  final base = end != null
      ? DateTime(first.year, first.month, first.day, edited.startTime.hour, edited.startTime.minute)
      : edited.startTime;
  final keptDays = {for (final o in kept) DateTime(o.start.year, o.start.month, o.start.day)};
  final room = maxOccurrencesWithEndDate - kept.length;
  final addStarts = <DateTime>[
    for (final s in futureOccurrenceStarts(edited.copyWith(startTime: base)))
      if (s.isAfter(lastKept) && !keptDays.contains(DateTime(s.year, s.month, s.day))) s,
  ];
  return SeriesEndChange(
    removeIds: removeIds,
    addStarts: addStarts.length > room ? addStarts.sublist(0, room < 0 ? 0 : room) : addStarts,
  );
}
