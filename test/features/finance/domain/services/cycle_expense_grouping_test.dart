import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/features/finance/domain/entities/house_expense.dart';
import 'package:omni_lar/features/finance/domain/entities/payment_method.dart';
import 'package:omni_lar/features/finance/domain/entities/split_rule.dart';
import 'package:omni_lar/features/finance/domain/services/cycle_expense_grouping.dart';

const _methods = [
  PaymentMethod(id: 'nubank', name: 'Nubank', type: PaymentMethodType.card, closingDay: 28, dueDay: 14),
  PaymentMethod(id: 'itau', name: 'Itaú', type: PaymentMethodType.card, closingDay: 20, dueDay: 27),
  PaymentMethod(id: 'caixa', name: 'Caixa da Casa', type: PaymentMethodType.account),
];

HouseExpense _expense(
  String id,
  int cents,
  DateTime date, {
  String method = 'nubank',
  DateTime? dueDate,
  DateTime? paidAt,
  ExpenseStatus status = ExpenseStatus.paid,
}) =>
    HouseExpense(
      id: id,
      title: id,
      amount: Money(cents),
      date: date,
      dueDate: dueDate,
      categoryId: 'cat',
      paidByMemberId: 'kelvynn',
      paymentMethodId: method,
      splitRule: const SplitRule.percentage(null),
      status: status,
      paidAt: paidAt,
    );

void main() {
  final due = DateTime(2026, 10, 14);

  test('compras do mesmo cartão e vencimento viram uma fatura, no lugar da primeira delas', () {
    final entries = groupCardInvoices([
      _expense('mercado', 9000, DateTime(2026, 10, 13), method: 'caixa'),
      _expense('a', 60961, DateTime(2026, 9, 20), dueDate: due),
      _expense('aluguel', 220000, DateTime(2026, 10, 10), method: 'caixa'),
      _expense('b', 4032, DateTime(2026, 10, 2), dueDate: due),
      _expense('c', 19188, DateTime(2026, 9, 25), dueDate: due),
    ], _methods);

    expect(entries, hasLength(3));
    expect((entries[0] as SingleExpenseEntry).expense.id, 'mercado');
    final invoice = entries[1] as CardInvoiceEntry;
    expect((entries[2] as SingleExpenseEntry).expense.id, 'aluguel');

    expect(invoice.card.name, 'Nubank');
    expect(invoice.dueDate, due);
    expect(invoice.total.cents, 60961 + 4032 + 19188);
    // Dentro da fatura, da compra mais recente para a mais antiga
    expect(invoice.purchases.map((e) => e.id), ['b', 'c', 'a']);
    expect(invoice.paidAt, isNull);
  });

  test('cartões e vencimentos diferentes são faturas separadas', () {
    final entries = groupCardInvoices([
      _expense('a', 100, DateTime(2026, 10, 1), dueDate: due),
      _expense('b', 200, DateTime(2026, 10, 2), dueDate: due),
      _expense('c', 300, DateTime(2026, 10, 3), dueDate: DateTime(2026, 11, 14)),
      _expense('d', 400, DateTime(2026, 10, 4), dueDate: DateTime(2026, 11, 14)),
      _expense('e', 500, DateTime(2026, 10, 5), method: 'itau', dueDate: due),
      _expense('f', 600, DateTime(2026, 10, 6), method: 'itau', dueDate: due),
    ], _methods);

    expect(entries.whereType<CardInvoiceEntry>().map((i) => i.total.cents), [300, 700, 1100]);
  });

  test('compra pendente e compra sozinha entram na fatura: é ela que se paga', () {
    final entries = groupCardInvoices([
      _expense('sozinha', 100, DateTime(2026, 10, 1), dueDate: due),
      _expense('pendente1', 200, DateTime(2026, 10, 2), method: 'itau', dueDate: due, status: ExpenseStatus.pending),
      _expense('pendente2', 300, DateTime(2026, 10, 3), method: 'itau', dueDate: due, status: ExpenseStatus.pending),
    ], _methods);

    final invoices = entries.whereType<CardInvoiceEntry>().toList();
    expect(invoices.map((i) => i.card.id), ['nubank', 'itau']);
    expect(invoices[0].purchases.single.id, 'sozinha');
    expect(invoices[1].total.cents, 500);
    expect(invoices[1].isOpen, isTrue);
    expect(invoices[1].isOverdue(DateTime(2026, 10, 15)), isTrue);
    expect(invoices[1].isOverdue(DateTime(2026, 10, 14)), isFalse);
  });

  test('conta fora do cartão, conta recorrente no cartão e despesa de projeto ficam soltas', () {
    final entries = groupCardInvoices([
      _expense('conta1', 400, DateTime(2026, 10, 4), method: 'caixa', dueDate: due),
      _expense('conta2', 500, DateTime(2026, 10, 5), method: 'caixa', dueDate: due),
      HouseExpense(
        id: 'netflix',
        title: 'Netflix',
        amount: const Money(5590),
        date: DateTime(2026, 10, 10),
        dueDate: due,
        categoryId: 'cat',
        paidByMemberId: 'kelvynn',
        paymentMethodId: 'nubank',
        splitRule: const SplitRule.percentage(null),
        status: ExpenseStatus.pending,
        isRecurring: true,
      ),
      HouseExpense(
        id: 'viagem',
        title: 'Hotel',
        amount: const Money(90000),
        date: DateTime(2026, 10, 10),
        dueDate: due,
        categoryId: 'cat',
        paidByMemberId: 'kelvynn',
        paymentMethodId: 'nubank',
        splitRule: const SplitRule.percentage(null),
        projectId: 'p1',
      ),
    ], _methods);

    expect(entries, hasLength(4));
    expect(entries.whereType<CardInvoiceEntry>(), isEmpty);
  });

  test('a fatura só conta como paga quando o pagamento foi registrado em todas as compras', () {
    final paid = DateTime(2026, 10, 12);
    final all = groupCardInvoices([
      _expense('a', 100, DateTime(2026, 10, 1), dueDate: due, paidAt: paid),
      _expense('b', 200, DateTime(2026, 10, 2), dueDate: due, paidAt: paid),
    ], _methods);
    expect((all.single as CardInvoiceEntry).paidAt, paid);

    final partial = groupCardInvoices([
      _expense('a', 100, DateTime(2026, 10, 1), dueDate: due, paidAt: paid),
      _expense('b', 200, DateTime(2026, 10, 2), dueDate: due),
    ], _methods);
    expect((partial.single as CardInvoiceEntry).paidAt, isNull);
  });
}
