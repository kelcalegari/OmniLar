import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/domain/value_objects/financial_cycle.dart';

void main() {
  group('FinancialCycle Value Object', () {
    test('calcula ciclo corretamente quando data é após o dia de início (dia 5)', () {
      final date = DateTime(2026, 10, 6);
      final cycle = FinancialCycle.fromDate(date: date, cycleStartDay: 5);

      expect(cycle.startDate, DateTime(2026, 10, 5));
      expect(cycle.endDate.day, 4);
      expect(cycle.endDate.month, 11);
      expect(cycle.endDate.year, 2026);
      expect(cycle.contains(DateTime(2026, 10, 5)), isTrue);
      expect(cycle.contains(DateTime(2026, 11, 4)), isTrue);
      expect(cycle.contains(DateTime(2026, 10, 4)), isFalse);
      expect(cycle.contains(DateTime(2026, 11, 5)), isFalse);
    });

    test('calcula ciclo corretamente quando data é antes do dia de início (dia 5)', () {
      final date = DateTime(2026, 10, 3);
      final cycle = FinancialCycle.fromDate(date: date, cycleStartDay: 5);

      expect(cycle.startDate, DateTime(2026, 9, 5));
      expect(cycle.endDate.day, 4);
      expect(cycle.endDate.month, 10);
      expect(cycle.endDate.year, 2026);
    });

    test('transição de ano em Janeiro', () {
      final date = DateTime(2027, 1, 2);
      final cycle = FinancialCycle.fromDate(date: date, cycleStartDay: 10);

      expect(cycle.startDate, DateTime(2026, 12, 10));
      expect(cycle.endDate.day, 9);
      expect(cycle.endDate.month, 1);
      expect(cycle.endDate.year, 2027);
    });

    test('avança e recua ciclos (next e previous)', () {
      final cycle = FinancialCycle.fromDate(date: DateTime(2026, 10, 15), cycleStartDay: 5);
      final nextCycle = cycle.next(5);
      final prevCycle = cycle.previous(5);

      expect(nextCycle.startDate, DateTime(2026, 11, 5));
      expect(prevCycle.startDate, DateTime(2026, 9, 5));
    });

    test('dia de início 31 em mês de 30 dias: o ciclo começa no último dia do mês', () {
      final cycle = FinancialCycle.fromDate(date: DateTime(2026, 4, 30), cycleStartDay: 31);

      expect(cycle.startDate, DateTime(2026, 4, 30));
      expect(cycle.endDate.month, 5);
      expect(cycle.endDate.day, 30);
      expect(cycle.contains(DateTime(2026, 4, 30)), isTrue);

      final before = FinancialCycle.fromDate(date: DateTime(2026, 4, 29), cycleStartDay: 31);
      expect(before.startDate, DateTime(2026, 3, 31));
      expect(before.endDate.month, 4);
      expect(before.endDate.day, 29);
    });

    test('dia de início 30 e 31 em fevereiro usam o último dia do mês', () {
      for (final startDay in [29, 30, 31]) {
        final cycle = FinancialCycle.fromDate(date: DateTime(2027, 2, 28), cycleStartDay: startDay);
        expect(cycle.startDate, DateTime(2027, 2, 28), reason: 'dia $startDay');
        expect(cycle.endDate.month, 3, reason: 'dia $startDay');
        expect(cycle.endDate.day, startDay - 1, reason: 'dia $startDay');
      }
      // Ano bissexto: fevereiro tem dia 29
      final leap = FinancialCycle.fromDate(date: DateTime(2028, 2, 29), cycleStartDay: 31);
      expect(leap.startDate, DateTime(2028, 2, 29));
    });

    test('todo dia do ano pertence ao próprio ciclo e os ciclos se encadeiam sem buraco', () {
      for (final startDay in [1, 5, 28, 29, 30, 31]) {
        var day = DateTime(2027, 1, 1);
        while (day.year < 2029) {
          final cycle = FinancialCycle.fromDate(date: day, cycleStartDay: startDay);
          expect(cycle.contains(day), isTrue, reason: 'dia $startDay, data $day');
          day = DateTime(day.year, day.month, day.day + 1);
        }

        var cycle = FinancialCycle.fromDate(date: DateTime(2027, 1, 15), cycleStartDay: startDay);
        for (var i = 0; i < 26; i++) {
          final next = cycle.next(startDay);
          final dayAfterEnd = DateTime(cycle.endDate.year, cycle.endDate.month, cycle.endDate.day + 1);
          expect(next.startDate, dayAfterEnd, reason: 'dia $startDay, ciclo $cycle');
          expect(next.previous(startDay), cycle, reason: 'dia $startDay, ciclo $next');
          cycle = next;
        }
      }
    });
  });
}
