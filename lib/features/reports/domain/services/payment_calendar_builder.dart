import '../../../finance/domain/entities/house_member.dart';
import '../../../finance/domain/entities/house_settings.dart';
import '../../../p2p/domain/entities/p2p_loan.dart';
import '../entities/cycle_preview.dart';
import '../entities/payment_due_entry.dart';

/// Monta o calendário de pagamentos do ciclo a partir da prévia do
/// fechamento e dos empréstimos.
///
/// Nada é contado duas vezes: parcela cobrada no fechamento já está dentro do
/// Super Pix e não vira linha própria; só entram as parcelas de empréstimos
/// que não passam pelo fechamento.
class PaymentCalendarBuilder {
  const PaymentCalendarBuilder();

  PaymentCalendar build({
    required CyclePreview preview,
    required List<P2PLoan> loans,
    required List<HouseMember> members,
    required DateTime today,
    String cashLabel = HouseSettings.defaultCashLabel,
  }) {
    final cycle = preview.cycle;
    final day = DateTime(today.year, today.month, today.day);
    if (preview.isSettled)
      return PaymentCalendar(cycle: cycle, entries: const [], today: day);

    final names = {for (final m in members) m.id: m.name};
    String nameOf(String? id) => id == null || id == P2PLoan.houseLenderId
        ? cashLabel
        : (names[id] ?? 'Membro');
    String? memberOrHouse(String id) => id == P2PLoan.houseLenderId ? null : id;
    final memberIds = names.keys.toSet();

    final entries = <PaymentDueEntry>[];

    // Faturas e contas em aberto, com quem a prévia considera que paga
    for (final a in preview.assumedPayments) {
      entries.add(
        PaymentDueEntry(
          kind: a.isInvoice ? PaymentDueKind.invoice : PaymentDueKind.bill,
          date: a.dueDate,
          title: a.title,
          amount: a.amount,
          payerId: a.payerMemberId,
          payerName: nameOf(a.payerMemberId),
          isOverdue: a.isOverdue,
          reimbursedAtClosing: a.payerMemberId != null,
          barcode: a.barcode,
        ),
      );
    }

    // Parcelas de empréstimos que não passam pelo fechamento
    final cycleHasStarted = !cycle.startDate.isAfter(day);
    for (final loan in loans) {
      if (loan.status == LoanStatus.paid || loan.status == LoanStatus.forgiven)
        continue;
      if (!memberIds.contains(loan.borrowerMemberId)) continue;
      if (loan.isOpenEnded) {
        final remaining = loan.remainingAmount;
        if (!remaining.isPositive) continue;
        entries.add(
          PaymentDueEntry(
            kind: PaymentDueKind.openEnded,
            date: null,
            title: loan.title,
            amount: remaining,
            payerId: loan.borrowerMemberId,
            payerName: nameOf(loan.borrowerMemberId),
            receiverId: memberOrHouse(loan.lenderMemberId),
            receiverName: nameOf(loan.lenderMemberId),
          ),
        );
        continue;
      }
      if (loan.entersCycleSettlement) continue;
      for (final i in loan.openInstallments) {
        final due = DateTime(i.dueDate.year, i.dueDate.month, i.dueDate.day);
        if (due.isAfter(cycle.endDate)) continue;
        // Ciclo futuro mostra só o que vence nele; o atrasado pesa no atual
        if (!cycleHasStarted && due.isBefore(cycle.startDate)) continue;
        entries.add(
          PaymentDueEntry(
            kind: PaymentDueKind.installment,
            date: due,
            title: '${loan.title} ${i.number}/${i.totalCount}',
            amount: i.remainingAmount,
            payerId: loan.borrowerMemberId,
            payerName: nameOf(loan.borrowerMemberId),
            receiverId: memberOrHouse(loan.lenderMemberId),
            receiverName: nameOf(loan.lenderMemberId),
            isOverdue: due.isBefore(day),
          ),
        );
      }
    }

    // Super Pix do fechamento, no último dia do ciclo
    final closingDay = DateTime(
      cycle.endDate.year,
      cycle.endDate.month,
      cycle.endDate.day,
    );
    final seen = <String>{};
    for (final member in preview.members) {
      for (final t in [...member.transfersOut, ...member.transfersIn]) {
        if (!seen.add(t.id)) continue;
        entries.add(
          PaymentDueEntry(
            kind: PaymentDueKind.closing,
            date: closingDay,
            title: 'Super Pix do fechamento',
            amount: t.amount,
            payerId: memberOrHouse(t.fromMemberId),
            payerName: memberIds.contains(t.fromMemberId)
                ? nameOf(t.fromMemberId)
                : t.fromMemberName,
            receiverId: memberOrHouse(t.toMemberId),
            receiverName: memberIds.contains(t.toMemberId)
                ? nameOf(t.toMemberId)
                : t.toMemberName,
            isOverdue: closingDay.isBefore(day),
          ),
        );
      }
    }

    entries.sort((a, b) {
      if (a.date == null || b.date == null) {
        return a.date == null ? (b.date == null ? 0 : 1) : -1;
      }
      final byDate = a.date!.compareTo(b.date!);
      if (byDate != 0) return byDate;
      // No mesmo dia, o fechamento vem por último
      return (a.kind == PaymentDueKind.closing ? 1 : 0) -
          (b.kind == PaymentDueKind.closing ? 1 : 0);
    });
    return PaymentCalendar(cycle: cycle, entries: entries, today: day);
  }
}
