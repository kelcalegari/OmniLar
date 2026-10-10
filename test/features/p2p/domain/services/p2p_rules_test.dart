import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/features/p2p/data/datasources/mock_p2p_datasource.dart';
import 'package:omni_lar/features/p2p/data/repositories/p2p_repository_impl.dart';
import 'package:omni_lar/features/p2p/domain/entities/p2p_loan.dart';
import 'package:omni_lar/features/p2p/domain/entities/p2p_installment.dart';

void main() {
  group('P2P Advanced Engine (RN02, RN03, RN04)', () {
    late MockP2PDataSource dataSource;
    late P2PRepositoryImpl repository;

    setUp(() {
      dataSource = MockP2PDataSource();
      repository = P2PRepositoryImpl(dataSource);
    });

    test('RN02: Pagamento parcial atualiza saldo restante e mantém status partiallyPaid até quitação', () async {
      final loans = await repository.getLoans();
      // loan_furadeira tem 1 parcela de R$ 250,00 (25000 cents)
      final furadeira = loans.firstWhere((l) => l.id == 'loan_furadeira');
      final instId = furadeira.installments.first.id;

      // Paga R$ 100,00 (10000 cents) parcialmente
      await repository.payInstallment(instId, const Money(10000));

      final updatedLoans = await repository.getLoans();
      final updatedFuradeira = updatedLoans.firstWhere((l) => l.id == 'loan_furadeira');
      final updatedInst = updatedFuradeira.installments.first;

      expect(updatedInst.status, InstallmentStatus.partiallyPaid);
      expect(updatedInst.paidAmount.cents, 10000);
      expect(updatedInst.remainingAmount.cents, 15000); // 25000 - 10000 = 15000
      expect(updatedFuradeira.status, LoanStatus.active); // Continua ativo

      // Paga os R$ 150,00 restantes
      await repository.payInstallment(instId, const Money(15000));

      final fullyPaidLoans = await repository.getLoans();
      final fullyPaidFuradeira = fullyPaidLoans.firstWhere((l) => l.id == 'loan_furadeira');
      final fullyPaidInst = fullyPaidFuradeira.installments.first;

      expect(fullyPaidInst.status, InstallmentStatus.paid);
      expect(fullyPaidInst.isFullyPaid, isTrue);
      expect(fullyPaidInst.remainingAmount.cents, 0);
      expect(fullyPaidFuradeira.status, LoanStatus.paid); // Empréstimo agora quitado
    });

    test('RN03: Perdão de dívida (Anistia) zera saldo restante sem apagar histórico', () async {
      final loans = await repository.getLoans();
      final zara = loans.firstWhere((l) => l.id == 'loan_zara');
      expect(zara.remainingAmount.cents, greaterThan(0));

      // Credor perdoa a dívida
      await repository.forgiveLoan(zara.id);

      final updatedLoans = await repository.getLoans();
      final forgivenZara = updatedLoans.firstWhere((l) => l.id == 'loan_zara');

      expect(forgivenZara.status, LoanStatus.forgiven);
      expect(forgivenZara.remainingAmount.cents, 0);
      // As parcelas não pagas foram marcadas como perdoadas
      final unpaidInsts = forgivenZara.installments.where((i) => !i.isFullyPaid);
      expect(unpaidInsts.every((i) => i.isForgiven), isTrue);
    });

    test('RN04: Renegociação cancela parcelas pendentes e cria novas com o saldo restante', () async {
      final loans = await repository.getLoans();
      final passagem = loans.firstWhere((l) => l.id == 'loan_passagem');
      // Passagem tem 4 parcelas de 20000, 2 já foram pagas (saldo restante = 40000)
      final remainingBefore = passagem.remainingAmount;
      expect(remainingBefore.cents, 40000);

      // Renegocia em 4 novas parcelas
      final newFirstDate = DateTime(2027, 1, 15);
      await repository.renegotiateLoan(passagem.id, 4, newFirstDate);

      final updatedLoans = await repository.getLoans();
      final renegotiated = updatedLoans.firstWhere((l) => l.id == 'loan_passagem');

      expect(renegotiated.status, LoanStatus.renegotiated);
      // As parcelas ativas novas somam o saldo restante exato de 40000 (10000 cada)
      final activeNewInsts = renegotiated.installments.where((i) => !i.isFullyPaid && !i.isCancelled).toList();
      expect(activeNewInsts.length, 4);
      final sumNew = activeNewInsts.fold<int>(0, (acc, i) => acc + i.amount.cents);
      expect(sumNew, 40000);
      expect(activeNewInsts[0].dueDate, newFirstDate);
    });
  });
}
