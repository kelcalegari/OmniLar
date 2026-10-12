import 'package:equatable/equatable.dart';
import '../../../../core/domain/value_objects/money.dart';
import 'house_expense.dart';

/// Fatura de cartão em aberto: as compras de um cartão que vencem no mesmo dia.
class CardInvoice extends Equatable {
  final String paymentMethodId;
  final DateTime dueDate;
  final Money total;
  final int purchasesCount;

  const CardInvoice({
    required this.paymentMethodId,
    required this.dueDate,
    required this.total,
    required this.purchasesCount,
  });

  /// Agrupa por vencimento as compras de [paymentMethodId] cuja fatura ainda
  /// não teve o pagamento registrado. A mais próxima de vencer vem primeiro.
  static List<CardInvoice> groupOpenInvoices(
    String paymentMethodId,
    Iterable<HouseExpense> expenses,
  ) {
    final byDueDate = <DateTime, List<HouseExpense>>{};
    for (final expense in expenses) {
      if (expense.paymentMethodId != paymentMethodId) continue;
      if (expense.dueDate == null || expense.paidAt != null || expense.isProjectExpense) continue;
      final due = expense.dueDate!;
      byDueDate.putIfAbsent(DateTime(due.year, due.month, due.day), () => []).add(expense);
    }

    return [
      for (final entry in byDueDate.entries)
        CardInvoice(
          paymentMethodId: paymentMethodId,
          dueDate: entry.key,
          total: Money(entry.value.fold<int>(0, (acc, e) => acc + e.amount.cents)),
          purchasesCount: entry.value.length,
        ),
    ]..sort((a, b) => a.dueDate.compareTo(b.dueDate));
  }

  @override
  List<Object?> get props => [paymentMethodId, dueDate, total, purchasesCount];
}
