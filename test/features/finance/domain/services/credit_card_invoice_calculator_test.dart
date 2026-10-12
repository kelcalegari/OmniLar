import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/domain/value_objects/financial_cycle.dart';
import 'package:omni_lar/features/finance/domain/services/credit_card_invoice_calculator.dart';

void main() {
  group('CreditCardInvoiceCalculator', () {
    test('Compra antes do fechamento com vencimento no mês seguinte (fecha 25, vence 05)', () {
      final purchase = DateTime(2026, 10, 10);
      final dueDate = CreditCardInvoiceCalculator.calculateInvoiceDueDate(
        purchaseDate: purchase,
        closingDay: 25,
        dueDay: 5,
      );

      // Fecha 25/10 -> Vence 05/11/2026
      expect(dueDate, DateTime(2026, 11, 5));
    });

    test('Compra no dia exato do fechamento (fecha 25, vence 05)', () {
      final purchase = DateTime(2026, 10, 25);
      final dueDate = CreditCardInvoiceCalculator.calculateInvoiceDueDate(
        purchaseDate: purchase,
        closingDay: 25,
        dueDay: 5,
      );

      // Fecha 25/10 -> Vence 05/11/2026
      expect(dueDate, DateTime(2026, 11, 5));
    });

    test('Compra após o fechamento - virada para o próximo ciclo (fecha 25, vence 05)', () {
      final purchase = DateTime(2026, 10, 26);
      final dueDate = CreditCardInvoiceCalculator.calculateInvoiceDueDate(
        purchaseDate: purchase,
        closingDay: 25,
        dueDay: 5,
      );

      // Já fechou em 25/10 -> Vai para fatura de 25/11 -> Vence 05/12/2026
      expect(dueDate, DateTime(2026, 12, 5));
    });

    test('Compra com fechamento e vencimento no mesmo mês (fecha 10, vence 20)', () {
      final purchaseBefore = DateTime(2026, 10, 5);
      final dueBefore = CreditCardInvoiceCalculator.calculateInvoiceDueDate(
        purchaseDate: purchaseBefore,
        closingDay: 10,
        dueDay: 20,
      );
      // Fecha 10/10 -> Vence 20/10/2026
      expect(dueBefore, DateTime(2026, 10, 20));

      final purchaseAfter = DateTime(2026, 10, 15);
      final dueAfter = CreditCardInvoiceCalculator.calculateInvoiceDueDate(
        purchaseDate: purchaseAfter,
        closingDay: 10,
        dueDay: 20,
      );
      // Fecha 10/11 -> Vence 20/11/2026
      expect(dueAfter, DateTime(2026, 11, 20));
    });

    test('Virada de ano (compra em dezembro após o fechamento)', () {
      final purchase = DateTime(2026, 12, 28);
      final dueDate = CreditCardInvoiceCalculator.calculateInvoiceDueDate(
        purchaseDate: purchase,
        closingDay: 25,
        dueDay: 5,
      );

      // Fecha 25/01/2027 -> Vence 05/02/2027
      expect(dueDate, DateTime(2027, 2, 5));
    });

    test('Pertencimento ao ciclo financeiro correto', () {
      // Ciclo da Casa: 05/10 a 04/11
      final cycleOctober = FinancialCycle.fromDate(
        date: DateTime(2026, 10, 15),
        cycleStartDay: 5,
      );

      // Ciclo da Casa: 05/11 a 04/12
      final cycleNovember = FinancialCycle.fromDate(
        date: DateTime(2026, 11, 15),
        cycleStartDay: 5,
      );

      // Compra feita em 10/10 num cartão que fecha 25 e vence 05
      // Vence em 05/11 -> pertence ao ciclo de Novembro (05/11 a 04/12) e NÃO ao ciclo de Outubro (05/10 a 04/11)!
      final purchase = DateTime(2026, 10, 10);

      expect(
        CreditCardInvoiceCalculator.belongsToCycle(
          purchaseDate: purchase,
          closingDay: 25,
          dueDay: 5,
          cycle: cycleOctober,
        ),
        isFalse,
      );

      expect(
        CreditCardInvoiceCalculator.belongsToCycle(
          purchaseDate: purchase,
          closingDay: 25,
          dueDay: 5,
          cycle: cycleNovember,
        ),
        isTrue,
      );
    });
  });
}
