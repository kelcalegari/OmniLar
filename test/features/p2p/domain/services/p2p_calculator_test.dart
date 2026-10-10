import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/features/p2p/domain/entities/p2p_installment.dart';
import 'package:omni_lar/features/p2p/domain/services/p2p_calculator.dart';

void main() {
  group('P2PCalculator & Installments', () {
    test('Gera parcelas dividindo centavos igualmente e somando exato', () {
      final total = Money.fromReal(100.00); // R$ 100,00
      final firstDueDate = DateTime(2026, 11, 10);

      final installments = P2PCalculator.generateInstallments(
        loanId: 'test_loan',
        totalAmount: total,
        installmentsCount: 3,
        firstDueDate: firstDueDate,
      );

      expect(installments.length, 3);
      expect(installments[0].amount.cents, 3334);
      expect(installments[1].amount.cents, 3333);
      expect(installments[2].amount.cents, 3333);

      final sum = installments.fold<Money>(const Money.zero(), (acc, inst) => acc + inst.amount);
      expect(sum.cents, total.cents);

      // Datas mensais
      expect(installments[0].dueDate, DateTime(2026, 11, 10));
      expect(installments[1].dueDate, DateTime(2026, 12, 10));
      expect(installments[2].dueDate, DateTime(2027, 1, 10));
    });

    test('Calcula saldo restante e status da parcela', () {
      final inst = P2PInstallment(
        id: 'inst_1',
        loanId: 'loan_1',
        number: 1,
        totalCount: 2,
        amount: const Money(10000), // R$ 100,00
        dueDate: DateTime(2026, 11, 10),
      );

      expect(inst.status, InstallmentStatus.pending);
      expect(inst.remainingAmount.cents, 10000);

      // Pagamento parcial de R$ 30,00
      final partial = inst.copyWith(paidAmount: const Money(3000));
      expect(partial.status, InstallmentStatus.partiallyPaid);
      expect(partial.remainingAmount.cents, 7000);

      // Pagamento total de R$ 100,00
      final paid = inst.copyWith(paidAmount: const Money(10000));
      expect(paid.status, InstallmentStatus.paid);
      expect(paid.remainingAmount.cents, 0);

      // Perdoada
      final forgiven = inst.copyWith(isForgiven: true);
      expect(forgiven.status, InstallmentStatus.forgiven);
      expect(forgiven.remainingAmount.cents, 0);
    });
  });
}
