import '../../../../core/domain/value_objects/money.dart';
import '../entities/p2p_installment.dart';

class P2PCalculator {
  P2PCalculator._();

  /// Divide o [totalAmount] em [installmentsCount] parcelas justas com vencimento mensal a partir de [firstDueDate].
  static List<P2PInstallment> generateInstallments({
    required String loanId,
    required Money totalAmount,
    required int installmentsCount,
    required DateTime firstDueDate,
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

      installments.add(
        P2PInstallment(
          id: '${loanId}_inst_${i + 1}',
          loanId: loanId,
          number: i + 1,
          totalCount: installmentsCount,
          amount: splitAmounts[i],
          dueDate: dueDate,
        ),
      );
    }

    return installments;
  }
}
