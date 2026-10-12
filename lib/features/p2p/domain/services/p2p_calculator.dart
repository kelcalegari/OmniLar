import '../../../../core/domain/value_objects/money.dart';
import '../entities/p2p_installment.dart';
import '../entities/p2p_loan.dart';

class P2PCalculator {
  P2PCalculator._();

  /// Divide o [totalAmount] em [installmentsCount] parcelas justas com vencimento mensal a partir de [firstDueDate].
  /// [paidInstallmentsCount] permite inicializar parcelas pregressas já como quitadas no passado.
  static List<P2PInstallment> generateInstallments({
    required String loanId,
    required Money totalAmount,
    required int installmentsCount,
    required DateTime firstDueDate,
    int paidInstallmentsCount = 0,
  }) {
    if (installmentsCount <= 0) {
      throw ArgumentError('O número de parcelas deve ser maior que zero');
    }

    final splitAmounts = totalAmount.splitEqually(installmentsCount);
    final installments = <P2PInstallment>[];

    for (int i = 0; i < installmentsCount; i++) {
      // Adiciona i meses à data de primeiro vencimento
      final dueMonth = firstDueDate.month + i;
      final dueYear = firstDueDate.year + ((dueMonth - 1) ~/ 12);
      final normalizedMonth = ((dueMonth - 1) % 12) + 1;
      final maxDayInMonth = DateTime(dueYear, normalizedMonth + 1, 0).day;
      final safeDay = firstDueDate.day > maxDayInMonth ? maxDayInMonth : firstDueDate.day;

      final dueDate = DateTime(dueYear, normalizedMonth, safeDay);
      final isPaid = i < paidInstallmentsCount;

      installments.add(
        P2PInstallment(
          id: '${loanId}_inst_${i + 1}',
          loanId: loanId,
          number: i + 1,
          totalCount: installmentsCount,
          amount: splitAmounts[i],
          paidAmount: isPaid ? splitAmounts[i] : const Money.zero(),
          dueDate: dueDate,
          paidAt: isPaid ? dueDate : null,
        ),
      );
    }

    return installments;
  }

  /// Gera a parcela única de "saldo aberto" de um empréstimo sem prazo.
  /// [alreadyPaid] permite registrar abatimentos feitos antes de usar o Omni Lar.
  static List<P2PInstallment> buildOpenEndedInstallment({
    required String loanId,
    required Money totalAmount,
    Money alreadyPaid = const Money.zero(),
    DateTime? paidAt,
  }) {
    if (!totalAmount.isPositive) {
      throw ArgumentError('O valor do empréstimo deve ser maior que zero');
    }
    int paidCents = alreadyPaid.cents;
    if (paidCents < 0) paidCents = 0;
    if (paidCents > totalAmount.cents) paidCents = totalAmount.cents;
    return [
      P2PInstallment(
        id: '${loanId}_inst_1',
        loanId: loanId,
        number: 1,
        totalCount: 1,
        amount: totalAmount,
        paidAmount: Money(paidCents),
        dueDate: P2PLoan.openEndedPlaceholderDueDate,
        paidAt: paidCents > 0 ? (paidAt ?? DateTime.now()) : null,
      ),
    ];
  }

  /// Calcula a soma total do valor nominal de todas as parcelas.
  static Money sumInstallments(List<P2PInstallment> installments) {
    int totalCents = 0;
    for (final inst in installments) {
      totalCents += inst.amount.cents;
    }
    return Money(totalCents);
  }

  /// Ajusta a diferença entre a soma das parcelas e o valor total na última parcela em aberto (ou na última geral).
  static List<P2PInstallment> balanceLastInstallment({
    required List<P2PInstallment> installments,
    required Money totalAmount,
  }) {
    if (installments.isEmpty) return installments;
    final currentSum = sumInstallments(installments);
    final diff = totalAmount.cents - currentSum.cents;
    if (diff == 0) return installments;

    int targetIndex = installments.lastIndexWhere((i) => !i.isFullyPaid);
    if (targetIndex == -1) targetIndex = installments.length - 1;

    final target = installments[targetIndex];
    final newAmountCents = target.amount.cents + diff;
    if (newAmountCents < 0) return installments;

    final updated = List<P2PInstallment>.from(installments);
    updated[targetIndex] = target.copyWith(
      amount: Money(newAmountCents),
      paidAmount: target.isFullyPaid ? Money(newAmountCents) : target.paidAmount,
    );
    return updated;
  }
}
