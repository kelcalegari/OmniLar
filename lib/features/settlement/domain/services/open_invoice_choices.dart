import '../../../finance/domain/entities/house_expense.dart';
import '../../../finance/domain/entities/payment_method.dart';
import '../../../finance/domain/services/cycle_expense_grouping.dart';
import '../../../finance/domain/services/expense_launch_defaults.dart';
import '../../../finance/domain/services/pending_payment.dart';

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

/// Escolha de conta pendente que leva a conta para o próximo ciclo.
const String carryOverBill = 'carry_over';

/// Conta a pagar (boleto, conta fixa) ainda pendente: não é compra de cartão,
/// que se paga pela fatura.
bool isOpenBill(HouseExpense expense, PaymentMethod? method) =>
    expense.isPending && !expense.isProjectExpense && !isOpenInvoicePurchase(expense, method);

/// Meios com que uma conta pode receber baixa no fechamento: cartão de crédito
/// não entra (pagar com cartão leva a conta para a fatura do cartão).
List<PaymentMethod> billPaymentMethods(List<PaymentMethod> methods) =>
    [for (final m in methods) if (!ExpenseLaunchDefaults.waitsForInvoice(m)) m];

/// Meio que vale quando o usuário não mexe: o que a conta já tinha (se puder
/// pagar conta); senão, o da casa.
String? defaultBillMethodId(HouseExpense expense, List<PaymentMethod> methods) {
  final allowed = billPaymentMethods(methods);
  if (allowed.any((m) => m.id == expense.paymentMethodId)) return expense.paymentMethodId;
  return ExpenseLaunchDefaults.houseAccount(allowed)?.id ?? allowed.firstOrNull?.id;
}

/// Despesas do ciclo como o fechamento deve vê-las: fatura ou conta levada
/// adiante sai do cálculo; a que vai receber baixa entra como paga por quem
/// foi escolhido (o pagamento de verdade é registrado antes de confirmar).
List<HouseExpense> applyOpenInvoiceChoices(
  List<HouseExpense> expenses,
  List<PaymentMethod> paymentMethods,
  Map<String, OpenInvoiceChoice> choices, {
  Map<String, String> billChoices = const {},
}) {
  final methods = {for (final m in paymentMethods) m.id: m};
  final result = <HouseExpense>[];
  for (final expense in expenses) {
    final method = methods[expense.paymentMethodId];
    if (isOpenBill(expense, method)) {
      final choice = billChoices[expense.id] ?? defaultBillMethodId(expense, paymentMethods);
      if (choice == carryOverBill) continue;
      final chosen = methods[choice];
      // Como fica depois de paga com o meio escolhido; o status segue pendente
      // até o fechamento dar baixa
      result.add(chosen == null
          ? expense
          : paidWith(expense, paidOn: expense.effectiveDueDate, method: chosen).copyWith(
              status: ExpenseStatus.pending,
              date: expense.date,
              clearPaidAt: true,
            ));
      continue;
    }
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

/// Contas a pagar pendentes entre as despesas do ciclo.
List<HouseExpense> openBillsOf(
  List<HouseExpense> expenses,
  List<PaymentMethod> paymentMethods,
) {
  final methods = {for (final m in paymentMethods) m.id: m};
  return [for (final e in expenses) if (isOpenBill(e, methods[e.paymentMethodId])) e];
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
