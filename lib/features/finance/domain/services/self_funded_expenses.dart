import '../entities/house_expense.dart';
import '../entities/payment_method.dart';

/// Despesas pagas com saldo próprio (forma de pagamento marcada como "não
/// consome aportes", 0122), como o vale-alimentação: contam como despesa da
/// casa nos totais e relatórios, mas ficam fora do rateio, do reembolso, do
/// Caixa, do Fôlego e do planejador.
class SelfFundedExpenses {
  const SelfFundedExpenses._();

  /// Ids das formas de pagamento que não consomem aportes.
  static Set<String> methodIds(Iterable<PaymentMethod>? methods) => {
        for (final m in methods ?? const <PaymentMethod>[])
          if (!m.consumesContributions) m.id,
      };

  /// A despesa foi paga com saldo próprio.
  static bool isSelfFunded(HouseExpense expense, Set<String> methodIds) =>
      methodIds.contains(expense.paymentMethodId);

  /// Só as despesas que saem dos aportes (o Caixa e o rateio).
  static List<HouseExpense> funded(Iterable<HouseExpense> expenses, Set<String> methodIds) =>
      methodIds.isEmpty
          ? expenses.toList()
          : expenses.where((e) => !methodIds.contains(e.paymentMethodId)).toList();
}
