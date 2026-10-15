import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/domain/value_objects/financial_cycle.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/features/finance/domain/entities/financial_cycle_summary.dart';
import 'package:omni_lar/features/finance/domain/entities/house_expense.dart';
import 'package:omni_lar/features/finance/domain/entities/split_rule.dart';
import 'package:omni_lar/features/reports/domain/entities/payment_due_entry.dart';
import 'package:omni_lar/features/reports/domain/services/house_cashflow_builder.dart';

void main() {
  final cycle = FinancialCycle(
    start: DateTime(2026, 10, 10),
    end: DateTime(2026, 11, 9),
  );
  final today = DateTime(2026, 10, 20);

  HouseExpense paid(
    String id,
    int cents, {
    bool outOfPocket = false,
    String method = 'pm_conta',
  }) => HouseExpense(
    id: id,
    title: id,
    amount: Money(cents),
    date: DateTime(2026, 10, 12),
    categoryId: 'cat',
    paidByMemberId: 'm_ana',
    paymentMethodId: method,
    splitRule: const SplitRule.percentage({'m_ana': 50, 'm_bia': 50}),
    status: ExpenseStatus.paid,
    paidOutOfPocket: outOfPocket,
  );

  PaymentDueEntry entry(
    PaymentDueKind kind,
    int day,
    int cents, {
    String? payerId,
    String payerName = 'Caixa da Casa',
    String? receiverId,
    String? receiverName,
    bool overdue = false,
  }) => PaymentDueEntry(
    kind: kind,
    date: DateTime(2026, day < 10 ? 11 : 10, day),
    title: '$kind $day',
    amount: Money(cents),
    payerId: payerId,
    payerName: payerName,
    receiverId: receiverId,
    receiverName: receiverName,
    isOverdue: overdue,
  );

  test('a sobra do ciclo anterior sai do resumo do ciclo', () {
    final summary = FinancialCycleSummary(
      cycle: cycle,
      totalContributions: const Money(300000),
      totalExpensesPaid: const Money(100000),
      committedFutureExpenses: const Money(50000),
      // sobra 20.000 + aportes 300.000 - (pagas 100.000 + a vencer 50.000)
      folego: const Money(170000),
      memberContributions: const {},
      memberExpensesPaid: const {},
    );
    expect(summary.openingBalance.cents, 20000);
  });

  test('saldo de hoje: sobra + aportes - o que o Caixa já pagou', () {
    final balance = HouseCashflowBuilder.startingBalance(
      openingBalance: const Money(20000),
      contributions: const Money(300000),
      expenses: [
        paid('aluguel', 150000),
        // Paga do bolso: não saiu do Caixa
        paid('farmacia', 8000, outOfPocket: true),
        // Lançada no Caixa mesmo marcada do bolso
        paid('gas', 12000, outOfPocket: true, method: 'pm_caixa'),
      ],
    );
    expect(balance.cents, 20000 + 300000 - 150000 - 12000);
  });

  test('o Caixa desconta o que paga e soma o Super Pix que recebe', () {
    final calendar = PaymentCalendar(
      cycle: cycle,
      today: today,
      entries: [
        // Conta vencida e não paga: sai hoje
        entry(PaymentDueKind.bill, 15, 20000, overdue: true),
        entry(PaymentDueKind.invoice, 25, 50000),
        // Fatura paga pela Ana: não mexe no Caixa
        entry(
          PaymentDueKind.invoice,
          25,
          40000,
          payerId: 'm_ana',
          payerName: 'Ana',
        ),
        // Parcela fora do fechamento vai para uma caixinha
        entry(
          PaymentDueKind.installment,
          28,
          5000,
          payerId: 'm_bia',
          payerName: 'Bia',
        ),
        entry(
          PaymentDueKind.closing,
          9,
          70000,
          payerId: 'm_bia',
          payerName: 'Bia',
        ),
        entry(
          PaymentDueKind.closing,
          9,
          10000,
          receiverId: 'm_ana',
          receiverName: 'Ana',
        ),
      ],
    );
    final cashflow = const HouseCashflowBuilder().build(
      calendar: calendar,
      startingBalance: const Money(60000),
    );

    expect(cashflow.days.map((d) => d.date), [
      today,
      DateTime(2026, 10, 25),
      DateTime(2026, 11, 9),
    ]);
    expect(cashflow.days.map((d) => d.balance.cents), [40000, -10000, 50000]);
    expect(cashflow.firstNegativeDay!.date, DateTime(2026, 10, 25));
    expect(cashflow.lowestBalance.cents, -10000);
    expect(cashflow.days.last.items, [
      '+ Super Pix de Bia',
      '− Super Pix para Ana',
    ]);
  });

  test('sem movimento, o menor saldo é o de hoje', () {
    final cashflow = const HouseCashflowBuilder().build(
      calendar: PaymentCalendar(cycle: cycle, today: today, entries: const []),
      startingBalance: const Money(1234),
    );
    expect(cashflow.days, isEmpty);
    expect(cashflow.lowestBalance.cents, 1234);
    expect(cashflow.firstNegativeDay, isNull);
  });
}
