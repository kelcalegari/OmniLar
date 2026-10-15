import '../../../../core/domain/value_objects/money.dart';
import '../../../finance/domain/entities/house_expense.dart';
import '../entities/payment_due_entry.dart';

/// Um dia em que o dinheiro do Caixa da Casa se mexe.
class CashflowDay {
  final DateTime date;
  final Money inflow;
  final Money outflow;

  /// Saldo do Caixa no fim do dia.
  final Money balance;

  /// O que entra e sai nesse dia (para a legenda).
  final List<String> items;

  const CashflowDay({
    required this.date,
    required this.inflow,
    required this.outflow,
    required this.balance,
    required this.items,
  });
}

/// Saldo do Caixa da Casa dia a dia até o fechamento do ciclo.
class HouseCashflow {
  /// Dinheiro no Caixa hoje.
  final Money startingBalance;
  final DateTime today;
  final List<CashflowDay> days;

  const HouseCashflow({
    required this.startingBalance,
    required this.today,
    required this.days,
  });

  /// Menor saldo do período (o de hoje, se nada sair).
  Money get lowestBalance => days.fold(
    startingBalance,
    (lowest, d) => d.balance.cents < lowest.cents ? d.balance : lowest,
  );

  /// Primeiro dia em que o Caixa fica negativo.
  CashflowDay? get firstNegativeDay =>
      days.where((d) => d.balance.isNegative).firstOrNull;
}

/// Projeta o saldo do Caixa a partir do calendário de pagamentos.
///
/// Mexem no Caixa: faturas e contas que ele paga e o Super Pix do fechamento
/// (o que os moradores pagam a ele e o que ele reembolsa). Parcelas fora do
/// fechamento não entram: o pagamento de acordo com o Lar vai para uma
/// caixinha, e não para o Caixa.
class HouseCashflowBuilder {
  const HouseCashflowBuilder();

  /// Dinheiro no Caixa hoje: a sobra do ciclo anterior, mais os aportes, menos
  /// o que o Caixa já pagou neste ciclo (despesa paga do bolso não sai dele).
  static Money startingBalance({
    required Money openingBalance,
    required Money contributions,
    required List<HouseExpense> expenses,
  }) {
    final paidByHouse = expenses
        .where(
          (e) =>
              !e.isProjectExpense &&
              e.isPaid &&
              (!e.paidOutOfPocket || e.paymentMethodId == 'pm_caixa'),
        )
        .fold<int>(0, (acc, e) => acc + e.amount.cents);
    return Money(openingBalance.cents + contributions.cents - paidByHouse);
  }

  HouseCashflow build({
    required PaymentCalendar calendar,
    required Money startingBalance,
  }) {
    final today = calendar.today;
    final inflows = <DateTime, int>{};
    final outflows = <DateTime, int>{};
    final items = <DateTime, List<String>>{};

    void add(PaymentDueEntry e, {required bool inflow}) {
      // O que já venceu sai hoje: ainda precisa ser pago
      final date = e.date!.isBefore(today) ? today : e.date!;
      final map = inflow ? inflows : outflows;
      map[date] = (map[date] ?? 0) + e.amount.cents;
      final who = e.kind == PaymentDueKind.closing
          ? (inflow
                ? 'Super Pix de ${e.payerName}'
                : 'Super Pix para ${e.receiverName}')
          : e.title;
      items.putIfAbsent(date, () => []).add('${inflow ? '+' : '−'} $who');
    }

    for (final e in calendar.entries) {
      if (e.date == null) continue;
      switch (e.kind) {
        case PaymentDueKind.invoice:
        case PaymentDueKind.bill:
          if (e.payerId == null) add(e, inflow: false);
        case PaymentDueKind.closing:
          if (e.payerId == null) add(e, inflow: false);
          if (e.receiverId == null) add(e, inflow: true);
        case PaymentDueKind.installment:
        case PaymentDueKind.openEnded:
          break;
      }
    }

    final dates = {...inflows.keys, ...outflows.keys}.toList()..sort();
    var balance = startingBalance.cents;
    final days = <CashflowDay>[];
    for (final date in dates) {
      final inCents = inflows[date] ?? 0;
      final outCents = outflows[date] ?? 0;
      balance += inCents - outCents;
      days.add(
        CashflowDay(
          date: date,
          inflow: Money(inCents),
          outflow: Money(outCents),
          balance: Money(balance),
          items: items[date] ?? const [],
        ),
      );
    }
    return HouseCashflow(
      startingBalance: startingBalance,
      today: today,
      days: days,
    );
  }
}
