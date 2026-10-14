import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/domain/value_objects/cycle_schedule.dart';
import 'package:omni_lar/core/domain/value_objects/financial_cycle.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/features/finance/domain/entities/house_expense.dart';
import 'package:omni_lar/features/finance/domain/entities/house_member.dart';
import 'package:omni_lar/features/finance/domain/entities/payment_method.dart';
import 'package:omni_lar/features/finance/domain/entities/split_rule.dart';
import 'package:omni_lar/features/p2p/domain/entities/p2p_installment.dart';
import 'package:omni_lar/features/p2p/domain/entities/p2p_loan.dart';
import 'package:omni_lar/features/reports/domain/services/upcoming_cycles_builder.dart';

void main() {
  const schedule = CycleSchedule(10);
  final today = DateTime(2026, 10, 20); // ciclo atual: 10/10 a 09/11

  const members = [
    HouseMember(id: 'm_ana', name: 'Ana', role: 'owner', defaultSplitPercent: 50),
    HouseMember(id: 'm_bia', name: 'Bia', role: 'member', defaultSplitPercent: 50),
  ];
  const account = PaymentMethod(id: 'pm_conta', name: 'Conta', type: PaymentMethodType.account);

  /// Quatro parcelas de R$ 50, uma por mês, do dia 15/10 ao dia 15/01.
  P2PLoan loan(String id, {bool settleInCycle = true}) => P2PLoan(
        id: id,
        title: id,
        totalAmount: const Money(20000),
        lenderMemberId: 'm_ana',
        borrowerMemberId: 'm_bia',
        installmentsCount: 4,
        createdAt: DateTime(2026, 10, 1),
        firstDueDate: DateTime(2026, 10, 15),
        settleInCycle: settleInCycle,
        installments: [
          for (var n = 1; n <= 4; n++)
            P2PInstallment(
              id: '$id-$n',
              loanId: id,
              number: n,
              totalCount: 4,
              amount: const Money(5000),
              dueDate: DateTime(2026, 9 + n, 15),
            ),
        ],
      );

  test('os três ciclos seguintes ao de hoje', () {
    final cycles = UpcomingCyclesBuilder.upcomingCycles(schedule, today);
    expect(cycles.map((c) => c.startDate), [
      DateTime(2026, 11, 10),
      DateTime(2026, 12, 10),
      DateTime(2027, 1, 10),
    ]);
  });

  test('cada parcela pesa em um ciclo só, com a numeração original', () {
    final forecast = const UpcomingCyclesBuilder().build(
      schedule: schedule,
      expensesByCycle: const {},
      loans: [loan('emprestimo')],
      members: members,
      paymentMethods: const [account],
      today: today,
    );

    expect(forecast.cycles, hasLength(3));
    for (final (index, cycle) in forecast.cycles.indexed) {
      final bia = cycle.preview.memberById('m_bia')!;
      expect(bia.p2pToPay.cents, 5000, reason: cycle.preview.cycle.formattedPeriod);
      expect(bia.installmentsToPay.single.installmentNumber, index + 2);
      expect(bia.installmentsToPay.single.totalInstallments, 4);
      expect(cycle.preview.memberById('m_ana')!.p2pToReceive.cents, 5000);
    }
  });

  test('parcela fora do fechamento fica numa lista própria e fora do saldo', () {
    final forecast = const UpcomingCyclesBuilder().build(
      schedule: schedule,
      expensesByCycle: const {},
      loans: [loan('lembrete', settleInCycle: false)],
      members: members,
      paymentMethods: const [account],
      today: today,
    );

    final first = forecast.cycles.first;
    expect(first.preview.memberById('m_bia')!.p2pToPay, const Money.zero());
    expect(first.outsideClosing.single.title, 'lembrete 2/4');
    expect(first.outsideClosing.single.payerId, 'm_bia');
  });

  test('aporte fixo e contas já lançadas entram em cada ciclo', () {
    final next = FinancialCycle(start: DateTime(2026, 11, 10), end: DateTime(2026, 12, 9));
    final fixedMembers = [
      members[0].copyWith(defaultFixedAmountCents: 100000),
      members[1].copyWith(defaultFixedAmountCents: 80000),
    ];
    final rent = HouseExpense(
      id: 'aluguel',
      title: 'Aluguel',
      amount: const Money(150000),
      date: DateTime(2026, 11, 15),
      dueDate: DateTime(2026, 11, 15),
      categoryId: 'cat',
      paidByMemberId: 'm_ana',
      paymentMethodId: account.id,
      splitRule: const SplitRule.percentage({'m_ana': 50, 'm_bia': 50}),
      status: ExpenseStatus.pending,
    );

    final forecast = const UpcomingCyclesBuilder().build(
      schedule: schedule,
      expensesByCycle: {
        next: [rent],
      },
      loans: const [],
      members: fixedMembers,
      paymentMethods: const [account],
      today: today,
    );

    final first = forecast.cycles.first.preview;
    expect(first.cycle, next);
    expect(first.memberById('m_ana')!.contributionDue.cents, 100000);
    expect(first.memberById('m_bia')!.contributionDue.cents, 80000);
    expect(first.assumedPayments.single.title, 'Aluguel');
  });

  test('quitação prevista de cada empréstimo', () {
    final forecast = const UpcomingCyclesBuilder().build(
      schedule: schedule,
      expensesByCycle: const {},
      loans: [loan('emprestimo')],
      members: members,
      paymentMethods: const [account],
      today: today,
    );
    final payoff = forecast.payoffs.single;
    expect(payoff.lastDueDate, DateTime(2027, 1, 15));
    expect(payoff.openInstallments, 4);
    expect(payoff.remaining.cents, 20000);
    expect(payoff.involves('m_bia'), isTrue);
  });
}
