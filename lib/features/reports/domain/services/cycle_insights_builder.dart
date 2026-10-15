import '../../../../core/domain/value_objects/financial_cycle.dart';
import '../../../../core/domain/value_objects/money.dart';
import '../../../finance/domain/entities/house_expense.dart';
import '../../../finance/domain/entities/house_member.dart';
import '../../../finance/domain/entities/payment_method.dart';
import '../../../p2p/domain/entities/p2p_loan.dart';
import '../../../settlement/domain/services/open_invoice_choices.dart';
import '../entities/cycle_insights.dart';

/// Monta a leitura do ciclo a partir das despesas, do ciclo anterior e dos
/// empréstimos.
class CycleInsightsBuilder {
  const CycleInsightsBuilder();

  static Map<String, int> totalsByCategory(Iterable<HouseExpense> expenses) {
    final totals = <String, int>{};
    for (final e in expenses) {
      if (e.isProjectExpense) continue;
      totals[e.categoryId] = (totals[e.categoryId] ?? 0) + e.amount.cents;
    }
    return totals;
  }

  static CycleTotal totalOf(
    FinancialCycle cycle,
    Iterable<HouseExpense> expenses,
  ) {
    final byCategory = totalsByCategory(expenses);
    return CycleTotal(
      cycle: cycle,
      total: Money(byCategory.values.fold<int>(0, (acc, c) => acc + c)),
      byCategory: byCategory,
    );
  }

  CycleInsights build({
    required List<HouseExpense> expenses,
    List<HouseExpense>? previousExpenses,
    required List<HouseMember> members,
    required List<PaymentMethod> paymentMethods,
    required List<P2PLoan> loans,
    required DateTime today,
  }) {
    final house = expenses.where((e) => !e.isProjectExpense).toList();
    final previousByCategory = previousExpenses == null
        ? const <String, int>{}
        : totalsByCategory(previousExpenses);
    final names = {for (final m in members) m.id: m.name};
    final methodNames = {for (final m in paymentMethods) m.id: m.name};

    // Quem paga: o que está em aberto entra pela escolha padrão do fechamento
    final asClosing = applyOpenInvoiceChoices(house, paymentMethods, const {});
    final payerCents = <String?, int>{};
    for (final e in asClosing) {
      final payer = e.paidOutOfPocket && e.paymentMethodId != 'pm_caixa'
          ? e.paidByMemberId
          : null;
      payerCents[payer] = (payerCents[payer] ?? 0) + e.amount.cents;
    }
    final byPayer = [
      for (final entry in payerCents.entries)
        PayerShare(
          memberId: entry.key,
          name: entry.key == null
              ? 'Caixa da Casa'
              : (names[entry.key] ?? 'Membro'),
          amount: Money(entry.value),
        ),
    ]..sort((a, b) => b.amount.cents.compareTo(a.amount.cents));

    final methodCents = <String, int>{};
    for (final e in house) {
      methodCents[e.paymentMethodId] =
          (methodCents[e.paymentMethodId] ?? 0) + e.amount.cents;
    }
    final byMethod = [
      for (final entry in methodCents.entries)
        MethodShare(
          paymentMethodId: entry.key,
          name:
              methodNames[entry.key] ??
              (entry.key == 'pm_caixa' ? 'Caixa da Casa' : 'Outra forma'),
          amount: Money(entry.value),
        ),
    ]..sort((a, b) => b.amount.cents.compareTo(a.amount.cents));

    final recurringCents = house
        .where((e) => e.isRecurring)
        .fold<int>(0, (acc, e) => acc + e.amount.cents);
    final totalCents = house.fold<int>(0, (acc, e) => acc + e.amount.cents);

    final day = DateTime(today.year, today.month, today.day);
    final open = loans.where(
      (l) => l.status != LoanStatus.paid && l.status != LoanStatus.forgiven,
    );
    final positions = <LoanPosition>[];
    for (final m in members) {
      var toReceive = 0, toPay = 0, paid = 0, overdue = 0;
      for (final loan in open) {
        if (loan.lenderMemberId == m.id)
          toReceive += loan.remainingAmount.cents;
        if (loan.borrowerMemberId == m.id) {
          toPay += loan.remainingAmount.cents;
          paid += loan.totalPaidAmount.cents;
          if (!loan.isOpenEnded) {
            overdue += loan.openInstallments
                .where((i) => i.dueDate.isBefore(day))
                .length;
          }
        }
      }
      final position = LoanPosition(
        memberId: m.id,
        name: m.name,
        toReceive: Money(toReceive),
        toPay: Money(toPay),
        alreadyPaid: Money(paid),
        overdueInstallments: overdue,
      );
      if (!position.isEmpty) positions.add(position);
    }

    return CycleInsights(
      previousByCategory: previousByCategory,
      hasPrevious: previousExpenses != null,
      previousTotal: Money(
        previousByCategory.values.fold<int>(0, (acc, c) => acc + c),
      ),
      byPayer: byPayer,
      byMethod: byMethod,
      recurring: Money(recurringCents),
      oneOff: Money(totalCents - recurringCents),
      loanPositions: positions,
    );
  }
}
