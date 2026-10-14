import '../entities/category.dart';
import '../entities/house_expense.dart';
import '../entities/house_member.dart';
import '../entities/payment_method.dart';
import '../entities/split_rule.dart';

/// Regras comuns a todo caminho que lança uma despesa da casa (formulário,
/// scanner, assistente, compra do mercado, importação de fatura), para que a
/// mesma despesa não mude de reembolso, categoria ou rateio conforme a tela.
class ExpenseLaunchDefaults {
  const ExpenseLaunchDefaults._();

  /// Pago do próprio bolso (gera reembolso no fechamento): só quando a forma
  /// de pagamento pertence a um morador. Caixa da Casa e formas sem dono, não.
  static bool paidOutOfPocket(PaymentMethod? paymentMethod) =>
      paymentMethod != null &&
      paymentMethod.ownerMemberId != null &&
      paymentMethod.id != 'pm_caixa';

  /// Compra no cartão (com fechamento e vencimento) fica pendente até a fatura
  /// ser paga: é a fatura que vira paga, na data do pagamento. Despesa de
  /// projeto não entra em fatura da casa e nasce paga.
  static bool waitsForInvoice(PaymentMethod? paymentMethod, {String? projectId}) =>
      projectId == null &&
      paymentMethod != null &&
      paymentMethod.isCreditCard &&
      paymentMethod.closingDay != null &&
      paymentMethod.dueDay != null;

  /// Status com que a despesa nasce: pendente quando espera a fatura.
  static ExpenseStatus launchStatus(PaymentMethod? paymentMethod, {String? projectId}) =>
      waitsForInvoice(paymentMethod, projectId: projectId)
          ? ExpenseStatus.pending
          : ExpenseStatus.paid;

  /// "Pago do bolso" de uma despesa nova: compra que espera a fatura ainda não
  /// tem quem pagou; isso se decide ao registrar o pagamento da fatura.
  static bool launchPaidOutOfPocket(PaymentMethod? paymentMethod, {String? projectId}) =>
      !waitsForInvoice(paymentMethod, projectId: projectId) && paidOutOfPocket(paymentMethod);

  /// Categoria real da casa: a indicada (por id ou por nome), senão a primeira
  /// cujo nome contém uma das [nameKeywords], senão a primeira da lista.
  /// Devolve null quando a casa não tem categorias.
  static ExpenseCategory? matchCategory(
    List<ExpenseCategory> categories, {
    String? preferred,
    List<String> nameKeywords = const [],
  }) {
    if (categories.isEmpty) return null;
    final wanted = preferred?.trim().toLowerCase();
    if (wanted != null && wanted.isNotEmpty) {
      for (final c in categories) {
        if (c.id.toLowerCase() == wanted) return c;
      }
      for (final c in categories) {
        final name = c.name.toLowerCase();
        if (name.contains(wanted) || wanted.contains(name)) return c;
      }
    }
    for (final keyword in nameKeywords) {
      for (final c in categories) {
        if (c.name.toLowerCase().contains(keyword.toLowerCase())) return c;
      }
    }
    return categories.first;
  }

  /// Responsável de um sub-item: quem foi marcado nele; sem marcação, o dono da
  /// categoria do sub-item (se houver). Null = entra no rateio da despesa.
  static String? itemResponsible({
    required String? chosenMemberId,
    required ExpenseCategory? itemCategory,
  }) =>
      chosenMemberId ?? itemCategory?.ownerMemberId;

  /// Rateio padrão: categoria com dono vai 100% para o dono; as demais seguem
  /// o percentual padrão dos moradores.
  static SplitRule splitRule({
    required ExpenseCategory? category,
    required List<HouseMember> members,
    required String paidByMemberId,
  }) {
    final ownerId = category?.ownerMemberId;
    if (ownerId != null) return SplitRule.singleResponsible(ownerId);
    if (members.isEmpty) return SplitRule.singleResponsible(paidByMemberId);
    return SplitRule.percentage({
      for (final m in members)
        m.id: m.defaultSplitPercent > 0 ? m.defaultSplitPercent : (100.0 / members.length),
    });
  }
}
