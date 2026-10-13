import '../entities/house_expense.dart';

/// Uma despesa por série recorrente ativa: a ocorrência mais recente (a que
/// carrega o valor e os dados atuais da série). A série é a primeira despesa
/// (matriz) mais as ocorrências ligadas a ela por `recurringSeriesId`.
List<HouseExpense> latestOccurrencePerSeries(
  Iterable<HouseExpense> occurrences, {
  required Set<String> activeSeriesIds,
}) {
  final latest = <String, HouseExpense>{};
  for (final e in occurrences) {
    final seriesId = e.recurringSeriesId ?? e.id;
    if (!activeSeriesIds.contains(seriesId)) continue;
    final current = latest[seriesId];
    if (current == null || e.effectiveDueDate.isAfter(current.effectiveDueDate)) {
      latest[seriesId] = e;
    }
  }
  return latest.values.toList()
    ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
}
