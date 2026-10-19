import 'cycle_expense_grouping.dart';
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

/// Fatura em aberto que parece ser a do boleto lido: compras de cartão ainda
/// pendentes com vencimento a até 5 dias do boleto e total parecido (até 30%
/// de diferença: compras que o app ainda não conhece mudam o total). A de
/// total mais próximo vem primeiro.
List<CardInvoiceEntry> knownInvoicesFor(
  List<HouseExpense> expenses, {
  required DateTime dueDate,
  required Money amount,
  List<PaymentMethod> paymentMethods = const [],
}) {
  final methods = {for (final m in paymentMethods) m.id: m};
  DateTime day(DateTime d) => DateTime(d.year, d.month, d.day);
  final groups = <String, List<HouseExpense>>{};
  final cards = <String, PaymentMethod>{};
  final dues = <String, DateTime>{};
  for (final expense in expenses) {
    final card = methods[expense.paymentMethodId];
    final due = expense.dueDate;
    if (card == null || due == null || !expense.isPending || expense.isRecurring) continue;
    if (!ExpenseLaunchDefaults.waitsForInvoice(card, projectId: expense.projectId)) continue;
    if (day(due).difference(day(dueDate)).inDays.abs() > 5) continue;
    final key = cardInvoiceKey(card.id, due);
    groups.putIfAbsent(key, () => []).add(expense);
    cards[key] = card;
    dues[key] = day(due);
  }
  final found = [
    for (final entry in groups.entries)
      CardInvoiceEntry(card: cards[entry.key]!, dueDate: dues[entry.key]!, purchases: entry.value),
  ].where((invoice) {
    final total = invoice.total.cents;
    return amount.cents == 0 || (amount.cents - total).abs() <= total * 0.3;
  }).toList()
    ..sort((a, b) => (a.total.cents - amount.cents).abs().compareTo((b.total.cents - amount.cents).abs()));
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
///
/// [usualPayerId] (quem costuma pagar a fatura, 0100) só reordena: as opções
/// dele vão na frente, e a opção genérica do titular conta como dele. A
/// escolha manual na tela sempre vence.
List<InvoicePaymentOption> invoicePaymentOptions(
  PaymentMethod card,
  List<PaymentMethod> methods, {
  Map<String, String> memberNames = const {},
  String? usualPayerId,
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
  final options = owner != null ? [...holder, ...house] : house;
  if (usualPayerId == null) return options;

  // Dono de cada opção: o meio cadastrado, ou o titular na opção genérica
  final owners = {for (final m in methods) m.id: m.ownerMemberId};
  bool usual(InvoicePaymentOption o) =>
      o.key == InvoicePaymentOption.holderOption ? owner == usualPayerId : owners[o.key] == usualPayerId;
  return [...options.where(usual), ...options.where((o) => !usual(o))];
}
