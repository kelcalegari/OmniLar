import '../../../../core/domain/value_objects/financial_cycle.dart';
import '../entities/house_expense.dart';
import '../entities/payment_method.dart';

/// Regra única de competência: decide se [expense] entra no [cycle].
/// Cada despesa conta em um único ciclo, para nunca ser cobrada duas vezes.
///
/// - Despesas de projeto vivem só no projeto (não pesam no Caixa nem no fechamento).
/// - Compra no cartão conta no ciclo do vencimento da fatura; se o pagamento da
///   fatura foi registrado, conta no ciclo em que ela foi paga.
///   Cartão com [CardCycleAssignment.purchaseDate] (0104): conta só no ciclo da
///   data da compra, paga ou não a fatura.
/// - Despesa já paga conta no ciclo em que foi lançada; se era uma conta
///   pendente, conta no ciclo em que recebeu baixa.
/// - Conta pendente conta no ciclo do vencimento e, se vencer sem ser paga,
///   continua pesando nos ciclos seguintes até receber baixa. Ciclo que ainda
///   não começou mostra só o que vence nele: até lá a conta pode ser paga.
bool expenseBelongsToCycle(
  HouseExpense expense,
  FinancialCycle cycle, {
  required bool isCardPayment,
  DateTime? now,
  CardCycleAssignment cardCycleAssignment = CardCycleAssignment.invoiceDue,
}) {
  if (expense.isProjectExpense) return false;

  // Competência pela data da compra: cada compra pesa uma vez, no ciclo em que
  // foi feita (sem passar a pesar nos seguintes enquanto a fatura está aberta)
  if (isCardPayment &&
      cardCycleAssignment == CardCycleAssignment.purchaseDate &&
      expense.dueDate != null) {
    return cycle.contains(expense.date);
  }

  final cycleHasStarted = !cycle.startDate.isAfter(now ?? DateTime.now());
  final isOverdueLiability =
      cycleHasStarted &&
      expense.isPending &&
      expense.effectiveDueDate.isBefore(cycle.endDate);
  if (isOverdueLiability) return true;

  if (isCardPayment && expense.dueDate != null) {
    return cycle.contains(expense.paidAt ?? expense.dueDate!);
  }

  return expense.isPaid
      ? cycle.contains(expense.paidAt ?? expense.date)
      : cycle.contains(expense.effectiveDueDate);
}
