import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/domain/value_objects/financial_cycle.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/features/finance/data/datasources/mock_finance_datasource.dart';
import 'package:omni_lar/features/finance/domain/entities/card_invoice.dart';
import 'package:omni_lar/features/finance/domain/entities/house_expense.dart';
import 'package:omni_lar/features/finance/domain/entities/split_rule.dart';
import 'package:omni_lar/features/finance/domain/services/cycle_expense_filter.dart';

void main() {
  // Cartão fecha dia 10 e vence dia 15; o ciclo da casa vira no dia 12
  final paymentCycle = FinancialCycle.fromDate(date: DateTime(2026, 11, 10), cycleStartDay: 12);
  final dueCycle = FinancialCycle.fromDate(date: DateTime(2026, 11, 15), cycleStartDay: 12);

  HouseExpense purchase(
    String id, {
    required int cents,
    required DateTime date,
    required DateTime dueDate,
    String card = 'card',
    DateTime? paidAt,
  }) => HouseExpense(
    id: id,
    title: 'Compra $id',
    amount: Money(cents),
    date: date,
    dueDate: dueDate,
    categoryId: 'c',
    paidByMemberId: 'ana',
    paymentMethodId: card,
    splitRule: const SplitRule.percentage(null),
    paidAt: paidAt,
  );

  group('Fatura de cartão paga antes do vencimento', () {
    test('Sem pagamento registrado, a compra conta no ciclo do vencimento', () {
      final e = purchase('a', cents: 5000, date: DateTime(2026, 11, 5), dueDate: DateTime(2026, 11, 15));

      expect(expenseBelongsToCycle(e, dueCycle, isCardPayment: true), isTrue);
      expect(expenseBelongsToCycle(e, paymentCycle, isCardPayment: true), isFalse);
    });

    test('Com a fatura paga no dia 10, a compra conta só no ciclo do pagamento', () {
      final e = purchase(
        'a',
        cents: 5000,
        date: DateTime(2026, 11, 5),
        dueDate: DateTime(2026, 11, 15),
        paidAt: DateTime(2026, 11, 10),
      );

      expect(expenseBelongsToCycle(e, paymentCycle, isCardPayment: true), isTrue);
      expect(expenseBelongsToCycle(e, dueCycle, isCardPayment: true), isFalse);
    });
  });

  group('CardInvoice.groupOpenInvoices', () {
    test('Agrupa por vencimento e ignora outros cartões e faturas já pagas', () {
      final invoices = CardInvoice.groupOpenInvoices('card', [
        purchase('a', cents: 5000, date: DateTime(2026, 11, 5), dueDate: DateTime(2026, 11, 15)),
        purchase('b', cents: 2500, date: DateTime(2026, 11, 8), dueDate: DateTime(2026, 11, 15)),
        purchase('c', cents: 9000, date: DateTime(2026, 11, 11), dueDate: DateTime(2026, 12, 15)),
        purchase('d', cents: 100, date: DateTime(2026, 11, 5), dueDate: DateTime(2026, 11, 15), card: 'outro'),
        purchase(
          'e',
          cents: 700,
          date: DateTime(2026, 10, 5),
          dueDate: DateTime(2026, 10, 15),
          paidAt: DateTime(2026, 10, 10),
        ),
      ]);

      expect(invoices.length, 2);
      expect(invoices[0].dueDate, DateTime(2026, 11, 15));
      expect(invoices[0].total.cents, 7500);
      expect(invoices[0].purchasesCount, 2);
      expect(invoices[1].dueDate, DateTime(2026, 12, 15));
      expect(invoices[1].total.cents, 9000);
    });
  });

  group('MockFinanceDataSource.payCardInvoice', () {
    test('Registra o pagamento só nas compras daquela fatura', () async {
      final dataSource = MockFinanceDataSource();
      await dataSource.addExpense(
        purchase('a', cents: 5000, date: DateTime(2026, 11, 5), dueDate: DateTime(2026, 11, 15), card: 'cartao_teste'),
      );
      await dataSource.addExpense(
        purchase('c', cents: 9000, date: DateTime(2026, 11, 11), dueDate: DateTime(2026, 12, 15), card: 'cartao_teste'),
      );

      await dataSource.payCardInvoice(
        paymentMethodId: 'cartao_teste',
        invoiceDueDate: DateTime(2026, 11, 15),
        paidAt: DateTime(2026, 11, 10),
      );

      final open = await dataSource.getOpenCardInvoices('cartao_teste');
      expect(open.length, 1);
      expect(open.single.dueDate, DateTime(2026, 12, 15));
    });
  });
}
