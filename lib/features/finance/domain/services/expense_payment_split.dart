import '../../../../core/domain/value_objects/money.dart';
import '../entities/house_expense.dart';
import '../entities/house_expense_item.dart';
import '../entities/payment_method.dart';
import '../entities/split_rule.dart';
import 'credit_card_invoice_calculator.dart';
import 'expense_launch_defaults.dart';

/// Quanto de uma nota foi pago com um meio de pagamento.
class PaymentPart {
  final String paymentMethodId;
  final int amountCents;

  const PaymentPart({required this.paymentMethodId, required this.amountCents});
}

/// Nota paga com mais de um meio de pagamento (0124), ex.: R$ 150 com R$ 50 no
/// VA e R$ 100 no cartão.
///
/// A nota vira uma despesa por meio, ligadas por `paymentGroupId`. Cada parte
/// segue a regra do próprio meio: a do cartão espera a fatura (e conta no ciclo
/// dela), a do VA fica fora dos aportes, a do Pix sai paga. Fatura, importação,
/// fechamento e Fôlego não precisam de regra nova.
class ExpensePaymentSplit {
  const ExpensePaymentSplit._();

  /// Motivo para recusar a divisão, ou nulo se ela vale.
  static String? validate(int totalCents, List<PaymentPart> parts) {
    if (parts.length < 2) return 'Escolha pelo menos dois meios de pagamento.';
    if (parts.any((p) => p.amountCents <= 0)) {
      return 'Cada meio de pagamento precisa de um valor maior que zero.';
    }
    final ids = parts.map((p) => p.paymentMethodId).toSet();
    if (ids.length != parts.length) return 'Use cada meio de pagamento uma vez só.';
    final sum = parts.fold<int>(0, (acc, p) => acc + p.amountCents);
    if (sum != totalCents) {
      return 'A soma dos meios (${Money(sum).format()}) deve ser igual ao valor da nota (${Money(totalCents).format()}).';
    }
    return null;
  }

  /// As partes da [note] (o lançamento inteiro, como se fosse pago com um meio
  /// só). As partes que não são de cartão nascem com [status] e [dueDate]
  /// (nulo quando a nota já foi paga); a do cartão espera a fatura. O
  /// comprovante fica só na primeira parte, para excluir uma parte não apagar o
  /// arquivo das outras.
  static List<HouseExpense> build({
    required HouseExpense note,
    required List<PaymentPart> parts,
    required Map<String, PaymentMethod> methods,
    required String groupId,
    required String Function(int index) partId,
    ExpenseStatus status = ExpenseStatus.paid,
    DateTime? dueDate,
  }) {
    final error = validate(note.amount.cents, parts);
    if (error != null) throw ArgumentError(error);

    final partCents = [for (final p in parts) p.amountCents];
    final itemCuts = note.items.isEmpty
        ? null
        : cut([for (final i in note.items) i.amount.cents], partCents);
    final fixed = note.splitRule.type == SplitType.fixed ? note.splitRule.fixedAmounts : null;
    final fixedIds = fixed?.keys.toList() ?? const <String>[];
    final fixedCuts = fixed == null ? null : cut([for (final id in fixedIds) fixed[id]!.cents], partCents);

    return [
      for (var p = 0; p < parts.length; p++)
        _part(
          note: note,
          index: p,
          id: partId(p),
          part: parts[p],
          method: methods[parts[p].paymentMethodId],
          groupId: groupId,
          status: status,
          dueDate: dueDate,
          items: itemCuts == null
              ? const []
              : [
                  for (var i = 0; i < note.items.length; i++)
                    if (itemCuts[p][i] > 0) (note.items[i], itemCuts[p][i]),
                ],
          splitRule: fixedCuts == null
              ? note.splitRule
              : SplitRule.fixed({
                  for (var m = 0; m < fixedIds.length; m++)
                    if (fixedCuts[p][m] > 0) fixedIds[m]: Money(fixedCuts[p][m]),
                }),
        ),
    ];
  }

  static HouseExpense _part({
    required HouseExpense note,
    required int index,
    required String id,
    required PaymentPart part,
    required PaymentMethod? method,
    required String groupId,
    required ExpenseStatus status,
    required DateTime? dueDate,
    required List<(HouseExpenseItem, int)> items,
    required SplitRule splitRule,
  }) {
    final waitsForInvoice = ExpenseLaunchDefaults.waitsForInvoice(method, projectId: note.projectId);
    final isHouseMethod = method == null
        ? part.paymentMethodId == 'pm_caixa'
        : (method.ownerMemberId == null || method.id == 'pm_caixa');
    final partDueDate = waitsForInvoice
        ? CreditCardInvoiceCalculator.calculateInvoiceDueDate(
            purchaseDate: note.date,
            closingDay: method!.closingDay!,
            dueDay: method.dueDay!,
          )
        : dueDate;

    return HouseExpense(
      id: id,
      title: note.title,
      description: note.description,
      amount: Money(part.amountCents),
      date: note.date,
      dueDate: partDueDate,
      categoryId: note.categoryId,
      paidByMemberId: method?.ownerMemberId ?? note.paidByMemberId,
      paymentMethodId: part.paymentMethodId,
      splitRule: splitRule,
      status: waitsForInvoice ? ExpenseStatus.pending : status,
      paidOutOfPocket: waitsForInvoice ? false : !isHouseMethod,
      paidAt: waitsForInvoice || status == ExpenseStatus.pending ? null : note.paidAt,
      notes: note.notes,
      barcode: waitsForInvoice ? null : note.barcode,
      createdBy: note.createdBy,
      items: [
        for (var i = 0; i < items.length; i++)
          HouseExpenseItem(
            id: 'item_${id}_$i',
            expenseId: id,
            title: items[i].$1.title,
            amount: Money(items[i].$2),
            categoryId: items[i].$1.categoryId,
            responsibleMemberId: items[i].$1.responsibleMemberId,
            splitRule: items[i].$1.splitRule,
          ),
      ],
      attachmentPath: index == 0 ? note.attachmentPath : null,
      attachmentName: index == 0 ? note.attachmentName : null,
      attachmentContentType: index == 0 ? note.attachmentContentType : null,
      attachmentSizeBytes: index == 0 ? note.attachmentSizeBytes : null,
      paymentGroupId: groupId,
    );
  }

  /// Corta os [pieces] (itens ou valores fixos, em ordem) entre as [parts],
  /// como uma fita: cada parte leva o trecho seguinte da soma, e só a peça na
  /// divisa entre duas partes é repartida. `resultado[p][i]` é quanto da peça
  /// `i` vai na parte `p`; as linhas somam as partes e as colunas, as peças.
  static List<List<int>> cut(List<int> pieces, List<int> parts) {
    final total = pieces.fold<int>(0, (a, b) => a + b);
    final partsTotal = parts.fold<int>(0, (a, b) => a + b);
    if (total != partsTotal) {
      throw ArgumentError('Peças ($total) e partes ($partsTotal) com somas diferentes');
    }
    final result = [for (final _ in parts) List<int>.filled(pieces.length, 0)];
    var piece = 0;
    var pieceLeft = pieces.isEmpty ? 0 : pieces[0];
    for (var p = 0; p < parts.length; p++) {
      var partLeft = parts[p];
      while (partLeft > 0 && piece < pieces.length) {
        final take = pieceLeft < partLeft ? pieceLeft : partLeft;
        result[p][piece] += take;
        partLeft -= take;
        pieceLeft -= take;
        if (pieceLeft == 0) {
          piece++;
          if (piece < pieces.length) pieceLeft = pieces[piece];
        }
      }
    }
    return result;
  }
}
