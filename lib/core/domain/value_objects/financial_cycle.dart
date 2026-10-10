import 'package:equatable/equatable.dart';
import 'package:intl/intl.dart';

/// Representa o ciclo financeiro da casa (ex: do dia 05 ao dia 04 do mês seguinte).
class FinancialCycle extends Equatable implements Comparable<FinancialCycle> {
  final DateTime startDate;
  final DateTime endDate;

  FinancialCycle({
    required DateTime start,
    required DateTime end,
  })  : startDate = DateTime(start.year, start.month, start.day),
        endDate = DateTime(end.year, end.month, end.day, 23, 59, 59, 999);

  /// Cria o ciclo correspondente a uma [date] de referência para um [cycleStartDay] (1 a 31).
  factory FinancialCycle.fromDate({
    required DateTime date,
    required int cycleStartDay,
  }) {
    final day = date.day;
    int startYear = date.year;
    int startMonth = date.month;

    // Se o dia da data for anterior ao dia de início do ciclo, o ciclo começou no mês anterior
    if (day < cycleStartDay) {
      if (startMonth == 1) {
        startMonth = 12;
        startYear -= 1;
      } else {
        startMonth -= 1;
      }
    }

    final safeStartDay = _clampDayToMonth(startYear, startMonth, cycleStartDay);
    final start = DateTime(startYear, startMonth, safeStartDay);

    // O fim do ciclo é 1 dia antes do próximo início de ciclo
    int nextMonth = startMonth == 12 ? 1 : startMonth + 1;
    int nextYear = startMonth == 12 ? startYear + 1 : startYear;
    final safeNextStartDay = _clampDayToMonth(nextYear, nextMonth, cycleStartDay);
    final nextStart = DateTime(nextYear, nextMonth, safeNextStartDay);

    final end = nextStart.subtract(const Duration(days: 1));

    return FinancialCycle(start: start, end: end);
  }

  /// Próximo ciclo financeiro
  FinancialCycle next(int cycleStartDay) {
    final nextDate = endDate.add(const Duration(days: 2));
    return FinancialCycle.fromDate(date: nextDate, cycleStartDay: cycleStartDay);
  }

  /// Ciclo financeiro anterior
  FinancialCycle previous(int cycleStartDay) {
    final prevDate = startDate.subtract(const Duration(days: 2));
    return FinancialCycle.fromDate(date: prevDate, cycleStartDay: cycleStartDay);
  }

  /// Verifica se uma determinada data pertence a este ciclo
  bool contains(DateTime date) {
    final normalized = DateTime(date.year, date.month, date.day);
    final normStart = DateTime(startDate.year, startDate.month, startDate.day);
    final normEnd = DateTime(endDate.year, endDate.month, endDate.day);
    return !normalized.isBefore(normStart) && !normalized.isAfter(normEnd);
  }

  /// Rótulo amigável (ex: "Outubro/2026" ou "05/10 a 04/11")
  String get label {
    final startFmt = DateFormat('dd/MM').format(startDate);
    final endFmt = DateFormat('dd/MM/yyyy').format(endDate);
    return '$startFmt a $endFmt';
  }

  /// Alias para o período formatado
  String get formattedPeriod => label;

  /// Nome do mês do ciclo (baseado no mês final onde a maioria dos vencimentos ocorre)
  String get monthName {
    final monthFormat = DateFormat('MMMM yyyy', 'pt_BR');
    return monthFormat.format(endDate);
  }

  static int _clampDayToMonth(int year, int month, int targetDay) {
    // Último dia do mês
    final lastDay = DateTime(year, month + 1, 0).day;
    return targetDay > lastDay ? lastDay : targetDay;
  }

  @override
  int compareTo(FinancialCycle other) => startDate.compareTo(other.startDate);

  @override
  List<Object?> get props => [startDate, endDate];

  @override
  String toString() => 'FinancialCycle($label)';
}
