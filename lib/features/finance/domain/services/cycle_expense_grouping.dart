import '../../../../core/domain/value_objects/money.dart';
import '../entities/house_expense.dart';
import '../entities/payment_method.dart';

/// Identifica a fatura de um cartão pelo vencimento.
String cardInvoiceKey(String paymentMethodId, DateTime dueDate) =>
    '$paymentMethodId|${DateTime(dueDate.year, dueDate.month, dueDate.day).toIso8601String()}';

/// Uma entrada da lista de gastos do ciclo: uma despesa solta ou a fatura de
/// um cartão com as compras dela.
sealed class CycleExpenseEntry {
  const CycleExpenseEntry();
}

class SingleExpenseEntry extends CycleExpenseEntry {
  final HouseExpense expense;

  const SingleExpenseEntry(this.expense);
}

/// Compras de um cartão que vencem no mesmo dia, mostradas como uma fatura.
class CardInvoiceEntry extends CycleExpenseEntry {
  final PaymentMethod card;
  final DateTime dueDate;

  /// Da compra mais recente para a mais antiga.
  final List<HouseExpense> purchases;

  const CardInvoiceEntry({
    required this.card,
    required this.dueDate,
    required this.purchases,
  });

  String get key => cardInvoiceKey(card.id, dueDate);

  Money get total => Money(purchases.fold<int>(0, (acc, e) => acc + e.amount.cents));

  /// Dia em que o pagamento da fatura foi registrado (null = em aberto).
  DateTime? get paidAt => purchases.every((e) => e.paidAt != null) ? purchases.first.paidAt : null;

  bool get isOpen => paidAt == null;

  /// Em aberto depois do vencimento.
  bool isOverdue(DateTime now) =>
      isOpen && dueDate.isBefore(DateTime(now.year, now.month, now.day));
}

/// Nota paga com mais de um meio (0124), mostrada como uma linha só: as partes
/// que aparecem neste ciclo, inclusive a do cartão (que continua dentro da
/// fatura dela). As outras partes podem estar em outros ciclos.
class PaymentNoteEntry extends CycleExpenseEntry {
  final String groupId;

  /// Partes visíveis no ciclo, da maior para a menor.
  final List<HouseExpense> parts;

  const PaymentNoteEntry({required this.groupId, required this.parts});

  String get title => parts.first.title;

  /// Soma das partes que aparecem neste ciclo.
  Money get visibleTotal => Money(parts.fold<int>(0, (acc, e) => acc + e.amount.cents));

  /// A nota inteira, mesmo com partes (ou parcelas) em outros ciclos.
  Money get total {
    final whole = parts.map((e) => e.paymentGroupTotalCents).whereType<int>().firstOrNull;
    return whole == null || whole < visibleTotal.cents ? visibleTotal : Money(whole);
  }

  /// Há partes (ou parcelas) fora deste ciclo.
  bool get hasHiddenParts => total.cents > visibleTotal.cents;

  DateTime get date => parts.first.date;
}

/// Troca as partes soltas de uma nota com vários meios por uma linha só
/// ([PaymentNoteEntry]), no lugar da primeira delas. A parte do cartão fica
/// também dentro da fatura. Nota com uma parte só neste ciclo segue como está.
List<CycleExpenseEntry> groupPaymentNotes(List<CycleExpenseEntry> entries) {
  final byGroup = <String, List<HouseExpense>>{};
  for (final entry in entries) {
    switch (entry) {
      case SingleExpenseEntry(:final expense):
        final id = expense.paymentGroupId;
        if (id != null) byGroup.putIfAbsent(id, () => []).add(expense);
      case CardInvoiceEntry():
        for (final purchase in entry.purchases) {
          final id = purchase.paymentGroupId;
          if (id != null) byGroup.putIfAbsent(id, () => []).add(purchase);
        }
      case PaymentNoteEntry():
        break;
    }
  }

  final result = <CycleExpenseEntry>[];
  final placed = <String>{};
  for (final entry in entries) {
    if (entry is SingleExpenseEntry && entry.expense.paymentGroupId != null) {
      final id = entry.expense.paymentGroupId!;
      final parts = byGroup[id]!;
      // Uma parte só no ciclo: nada a juntar
      if (parts.length < 2) {
        result.add(entry);
        continue;
      }
      if (placed.add(id)) {
        result.add(
          PaymentNoteEntry(
            groupId: id,
            parts: [...parts]..sort((a, b) => b.amount.cents.compareTo(a.amount.cents)),
          ),
        );
      }
      continue;
    }
    result.add(entry);
  }
  return result;
}

/// Junta em uma fatura as compras de cartão do ciclo, sem mudar nenhuma
/// despesa: é só a forma de mostrar. A fatura fica no lugar da primeira compra
/// dela na lista. É a fatura que se paga, então mesmo uma compra sozinha
/// aparece dentro dela. Contas recorrentes no cartão seguem soltas: vencem no
/// dia da própria série.
List<CycleExpenseEntry> groupCardInvoices(
  List<HouseExpense> expenses,
  List<PaymentMethod> paymentMethods,
) {
  final cards = {
    for (final method in paymentMethods)
      if (method.isCreditCard) method.id: method,
  };

  String? invoiceKeyOf(HouseExpense expense) {
    final dueDate = expense.dueDate;
    if (dueDate == null ||
        expense.isRecurring ||
        expense.isProjectExpense ||
        !cards.containsKey(expense.paymentMethodId)) {
      return null;
    }
    return '${expense.paymentMethodId}|${dueDate.year}-${dueDate.month}-${dueDate.day}';
  }

  final byInvoice = <String, List<HouseExpense>>{};
  for (final expense in expenses) {
    final key = invoiceKeyOf(expense);
    if (key != null) byInvoice.putIfAbsent(key, () => []).add(expense);
  }

  final entries = <CycleExpenseEntry>[];
  final placed = <String>{};
  for (final expense in expenses) {
    final key = invoiceKeyOf(expense);
    final purchases = key == null ? null : byInvoice[key];
    if (key == null || purchases == null) {
      entries.add(SingleExpenseEntry(expense));
      continue;
    }
    if (!placed.add(key)) continue;

    final dueDate = expense.dueDate!;
    entries.add(
      CardInvoiceEntry(
        card: cards[expense.paymentMethodId]!,
        dueDate: DateTime(dueDate.year, dueDate.month, dueDate.day),
        purchases: [...purchases]..sort((a, b) => b.date.compareTo(a.date)),
      ),
    );
  }
  return entries;
}
