import 'package:equatable/equatable.dart';
import '../../../../core/domain/value_objects/money.dart';
import 'house_expense.dart';

/// Fatura de cartão: as compras de um cartão que vencem no mesmo dia.
class CardInvoice extends Equatable {
  final String paymentMethodId;
  final DateTime dueDate;
  final Money total;
  final int purchasesCount;

  /// Dia em que o pagamento da fatura foi registrado (null = em aberto).
  final DateTime? paidAt;

  const CardInvoice({
    required this.paymentMethodId,
    required this.dueDate,
    required this.total,
    required this.purchasesCount,
    this.paidAt,
  });

  bool get isPaid => paidAt != null;

  static DateTime _day(DateTime date) => DateTime(date.year, date.month, date.day);

  static List<CardInvoice> _group(
    String paymentMethodId,
    Iterable<HouseExpense> expenses, {
    required bool paid,
  }) {
    final byDueDate = <DateTime, List<HouseExpense>>{};
    for (final expense in expenses) {
      if (expense.paymentMethodId != paymentMethodId) continue;
      if (expense.dueDate == null || expense.isProjectExpense) continue;
      if ((expense.paidAt != null) != paid) continue;
      byDueDate.putIfAbsent(_day(expense.dueDate!), () => []).add(expense);
    }

    return [
      for (final entry in byDueDate.entries)
        CardInvoice(
          paymentMethodId: paymentMethodId,
          dueDate: entry.key,
          total: Money(entry.value.fold<int>(0, (acc, e) => acc + e.amount.cents)),
          purchasesCount: entry.value.length,
          paidAt: paid ? _day(entry.value.first.paidAt!) : null,
        ),
    ];
  }

  /// Agrupa por vencimento as compras de [paymentMethodId] cuja fatura ainda
  /// não teve o pagamento registrado. A mais próxima de vencer vem primeiro.
  static List<CardInvoice> groupOpenInvoices(
    String paymentMethodId,
    Iterable<HouseExpense> expenses,
  ) =>
      _group(paymentMethodId, expenses, paid: false)
        ..sort((a, b) => a.dueDate.compareTo(b.dueDate));

  /// Faturas de [paymentMethodId] com pagamento registrado, da mais recente para a mais antiga.
  static List<CardInvoice> groupPaidInvoices(
    String paymentMethodId,
    Iterable<HouseExpense> expenses,
  ) =>
      _group(paymentMethodId, expenses, paid: true)
        ..sort((a, b) => b.dueDate.compareTo(a.dueDate));

  @override
  List<Object?> get props => [paymentMethodId, dueDate, total, purchasesCount, paidAt];
}
