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
  });
}
