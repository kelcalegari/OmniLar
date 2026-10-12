import '../../../../core/domain/value_objects/financial_cycle.dart';

/// Utilitário de domínio para calcular o fechamento e o vencimento
/// da fatura de cartão de crédito e associá-la ao ciclo financeiro correto.
class CreditCardInvoiceCalculator {
  const CreditCardInvoiceCalculator();

  /// Calcula a data de vencimento da fatura para uma compra realizada em [purchaseDate],
  /// dado o dia de fechamento [closingDay] e dia de vencimento [dueDay] do cartão.
  static DateTime calculateInvoiceDueDate({
    required DateTime purchaseDate,
    required int closingDay,
    required int dueDay,
  }) {
    // 1. Determina o mês e ano de fechamento da fatura
    int closingYear = purchaseDate.year;
    int closingMonth = purchaseDate.month;

    final daysInPurchaseMonth = _daysInMonth(closingYear, closingMonth);
    final effectiveClosingDay = closingDay.clamp(1, daysInPurchaseMonth);

    // Se a compra foi feita após o dia de fechamento daquele mês, a fatura já virou para o próximo mês
    if (purchaseDate.day > effectiveClosingDay) {
      if (closingMonth == 12) {
        closingYear += 1;
        closingMonth = 1;
      } else {
        closingMonth += 1;
      }
    }

    // 2. Determina o mês e ano de vencimento da fatura
    // Se o dia de vencimento for menor ou igual ao dia de fechamento (ex: fecha dia 25, vence dia 5 do mês seguinte),
    // o vencimento ocorre no mês seguinte ao fechamento.
    // Se o dia de vencimento for maior que o dia de fechamento (ex: fecha dia 10, vence dia 20),
    // o vencimento ocorre no mesmo mês do fechamento.
    int dueYear = closingYear;
    int dueMonth = closingMonth;

    if (dueDay <= closingDay) {
      if (dueMonth == 12) {
        dueYear += 1;
        dueMonth = 1;
      } else {
        dueMonth += 1;
      }
    }

    final daysInDueMonth = _daysInMonth(dueYear, dueMonth);
    final safeDueDay = dueDay.clamp(1, daysInDueMonth);

    return DateTime(dueYear, dueMonth, safeDueDay);
  }

  /// Retorna se uma compra no cartão deve ser alocada dentro de [cycle].
  ///
  /// Uma compra no cartão pesa no ciclo financeiro onde sua fatura VENCE (momento do desembolso),
  /// e não na data da compra em si.
  static bool belongsToCycle({
    required DateTime purchaseDate,
    required int closingDay,
    required int dueDay,
    required FinancialCycle cycle,
  }) {
    final invoiceDueDate = calculateInvoiceDueDate(
      purchaseDate: purchaseDate,
      closingDay: closingDay,
      dueDay: dueDay,
    );
    return cycle.contains(invoiceDueDate);
  }

  static int _daysInMonth(int year, int month) {
    return DateTime(year, month + 1, 0).day;
  }
}
