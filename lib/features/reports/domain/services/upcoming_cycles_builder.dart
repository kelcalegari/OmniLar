import '../../../../core/domain/value_objects/cycle_schedule.dart';
import '../../../../core/domain/value_objects/financial_cycle.dart';
import '../../../../core/domain/value_objects/money.dart';
import '../../../finance/domain/entities/house_expense.dart';
import '../../../finance/domain/entities/house_member.dart';
import '../../../finance/domain/entities/house_settings.dart';
import '../../../finance/domain/entities/payment_method.dart';
import '../../../p2p/domain/entities/p2p_installment.dart';
import '../../../p2p/domain/entities/p2p_loan.dart';
import '../../../settlement/domain/services/global_clearing_engine.dart';
import '../../../settlement/domain/services/open_invoice_choices.dart';
import '../entities/payment_due_entry.dart';
import '../entities/upcoming_forecast.dart';
import 'cycle_preview_builder.dart';

/// O que já está contratado para os próximos ciclos, por morador: o mesmo
/// motor do fechamento rodando só sobre o que já foi lançado em cada ciclo
/// (contas recorrentes geradas, faturas, parcelas), sem estimativa.
class UpcomingCyclesBuilder {
  const UpcomingCyclesBuilder();

  /// Os [count] ciclos seguintes ao ciclo de [today].
  static List<FinancialCycle> upcomingCycles(
    CycleSchedule schedule,
    DateTime today, {
    int count = 3,
  }) {
    final cycles = <FinancialCycle>[];
    var cycle = schedule.cycleFor(today);
    for (var i = 0; i < count; i++) {
      cycle = schedule.next(cycle);
      cycles.add(cycle);
    }
    return cycles;
  }

  UpcomingForecast build({
    required CycleSchedule schedule,
    required Map<FinancialCycle, List<HouseExpense>> expensesByCycle,
    required List<P2PLoan> loans,
    required List<HouseMember> members,
    required List<PaymentMethod> paymentMethods,
    Map<String, String> invoiceCodes = const {},
    required DateTime today,
    int count = 3,
    String cashLabel = HouseSettings.defaultCashLabel,
  }) {
    final day = DateTime(today.year, today.month, today.day);
    final current = schedule.cycleFor(day);
    final cycles = upcomingCycles(schedule, day, count: count);
    final memberIds = members.map((m) => m.id).toSet();
    final names = {for (final m in members) m.id: m.name};
    String nameOf(String id) =>
        id == P2PLoan.houseLenderId ? cashLabel : (names[id] ?? 'Membro');
    String? memberOrHouse(String id) => id == P2PLoan.houseLenderId ? null : id;

    final active = loans
        .where(
          (l) =>
              l.status != LoanStatus.paid &&
              l.status != LoanStatus.forgiven &&
              !l.isOpenEnded &&
              memberIds.contains(l.borrowerMemberId),
        )
        .toList();

    // Cada parcela em aberto pesa em um ciclo só: o do vencimento, ou o atual
    // se já venceu. Assim a mesma parcela não aparece em vários ciclos.
    FinancialCycle cycleOf(P2PInstallment i) =>
        i.dueDate.isBefore(current.startDate)
        ? current
        : schedule.cycleFor(i.dueDate);

    final customTargets =
        members.any((m) => (m.defaultFixedAmountCents ?? 0) > 0)
        ? {
            for (final m in members)
              if ((m.defaultFixedAmountCents ?? 0) > 0)
                m.id: Money(m.defaultFixedAmountCents!),
          }
        : null;

    final forecasts = <UpcomingCycleForecast>[];
    for (final cycle in cycles) {
      final inCycle = {
        for (final loan in active)
          for (final i in loan.openInstallments)
            if (cycleOf(i) == cycle) i.id,
      };
      // Parcelas de outros ciclos saem da conta deste (marcadas como canceladas
      // só nesta cópia), sem mudar a numeração "2/3" das que ficam
      final loansInCycle = [
        for (final loan in active)
          loan.copyWith(
            installments: [
              for (final i in loan.installments)
                inCycle.contains(i.id) ? i : i.copyWith(isCancelled: true),
            ],
          ),
      ];

      final expenses = expensesByCycle[cycle] ?? const <HouseExpense>[];
      final summary = const GlobalClearingEngine().computeSettlement(
        cycle: cycle,
        members: members,
        expenses: applyOpenInvoiceChoices(expenses, paymentMethods, const {}),
        contributions: const [],
        loans: loansInCycle,
        customContributionTargets: customTargets,
      );
      final preview = const CyclePreviewBuilder().build(
        summary: summary,
        members: members,
        expenses: expenses,
        paymentMethods: paymentMethods,
        invoiceCodes: invoiceCodes,
        today: day,
      );

      final outside = <PaymentDueEntry>[
        for (final loan in loansInCycle.where((l) => !l.entersCycleSettlement))
          for (final i in loan.openInstallments)
            PaymentDueEntry(
              kind: PaymentDueKind.installment,
              date: DateTime(i.dueDate.year, i.dueDate.month, i.dueDate.day),
              title: '${loan.title} ${i.number}/${i.totalCount}',
              amount: i.remainingAmount,
              payerId: loan.borrowerMemberId,
              payerName: nameOf(loan.borrowerMemberId),
              receiverId: memberOrHouse(loan.lenderMemberId),
              receiverName: nameOf(loan.lenderMemberId),
            ),
      ]..sort((a, b) => a.date!.compareTo(b.date!));

      forecasts.add(
        UpcomingCycleForecast(preview: preview, outsideClosing: outside),
      );
    }

    final payoffs = <LoanPayoff>[
      for (final loan in active)
        if (loan.openInstallments.isNotEmpty)
          LoanPayoff(
            loanId: loan.id,
            title: loan.title,
            borrowerId: loan.borrowerMemberId,
            borrowerName: nameOf(loan.borrowerMemberId),
            lenderId: memberOrHouse(loan.lenderMemberId),
            lenderName: nameOf(loan.lenderMemberId),
            remaining: loan.remainingAmount,
            openInstallments: loan.openInstallments.length,
            lastDueDate: loan.openInstallments.last.dueDate,
          ),
    ]..sort((a, b) => a.lastDueDate.compareTo(b.lastDueDate));

    return UpcomingForecast(cycles: forecasts, payoffs: payoffs);
  }
}
