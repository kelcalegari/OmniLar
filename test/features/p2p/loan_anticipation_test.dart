import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/domain/value_objects/financial_cycle.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/features/finance/domain/entities/house_member.dart';
import 'package:omni_lar/features/p2p/data/datasources/mock_p2p_datasource.dart';
import 'package:omni_lar/features/p2p/domain/entities/p2p_loan.dart';
import 'package:omni_lar/features/p2p/domain/services/p2p_calculator.dart';
import 'package:omni_lar/features/settlement/domain/services/global_clearing_engine.dart';

P2PLoan _installmentLoan({
  String id = 'loan_parc',
  DateTime? firstDueDate,
  bool settleInCycle = true,
}) {
  final first = firstDueDate ?? DateTime(2026, 10, 20);
  return P2PLoan(
    id: id,
    title: 'Parcelado',
    totalAmount: const Money(30000),
    lenderMemberId: 'member_carlos',
    borrowerMemberId: 'member_marina',
    installmentsCount: 3,
    createdAt: DateTime(2026, 10, 1),
    firstDueDate: first,
    installments: P2PCalculator.generateInstallments(
      loanId: id,
      totalAmount: const Money(30000),
      installmentsCount: 3,
      firstDueDate: first,
    ),
    settleInCycle: settleInCycle,
  );
}

void main() {
  group('Abatimento livre em empréstimo parcelado', () {
    test('Distribui das parcelas mais antigas para as mais novas', () async {
      final ds = MockP2PDataSource();
      await ds.createLoan(_installmentLoan());

      // 1 parcela inteira (10000) + metade da seguinte
      await ds.payLoan('loan_parc', const Money(15000));

      final loan = (await ds.getLoans()).firstWhere((l) => l.id == 'loan_parc');
      expect(loan.installments[0].isFullyPaid, isTrue);
      expect(loan.installments[1].paidAmount.cents, 5000);
      expect(loan.installments[2].paidAmount.cents, 0);
      expect(loan.remainingAmount.cents, 15000);
      expect(loan.status, LoanStatus.active);
    });

    test('Quitar tudo marca o empréstimo como pago', () async {
      final ds = MockP2PDataSource();
      await ds.createLoan(_installmentLoan());

      await ds.payLoan('loan_parc', const Money(30000));

      final loan = (await ds.getLoans()).firstWhere((l) => l.id == 'loan_parc');
      expect(loan.remainingAmount.cents, 0);
      expect(loan.status, LoanStatus.paid);
    });

    test('Rejeita valor acima do saldo devedor', () async {
      final ds = MockP2PDataSource();
      await ds.createLoan(_installmentLoan());

      expect(() => ds.payLoan('loan_parc', const Money(30001)), throwsArgumentError);
    });
  });

  group('Fechamento do Ciclo - antecipação, atraso e fora do ciclo', () {
    const engine = GlobalClearingEngine();
    final cycle = FinancialCycle(
      start: DateTime(2026, 10, 5),
      end: DateTime(2026, 11, 4),
    );
    const members = [
      HouseMember(id: 'member_carlos', name: 'Carlos', role: 'owner'),
      HouseMember(id: 'member_marina', name: 'Marina', role: 'member'),
    ];

    int clearedCents(List<P2PLoan> loans) => engine
        .computeSettlement(
          cycle: cycle,
          members: members,
          expenses: const [],
          contributions: const [],
          loans: loans,
        )
        .totalP2PCleared
        .cents;

    test('Parcela antecipada não é cobrada de novo no fechamento', () async {
      final ds = MockP2PDataSource();
      await ds.createLoan(_installmentLoan());
      expect(clearedCents([(await ds.getLoans()).firstWhere((l) => l.id == 'loan_parc')]), 10000);

      await ds.payLoan('loan_parc', const Money(10000));
      expect(clearedCents([(await ds.getLoans()).firstWhere((l) => l.id == 'loan_parc')]), 0);
    });

    test('Parcela atrasada de ciclo anterior entra no fechamento atual', () {
      // Vencimentos: 20/09 (atrasada), 20/10 (no ciclo), 20/11 (futuro)
      final loan = _installmentLoan(firstDueDate: DateTime(2026, 9, 20));
      expect(clearedCents([loan]), 20000);
    });

    test('Empréstimo fora do ciclo nunca entra no fechamento', () {
      expect(clearedCents([_installmentLoan(settleInCycle: false)]), 0);
    });

    test('Parcela cancelada por renegociação não é cobrada', () {
      final loan = _installmentLoan();
      final withCancelled = loan.copyWith(
        installments: [
          loan.installments[0].copyWith(isCancelled: true),
          ...loan.installments.skip(1),
        ],
      );
      expect(withCancelled.installmentsChargedIn(cycle), isEmpty);
    });
  });
}
