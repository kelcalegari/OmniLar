import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/domain/value_objects/cycle_schedule.dart';
import 'package:omni_lar/core/domain/value_objects/financial_cycle.dart';

void main() {
  DateTime dayAfter(DateTime d) => DateTime(d.year, d.month, d.day + 1);

  group('CycleSchedule', () {
    test('sem troca, é o ciclo de sempre', () {
      const schedule = CycleSchedule(9);
      final cycle = schedule.cycleFor(DateTime(2026, 10, 20));
      expect(cycle, FinancialCycle.fromDate(date: DateTime(2026, 10, 20), cycleStartDay: 9));
      expect(schedule.next(cycle).startDate, DateTime(2026, 11, 9));
      expect(schedule.previous(cycle).startDate, DateTime(2026, 9, 9));
    });

    test('trocar do dia 9 para o 15: o ciclo atual não muda e o seguinte é o de transição', () {
      const before = CycleSchedule(9);
      final change = before.planChange(DateTime(2026, 10, 20), 15);
      expect(change.from, DateTime(2026, 11, 9));
      expect(change.previousDay, 9);

      final schedule = before.withChange(change);
      expect(schedule.currentDay, 15);

      // Ciclo em andamento: termina no dia antigo
      final current = schedule.cycleFor(DateTime(2026, 10, 20));
      expect(current.startDate, DateTime(2026, 10, 9));
      expect(current.endDate.day, 8);
      expect(current.endDate.month, 11);

      // Ciclos anteriores continuam no dia antigo
      expect(schedule.cycleFor(DateTime(2026, 9, 1)).startDate, DateTime(2026, 8, 9));

      // Transição: de 09/11 a 14/12 (15/11 ficaria com 6 dias)
      final transition = schedule.next(current);
      expect(transition.startDate, DateTime(2026, 11, 9));
      expect(transition.endDate.month, 12);
      expect(transition.endDate.day, 14);

      // Depois, dia 15
      final regular = schedule.next(transition);
      expect(regular.startDate, DateTime(2026, 12, 15));
      expect(schedule.next(regular).startDate, DateTime(2027, 1, 15));
      expect(schedule.previous(regular), transition);
      expect(schedule.previous(transition), current);
    });

    test('trocar do dia 9 para o 5: transição de 26 dias', () {
      const before = CycleSchedule(9);
      final schedule = before.withChange(before.planChange(DateTime(2026, 10, 20), 5));
      final transition = schedule.cycleFor(DateTime(2026, 11, 20));
      expect(transition.startDate, DateTime(2026, 11, 9));
      expect(transition.endDate.month, 12);
      expect(transition.endDate.day, 4);
    });

    test('todo dia pertence a um ciclo só, e os ciclos se encadeiam sem buraco', () {
      for (final newDay in [1, 5, 15, 28, 31]) {
        const before = CycleSchedule(9);
        final schedule = before.withChange(before.planChange(DateTime(2026, 10, 20), newDay));

        var day = DateTime(2026, 8, 1);
        while (day.isBefore(DateTime(2027, 6, 1))) {
          expect(schedule.cycleFor(day).contains(day), isTrue, reason: 'dia $newDay, data $day');
          day = dayAfter(day);
        }

        var cycle = schedule.cycleFor(DateTime(2026, 8, 15));
        for (var i = 0; i < 12; i++) {
          final next = schedule.next(cycle);
          final expectedStart = DateTime(cycle.endDate.year, cycle.endDate.month, cycle.endDate.day + 1);
          expect(next.startDate, expectedStart, reason: 'dia $newDay, ciclo $cycle');
          expect(schedule.previous(next), cycle, reason: 'dia $newDay, ciclo $next');
          final length = next.endDate.difference(next.startDate).inDays + 1;
          expect(length, inInclusiveRange(15, 46), reason: 'dia $newDay, ciclo $next');
          cycle = next;
        }
      }
    });

    test('trocar de novo antes de a troca valer substitui a troca pendente', () {
      const before = CycleSchedule(9);
      final first = before.withChange(before.planChange(DateTime(2026, 10, 20), 15));
      final secondChange = first.planChange(DateTime(2026, 10, 25), 20);
      expect(secondChange.from, DateTime(2026, 11, 9));
      expect(secondChange.previousDay, 9);

      final second = first.withChange(secondChange);
      expect(second.changes.length, 1);
      expect(second.cycleFor(DateTime(2026, 10, 25)).startDate, DateTime(2026, 10, 9));
      expect(second.cycleFor(DateTime(2027, 1, 25)).startDate, DateTime(2027, 1, 20));
    });

    test('segunda troca, depois de a primeira já valer, guarda as duas', () {
      const before = CycleSchedule(9);
      final first = before.withChange(before.planChange(DateTime(2026, 10, 20), 15));
      final second = first.withChange(first.planChange(DateTime(2027, 2, 1), 3));

      expect(second.changes.length, 2);
      // Antes da primeira troca: dia 9; entre as trocas: dia 15; depois: dia 3
      expect(second.cycleFor(DateTime(2026, 9, 20)).startDate, DateTime(2026, 9, 9));
      expect(second.cycleFor(DateTime(2027, 1, 20)).startDate, DateTime(2027, 1, 15));
      expect(second.cycleFor(DateTime(2027, 6, 20)).startDate, DateTime(2027, 6, 3));
    });

    test('lê as trocas gravadas no banco', () {
      final changes = CycleDayChange.listFromJson([
        {'from': '2026-11-09', 'day': 15, 'previous_day': 9},
        {'day': 3},
        'lixo',
      ]);
      expect(changes.length, 1);
      expect(changes.single.from, DateTime(2026, 11, 9));
      expect(CycleDayChange.listFromJson(null), isEmpty);
    });
  });
}
