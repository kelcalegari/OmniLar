import 'package:equatable/equatable.dart';
import 'financial_cycle.dart';

/// Uma troca do dia de início do ciclo: a partir de [from] (o primeiro dia do
/// ciclo de transição) a casa passa do dia [previousDay] para o dia [day].
class CycleDayChange extends Equatable {
  final DateTime from;
  final int day;
  final int previousDay;

  CycleDayChange({
    required DateTime from,
    required this.day,
    required this.previousDay,
  }) : from = DateTime(from.year, from.month, from.day);

  static List<CycleDayChange> listFromJson(Object? json) {
    if (json is! List) return const [];
    final changes = <CycleDayChange>[];
    for (final item in json) {
      if (item is! Map) continue;
      final from = DateTime.tryParse(item['from']?.toString() ?? '');
      final day = (item['day'] as num?)?.toInt();
      final previousDay = (item['previous_day'] as num?)?.toInt();
      if (from == null || day == null || previousDay == null) continue;
      changes.add(CycleDayChange(from: from, day: day, previousDay: previousDay));
    }
    changes.sort((a, b) => a.from.compareTo(b.from));
    return changes;
  }

  @override
  List<Object?> get props => [from, day, previousDay];
}

/// Calendário de ciclos de uma casa, com as trocas do dia de início.
///
/// Trocar o dia não mexe nos ciclos que já passaram: o ciclo em andamento
/// termina no dia antigo, o seguinte é um ciclo de transição (de 15 a 45 dias)
/// e depois dele os ciclos seguem o dia novo.
class CycleSchedule extends Equatable {
  /// Dia configurado hoje na casa (o da troca mais recente, se houver).
  final int currentDay;
  final List<CycleDayChange> changes;

  /// Mínimo de dias do ciclo de transição (padrão: [defaultTransitionDays];
  /// a casa pode mudar em `houses.folego_params`, 0098).
  final int minTransitionDays;

  /// Única definição do padrão da transição; o banco usa o mesmo 15 (0098).
  static const int defaultTransitionDays = 15;

  /// Mínimo da transição lido de `houses.folego_params`; ausente ou fora de
  /// 15 a 30 vale o padrão.
  static int transitionDaysFromParams(Object? params) {
    final raw = params is Map ? params['transition_min_days'] : null;
    if (raw is! num || raw != raw.truncate()) return defaultTransitionDays;
    final days = raw.toInt();
    return days >= 15 && days <= 30 ? days : defaultTransitionDays;
  }

  const CycleSchedule(this.currentDay, [this.changes = const [], this.minTransitionDays = defaultTransitionDays]);

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Primeiro início de ciclo no dia [day] em [date] ou depois dele.
  static DateTime _firstStartOnOrAfter(DateTime date, int day) {
    DateTime startIn(int year, int month) {
      final lastDay = DateTime(year, month + 1, 0).day;
      return DateTime(year, month, day > lastDay ? lastDay : day);
    }

    final sameMonth = startIn(date.year, date.month);
    if (!sameMonth.isBefore(date)) return sameMonth;
    return startIn(date.year, date.month + 1);
  }

  /// Fim do ciclo de transição que começa em [change.from].
  DateTime _firstRegularStart(CycleDayChange change) => _firstStartOnOrAfter(
        DateTime(change.from.year, change.from.month, change.from.day + minTransitionDays),
        change.day,
      );

  /// Ciclo que contém [date].
  FinancialCycle cycleFor(DateTime date) {
    final day = _dateOnly(date);

    CycleDayChange? active;
    for (final change in changes) {
      if (!change.from.isAfter(day)) active = change;
    }

    if (active == null) {
      final baseDay = changes.isEmpty ? currentDay : changes.first.previousDay;
      return FinancialCycle.fromDate(date: day, cycleStartDay: baseDay);
    }

    final firstRegularStart = _firstRegularStart(active);
    if (day.isBefore(firstRegularStart)) {
      return FinancialCycle(
        start: active.from,
        end: firstRegularStart.subtract(const Duration(days: 1)),
      );
    }
    return FinancialCycle.fromDate(date: day, cycleStartDay: active.day);
  }

  FinancialCycle next(FinancialCycle cycle) => cycleFor(
        DateTime(cycle.endDate.year, cycle.endDate.month, cycle.endDate.day + 1),
      );

  FinancialCycle previous(FinancialCycle cycle) => cycleFor(
        DateTime(cycle.startDate.year, cycle.startDate.month, cycle.startDate.day - 1),
      );

  /// Troca para [newDay] pedida em [today]: vale a partir do dia seguinte ao
  /// fim do ciclo em andamento. Uma troca ainda não iniciada é substituída.
  CycleDayChange planChange(DateTime today, int newDay) {
    final day = _dateOnly(today);
    final pending = changes.isNotEmpty && changes.last.from.isAfter(day) ? changes.last : null;
    final current = cycleFor(day);
    return CycleDayChange(
      from: DateTime(current.endDate.year, current.endDate.month, current.endDate.day + 1),
      day: newDay,
      previousDay: pending?.previousDay ?? currentDay,
    );
  }

  /// O calendário depois de aplicar [change] (substitui a troca ainda não iniciada).
  CycleSchedule withChange(CycleDayChange change) {
    final kept = changes.where((c) => c.from.isBefore(change.from)).toList();
    // Voltar ao dia que já valia antes da troca pendente é só cancelar a troca
    if (change.day == change.previousDay) return CycleSchedule(change.day, kept, minTransitionDays);
    return CycleSchedule(change.day, [...kept, change], minTransitionDays);
  }

  @override
  List<Object?> get props => [currentDay, changes, minTransitionDays];
}
