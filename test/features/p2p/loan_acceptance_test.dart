import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/domain/value_objects/financial_cycle.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/features/p2p/data/datasources/mock_p2p_datasource.dart';
import 'package:omni_lar/features/p2p/domain/entities/p2p_loan.dart';
import 'package:omni_lar/features/p2p/domain/services/p2p_calculator.dart';

P2PLoan _loan({required bool awaiting}) {
  final due = DateTime(2026, 10, 10);
  return P2PLoan(
    id: 'loan_aceite',
    title: 'Conserto da bicicleta',
    totalAmount: const Money(30000),
    lenderMemberId: 'member_carlos',
    borrowerMemberId: 'member_marina',
    installmentsCount: 3,
    createdAt: DateTime(2026, 10, 1),
    firstDueDate: due,
    installments: P2PCalculator.generateInstallments(
      loanId: 'loan_aceite',
      totalAmount: const Money(30000),
      installmentsCount: 3,
      firstDueDate: due,
    ),
    awaitingAcceptance: awaiting,
  );
}

void main() {
  final cycle = FinancialCycle(start: DateTime(2026, 10, 5), end: DateTime(2026, 11, 4));

  test('Empréstimo não aceito fica fora do fechamento', () {
    expect(_loan(awaiting: true).entersCycleSettlement, isFalse);
    expect(_loan(awaiting: true).installmentsChargedIn(cycle), isEmpty);
  });

  test('Depois do aceite, a parcela do ciclo é cobrada', () {
    expect(_loan(awaiting: false).entersCycleSettlement, isTrue);
    expect(_loan(awaiting: false).installmentsChargedIn(cycle), hasLength(1));
  });

  test('Demo: aceitar tira da espera e recusar remove o empréstimo', () async {
    final source = MockP2PDataSource();
    await source.createLoan(_loan(awaiting: true));
    await source.acceptLoan('loan_aceite');
    var loans = await source.getLoans();
    expect(loans.firstWhere((l) => l.id == 'loan_aceite').awaitingAcceptance, isFalse);

    await source.deleteLoan('loan_aceite');
    await source.createLoan(_loan(awaiting: true));
    await source.declineLoan('loan_aceite');
    loans = await source.getLoans();
    expect(loans.where((l) => l.id == 'loan_aceite'), isEmpty);
  });
}
