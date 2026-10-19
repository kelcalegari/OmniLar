import '../entities/category.dart';
import '../entities/house_expense.dart';
import '../entities/house_member.dart';
import '../entities/import_params.dart';
import '../entities/member_settings.dart';
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

  /// A conta da casa (Caixa): forma sem dono do tipo conta; sem ela, qualquer
  /// forma sem dono que não seja cartão.
  static PaymentMethod? houseAccount(List<PaymentMethod> methods) =>
      methods.where((m) => m.ownerMemberId == null && m.type == PaymentMethodType.account).firstOrNull ??
      methods.where((m) => m.ownerMemberId == null && !m.isCreditCard).firstOrNull;

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

  /// Rateio padrão: categoria com dono vai 100% para o dono; senão vale a
  /// divisão padrão da categoria (0097), se tiver; as demais seguem o
  /// percentual padrão dos moradores. Morador com 0% fica fora (quem entrou
  /// sem parte na divisão); só quando ninguém tem percentual a divisão é igual.
  static SplitRule splitRule({
    required ExpenseCategory? category,
    required List<HouseMember> members,
    required String paidByMemberId,
  }) {
    final ownerId = category?.ownerMemberId;
    if (ownerId != null) return SplitRule.singleResponsible(ownerId);
    final categorySplit = category?.defaultSplit?.toRule(members);
    if (categorySplit != null) return categorySplit;
    if (members.isEmpty) return SplitRule.singleResponsible(paidByMemberId);
    final anyShare = members.any((m) => m.defaultSplitPercent > 0);
    return SplitRule.percentage({
      for (final m in members)
        m.id: anyShare ? m.defaultSplitPercent : (100.0 / members.length),
    });
  }

  /// Rateio de uma escolha de divisão ([ImportSplitMode], usada pela importação
  /// e pelas listas de compras): categoria com dono vai sempre 100% para o dono;
  /// senão 'equal' divide em partes iguais, 'payer' fica só com quem paga e
  /// 'category' é o rateio padrão acima.
  static SplitRule splitRuleForMode({
    required ImportSplitMode mode,
    required ExpenseCategory? category,
    required List<HouseMember> members,
    required String paidByMemberId,
  }) {
    if (category?.ownerMemberId == null && members.isNotEmpty) {
      switch (mode) {
        case ImportSplitMode.equal:
          return SplitRule.percentage({for (final m in members) m.id: 100.0 / members.length});
        case ImportSplitMode.payer:
          return SplitRule.singleResponsible(paidByMemberId);
        case ImportSplitMode.category:
          break;
      }
    }
    return splitRule(category: category, members: members, paidByMemberId: paidByMemberId);
  }

  /// O que o formulário de despesa nova já abre marcado para quem lança:
  /// - quem pagou: o próprio morador (com "Caixa da casa" nos padrões, ele
  ///   mesmo pela conta da casa); forma de outro morador passa a ser dele;
  /// - forma de pagamento: a fixa dos padrões, senão a da última despesa que
  ///   ele lançou entre as [expenses] já carregadas;
  /// - categoria: a fixa dos padrões, senão a que ele mais usa nelas (empate:
  ///   a mais recente).
  /// Null em um campo = o formulário fica com o primeiro da lista, como antes.
  static ({String? payerId, String? paymentMethodId, String? categoryId}) formDefaults({
    required String? currentUserId,
    required List<HouseMember> members,
    required List<PaymentMethod> paymentMethods,
    required List<ExpenseCategory> categories,
    required List<HouseExpense> expenses,
    MemberSettings settings = const MemberSettings(),
  }) {
    final me = members.where((m) => m.id == currentUserId).firstOrNull;
    String? method(String? id) => paymentMethods.where((p) => p.id == id).firstOrNull?.id;
    String? category(String? id) => categories.where((c) => c.id == id).firstOrNull?.id;

    // Despesas lançadas por ele (sem repetir), da mais recente para a mais antiga
    final seen = <String>{};
    final mine = currentUserId == null
        ? <HouseExpense>[]
        : (expenses.where((e) => e.createdBy == currentUserId && seen.add(e.id)).toList()
          ..sort((a, b) => b.date.compareTo(a.date)));

    final String? paymentMethodId;
    if (settings.launchPayer == LaunchPayer.house && houseAccount(paymentMethods) != null) {
      paymentMethodId = houseAccount(paymentMethods)!.id;
    } else {
      paymentMethodId = method(settings.launchPaymentMethodId) ??
          mine.map((e) => method(e.paymentMethodId)).nonNulls.firstOrNull;
    }

    String? mostUsedCategory() {
      final counts = <String, int>{};
      for (final e in mine) {
        if (category(e.categoryId) != null) counts[e.categoryId] = (counts[e.categoryId] ?? 0) + 1;
      }
      String? best;
      // A lista já vem da mais recente: no empate fica a que apareceu primeiro
      for (final id in counts.keys) {
        if (best == null || counts[id]! > counts[best]!) best = id;
      }
      return best;
    }

    final categoryId = category(settings.launchCategoryId) ?? mostUsedCategory();

    final owner = paymentMethods.where((p) => p.id == paymentMethodId).firstOrNull?.ownerMemberId;
    final payerId = owner != null && members.any((m) => m.id == owner) ? owner : me?.id;

    return (payerId: payerId, paymentMethodId: paymentMethodId, categoryId: categoryId);
  }
}
