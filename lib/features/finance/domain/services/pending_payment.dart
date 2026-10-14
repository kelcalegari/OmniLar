import '../../../../core/domain/value_objects/money.dart';
import '../entities/house_expense.dart';
import '../entities/payment_method.dart';
import 'credit_card_invoice_calculator.dart';
import 'expense_launch_defaults.dart';

/// Como fica uma conta pendente depois de paga no dia [paidOn] com [method].
///
/// Quem pagou sai do meio: com dono, o dono (é reembolsado no fechamento); da
/// casa, a casa. Cartão de crédito transforma a conta numa compra da fatura,
/// que fica pendente até a fatura ser paga. Conta recorrente no cartão recebe
/// baixa direto: as recorrentes seguem o vencimento da própria série.
HouseExpense paidWith(
  HouseExpense expense, {
  required DateTime paidOn,
  required PaymentMethod? method,
  Money? amount,
}) {
  final waitsForInvoice = !expense.isRecurring &&
      ExpenseLaunchDefaults.waitsForInvoice(method, projectId: expense.projectId);
  final paidBy = method?.ownerMemberId ?? expense.paidByMemberId;

  if (waitsForInvoice) {
    return expense.copyWith(
      amount: amount,
      date: paidOn,
      dueDate: CreditCardInvoiceCalculator.calculateInvoiceDueDate(
        purchaseDate: paidOn,
        closingDay: method!.closingDay!,
        dueDay: method.dueDay!,
      ),
      paymentMethodId: method.id,
      paidByMemberId: paidBy,
      paidOutOfPocket: false,
      status: ExpenseStatus.pending,
    );
  }
  return expense.copyWith(
    amount: amount,
    date: paidOn,
    paidAt: paidOn,
    status: ExpenseStatus.paid,
    paymentMethodId: method?.id,
    paidByMemberId: paidBy,
    paidOutOfPocket: ExpenseLaunchDefaults.paidOutOfPocket(method),
  );
}

/// Conta pendente já prevista no app que parece ser a do boleto lido: mesmo
/// código, ou vencimento próximo com o mesmo valor (ou conta de valor variável
/// ou recorrente, cujo valor muda todo mês).
List<HouseExpense> knownBillsFor(
  List<HouseExpense> expenses, {
  required DateTime dueDate,
  required Money amount,
  String? barcode,
  List<PaymentMethod> paymentMethods = const [],
}) {
  final methods = {for (final m in paymentMethods) m.id: m};
  int digits(String? text) => (text ?? '').replaceAll(RegExp(r'[^0-9]'), '').hashCode;
  final wanted = barcode == null ? null : digits(barcode);

  final found = <HouseExpense>[];
  for (final expense in expenses) {
    if (!expense.isPending || expense.isProjectExpense) continue;
    // Compra de cartão em aberto não é conta a pagar: quem se paga é a fatura
    if (!expense.isRecurring &&
        ExpenseLaunchDefaults.waitsForInvoice(methods[expense.paymentMethodId], projectId: expense.projectId)) {
      continue;
    }
    if (wanted != null && expense.barcode != null && digits(expense.barcode) == wanted) {
      found.insert(0, expense);
      continue;
    }
    final days = expense.effectiveDueDate.difference(dueDate).inDays.abs();
    final amountFits =
        expense.amount.cents == amount.cents || expense.isVariable || expense.isRecurring;
    if (days <= 5 && amountFits) found.add(expense);
  }
  return found;
}
