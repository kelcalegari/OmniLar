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

/// Meio com que a fatura de um cartão pode ser paga.
class InvoicePaymentOption {
  /// Id do meio de pagamento, ou [holderOption] / [houseOption] quando não há
  /// um meio cadastrado para isso.
  final String key;
  final String label;

  /// Pago pela casa (Caixa): sem reembolso, e o que não era da casa vira dívida.
  final bool byHouse;

  const InvoicePaymentOption({required this.key, required this.label, required this.byHouse});

  static const String holderOption = 'holder';
  static const String houseOption = 'house';
}

/// Meios para pagar a fatura de [card]: os da casa (pago pelo Caixa) e os do
/// titular do cartão (pago por ele, reembolsado no fechamento). Outro cartão
/// de crédito não entra. Sem meio cadastrado do titular ou da casa, entra uma
/// opção genérica. A primeira opção é a sugerida.
List<InvoicePaymentOption> invoicePaymentOptions(
  PaymentMethod card,
  List<PaymentMethod> methods, {
  Map<String, String> memberNames = const {},
}) {
  final owner = card.ownerMemberId;
  final ownerName = memberNames[owner] ?? 'titular';
  bool usable(PaymentMethod m) => m.id != card.id && !ExpenseLaunchDefaults.waitsForInvoice(m);

  final holder = [
    if (owner != null)
      for (final m in methods)
        if (usable(m) && m.ownerMemberId == owner)
          InvoicePaymentOption(key: m.id, label: '${m.name} ($ownerName)', byHouse: false),
  ];
  if (owner != null && holder.isEmpty) {
    holder.add(InvoicePaymentOption(
      key: InvoicePaymentOption.holderOption,
      label: 'Dinheiro de $ownerName',
      byHouse: false,
    ));
  }
  final house = [
    for (final m in methods)
      if (usable(m) && m.ownerMemberId == null)
        InvoicePaymentOption(key: m.id, label: '${m.name} (da casa)', byHouse: true),
  ];
  if (house.isEmpty) {
    house.add(const InvoicePaymentOption(
      key: InvoicePaymentOption.houseOption,
      label: 'Caixa da Casa',
      byHouse: true,
    ));
  }
  // Cartão com dono: em geral é o titular que paga; cartão da casa, o Caixa
  return owner != null ? [...holder, ...house] : house;
}
