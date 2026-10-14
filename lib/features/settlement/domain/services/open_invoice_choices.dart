import '../../../finance/domain/entities/house_expense.dart';
import '../../../finance/domain/entities/payment_method.dart';
import '../../../finance/domain/services/cycle_expense_grouping.dart';
import '../../../finance/domain/services/expense_launch_defaults.dart';

/// O que fazer, no fechamento, com uma fatura de cartão que ainda está em
/// aberto e pesa no ciclo.
enum OpenInvoiceChoice {
  /// Dá baixa como um boleto: o titular pagou e é reembolsado.
  paidByHolder,

  /// Dá baixa: a fatura saiu do Caixa da Casa, sem reembolso.
  paidByHouse,

  /// Fica fora deste fechamento e continua em aberto no próximo ciclo.
  carryOver,
}

/// Compra de cartão em aberto, à espera do pagamento da fatura.
bool isOpenInvoicePurchase(HouseExpense expense, PaymentMethod? method) =>
    expense.isPending &&
    !expense.isRecurring &&
    ExpenseLaunchDefaults.waitsForInvoice(method, projectId: expense.projectId);

/// Escolha que vale quando o usuário não mexe: baixa como um boleto, paga
/// pelo titular; cartão sem dono é pago pelo Caixa.
OpenInvoiceChoice defaultOpenInvoiceChoice(PaymentMethod card) =>
    card.ownerMemberId != null ? OpenInvoiceChoice.paidByHolder : OpenInvoiceChoice.paidByHouse;

/// Despesas do ciclo como o fechamento deve vê-las: fatura levada adiante sai
/// do cálculo; fatura que vai receber baixa entra como paga por quem foi
/// escolhido (o pagamento de verdade é registrado antes de confirmar).
List<HouseExpense> applyOpenInvoiceChoices(
  List<HouseExpense> expenses,
  List<PaymentMethod> paymentMethods,
  Map<String, OpenInvoiceChoice> choices,
) {
  final methods = {for (final m in paymentMethods) m.id: m};
  final result = <HouseExpense>[];
  for (final expense in expenses) {
    final method = methods[expense.paymentMethodId];
    if (method == null || !isOpenInvoicePurchase(expense, method)) {
      result.add(expense);
      continue;
    }
    final key = cardInvoiceKey(method.id, expense.dueDate!);
    switch (choices[key] ?? defaultOpenInvoiceChoice(method)) {
      case OpenInvoiceChoice.carryOver:
        break;
      case OpenInvoiceChoice.paidByHolder:
        result.add(expense.copyWith(paidOutOfPocket: method.ownerMemberId != null));
      case OpenInvoiceChoice.paidByHouse:
        result.add(expense.copyWith(paidOutOfPocket: false));
    }
  }
  return result;
}

/// Faturas em aberto entre as despesas do ciclo.
List<CardInvoiceEntry> openInvoicesOf(
  List<HouseExpense> expenses,
  List<PaymentMethod> paymentMethods,
) {
  final methods = {for (final m in paymentMethods) m.id: m};
  final open = expenses.where((e) => isOpenInvoicePurchase(e, methods[e.paymentMethodId])).toList();
  return groupCardInvoices(open, paymentMethods).whereType<CardInvoiceEntry>().toList();
}
