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

    test('Gera empréstimo antigo com parcelas já pagas no passado', () {
      final total = const Money(200000); // R$ 2.000,00
      final firstDueDate = DateTime(2026, 5, 10);

      // 10 parcelas, 4 já pagas anteriormente
      final installments = P2PCalculator.generateInstallments(
        loanId: 'old_loan',
        totalAmount: total,
        installmentsCount: 10,
        firstDueDate: firstDueDate,
        paidInstallmentsCount: 4,
      );

      expect(installments.length, 10);
      for (int i = 0; i < 4; i++) {
        expect(installments[i].isFullyPaid, isTrue, reason: 'Parcela ${i + 1} deve nascer quitada');
        expect(installments[i].status, InstallmentStatus.paid);
        expect(installments[i].paidAmount, installments[i].amount);
        expect(installments[i].remainingAmount.cents, 0);
      }

      for (int i = 4; i < 10; i++) {
        expect(installments[i].isFullyPaid, isFalse, reason: 'Parcela ${i + 1} deve nascer em aberto');
        expect(installments[i].paidAmount.cents, 0);
        expect(installments[i].remainingAmount, installments[i].amount);
      }

      final sum = P2PCalculator.sumInstallments(installments);
      expect(sum.cents, total.cents);
    });

    test('Equilibra diferença na última parcela em aberto com balanceLastInstallment', () {
      final total = const Money(30000); // R$ 300,00 em 3x de R$ 100,00
      final firstDueDate = DateTime(2026, 11, 10);

      final installments = P2PCalculator.generateInstallments(
        loanId: 'custom_loan',
        totalAmount: total,
        installmentsCount: 3,
        firstDueDate: firstDueDate,
        paidInstallmentsCount: 1, // Parcela 1 já paga (R$ 100,00)
      );

      // Usuário edita parcela 2 manualmente para R$ 120,00 (+ R$ 20,00)
      final edited = List<P2PInstallment>.from(installments);
      edited[1] = edited[1].copyWith(amount: const Money(12000));

      expect(P2PCalculator.sumInstallments(edited).cents, 32000); // R$ 320,00

      // Ajusta na última parcela em aberto
      final balanced = P2PCalculator.balanceLastInstallment(
        installments: edited,
        totalAmount: total,
      );

      // Parcela 1 manteve R$ 100
      expect(balanced[0].amount.cents, 10000);
      // Parcela 2 manteve R$ 120
      expect(balanced[1].amount.cents, 12000);
      // Parcela 3 absorveu a diferença: R$ 80
      expect(balanced[2].amount.cents, 8000);

      expect(P2PCalculator.sumInstallments(balanced).cents, total.cents);
    });
  });
}
