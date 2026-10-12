import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/domain/value_objects/financial_cycle.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/features/finance/domain/entities/house_expense.dart';
import 'package:omni_lar/features/finance/domain/entities/split_rule.dart';
import 'package:omni_lar/features/finance/domain/services/cycle_expense_filter.dart';

void main() {
  // Ciclo de 09/10 a 08/11
  final cycle = FinancialCycle.fromDate(
    date: DateTime(2026, 10, 12),
    cycleStartDay: 9,
  );

  HouseExpense expense({
    required DateTime date,
    DateTime? dueDate,
    ExpenseStatus status = ExpenseStatus.paid,
    String? projectId,
    DateTime? paidAt,
  }) => HouseExpense(
    id: 'e1',
    title: 'Conta',
    amount: const Money(10000),
    date: date,
    dueDate: dueDate,
    categoryId: 'c',
    paidByMemberId: 'ana',
    paymentMethodId: 'pm',
    splitRule: const SplitRule.percentage(null),
    status: status,
    projectId: projectId,
    paidAt: paidAt,
  );

  group('expenseBelongsToCycle', () {
    test('Despesa lançada dentro do ciclo entra', () {
      final e = expense(date: DateTime(2026, 10, 20));
      expect(expenseBelongsToCycle(e, cycle, isCardPayment: false), isTrue);
    });

    test('Despesa paga de um ciclo anterior não entra', () {
      final e = expense(date: DateTime(2026, 9, 20));
      expect(expenseBelongsToCycle(e, cycle, isCardPayment: false), isFalse);
    });

    test('Conta pendente vencida em ciclo anterior continua pesando', () {
      final e = expense(
        date: DateTime(2026, 9, 1),
        dueDate: DateTime(2026, 9, 20),
        status: ExpenseStatus.pending,
      );
      expect(expenseBelongsToCycle(e, cycle, isCardPayment: false), isTrue);
    });

    test('Conta pendente que só vence depois do ciclo não entra', () {
      final e = expense(
        date: DateTime(2026, 11, 20),
        dueDate: DateTime(2026, 11, 25),
        status: ExpenseStatus.pending,
      );
      expect(expenseBelongsToCycle(e, cycle, isCardPayment: false), isFalse);
    });

    test('Compra no cartão conta no ciclo do vencimento da fatura', () {
      final e = expense(
        date: DateTime(2026, 10, 20),
        dueDate: DateTime(2026, 11, 15),
      );
      expect(expenseBelongsToCycle(e, cycle, isCardPayment: true), isFalse);
      expect(expenseBelongsToCycle(e, cycle, isCardPayment: false), isTrue);
    });

    test('Boleto vencido em um ciclo e pago no seguinte conta só no ciclo do lançamento', () {
      // Ciclo anterior: 09/09 a 08/10
      final previousCycle = FinancialCycle.fromDate(
        date: DateTime(2026, 10, 1),
        cycleStartDay: 9,
      );
      final e = expense(
        date: DateTime(2026, 10, 12),
        dueDate: DateTime(2026, 10, 5),
      );

      expect(expenseBelongsToCycle(e, cycle, isCardPayment: false), isTrue);
      expect(expenseBelongsToCycle(e, previousCycle, isCardPayment: false), isFalse);
    });

    test('Compra no cartão não aparece no ciclo da compra, só no da fatura', () {
      final nextCycle = FinancialCycle.fromDate(
        date: DateTime(2026, 11, 15),
        cycleStartDay: 9,
      );
      final e = expense(
        date: DateTime(2026, 10, 20),
        dueDate: DateTime(2026, 11, 15),
      );

      expect(expenseBelongsToCycle(e, cycle, isCardPayment: true), isFalse);
      expect(expenseBelongsToCycle(e, nextCycle, isCardPayment: true), isTrue);
    });

    test('Conta atrasada que recebeu baixa conta só no ciclo da baixa', () {
      // Cadastrada em setembro, arrastada e baixada em outubro
      final previousCycle = FinancialCycle.fromDate(
        date: DateTime(2026, 9, 20),
        cycleStartDay: 9,
      );
      final e = expense(
        date: DateTime(2026, 9, 12),
        dueDate: DateTime(2026, 9, 20),
        paidAt: DateTime(2026, 10, 15),
      );

      expect(expenseBelongsToCycle(e, cycle, isCardPayment: false), isTrue);
      // Fechar setembro depois não pode cobrar a mesma conta de novo
      expect(expenseBelongsToCycle(e, previousCycle, isCardPayment: false), isFalse);
    });

    test('Despesa de projeto nunca entra no ciclo da casa', () {
      final e = expense(date: DateTime(2026, 10, 20), projectId: 'viagem');
      expect(expenseBelongsToCycle(e, cycle, isCardPayment: false), isFalse);
    });
  });
}
