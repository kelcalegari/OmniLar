import '../../domain/entities/p2p_loan.dart';
import '../../domain/entities/p2p_installment.dart';
import '../../domain/services/p2p_calculator.dart';
import '../../../../core/domain/value_objects/money.dart';

class MockP2PDataSource {
  final List<P2PLoan> _loans = [];

  MockP2PDataSource() {
    final now = DateTime.now();

    // 1. Camisa Zara (Marina deve para Carlos)
    final loan1Id = 'loan_zara';
    final loan1Date = DateTime(now.year, now.month - 1, 10);
    final loan1Installments = P2PCalculator.generateInstallments(
      loanId: loan1Id,
      totalAmount: const Money(18000), // R$ 180,00
      installmentsCount: 3,
      firstDueDate: loan1Date,
    );
    // Parcela 1 paga
    loan1Installments[0] = loan1Installments[0].copyWith(
      paidAmount: const Money(6000),
      paidAt: DateTime(now.year, now.month - 1, 10),
    );

    _loans.add(
      P2PLoan(
        id: loan1Id,
        title: 'Camisa Zara (Cartão Carlos)',
        description: 'Compra no shopping com o cartão do Carlos',
        totalAmount: const Money(18000),
        lenderMemberId: 'member_carlos',
        borrowerMemberId: 'member_marina',
        installmentsCount: 3,
        createdAt: loan1Date,
        firstDueDate: loan1Date,
        installments: loan1Installments,
      ),
    );

    // 2. Conserto Furadeira (Carlos deve para Marina)
    final loan2Id = 'loan_furadeira';
    final loan2Date = DateTime(now.year, now.month, 15);
    final loan2Installments = P2PCalculator.generateInstallments(
      loanId: loan2Id,
      totalAmount: const Money(25000), // R$ 250,00
      installmentsCount: 1,
      firstDueDate: loan2Date,
    );

    _loans.add(
      P2PLoan(
        id: loan2Id,
        title: 'Conserto da Furadeira',
        description: 'Marina pagou no Pix da assistência técnica',
        totalAmount: const Money(25000),
        lenderMemberId: 'member_marina',
        borrowerMemberId: 'member_carlos',
        installmentsCount: 1,
        createdAt: loan2Date,
        firstDueDate: loan2Date,
        installments: loan2Installments,
      ),
    );

    // 3. Passagem Aérea Férias (Marina deve para Carlos)
    final loan3Id = 'loan_passagem';
    final loan3Date = DateTime(now.year, now.month - 2, 5);
    final loan3Installments = P2PCalculator.generateInstallments(
      loanId: loan3Id,
      totalAmount: const Money(80000), // R$ 800,00
      installmentsCount: 4,
      firstDueDate: loan3Date,
    );
    // Parcelas 1 e 2 pagas
    loan3Installments[0] = loan3Installments[0].copyWith(
      paidAmount: const Money(20000),
      paidAt: DateTime(now.year, now.month - 2, 5),
    );
    loan3Installments[1] = loan3Installments[1].copyWith(
      paidAmount: const Money(20000),
      paidAt: DateTime(now.year, now.month - 1, 5),
    );

    _loans.add(
      P2PLoan(
        id: loan3Id,
        title: 'Passagem Aérea das Férias',
        description: 'Passagens compradas no cartão Smiles',
        totalAmount: const Money(80000),
        lenderMemberId: 'member_carlos',
        borrowerMemberId: 'member_marina',
        installmentsCount: 4,
        createdAt: loan3Date,
        firstDueDate: loan3Date,
        installments: loan3Installments,
      ),
    );
  }

  Future<List<P2PLoan>> getLoans() async {
    return List.unmodifiable(_loans);
  }

  Future<void> createLoan(P2PLoan loan) async {
    _loans.insert(0, loan);
  }

  Future<void> registerPayment({
    required String loanId,
    required String installmentId,
    required Money amount,
  }) =>
      payInstallment(installmentId, amount);

  Future<void> payInstallment(String installmentId, Money amount) async {
    for (int i = 0; i < _loans.length; i++) {
      final loan = _loans[i];
      final instIndex = loan.installments.indexWhere((inst) => inst.id == installmentId);
      if (instIndex != -1) {
        final currentInst = loan.installments[instIndex];
        final newPaidAmount = currentInst.paidAmount + amount;
        final updatedInst = currentInst.copyWith(
          paidAmount: newPaidAmount,
          paidAt: DateTime.now(),
        );

        final updatedInstallments = List<P2PInstallment>.from(loan.installments);
        updatedInstallments[instIndex] = updatedInst;

        final isAllPaid = updatedInstallments.every((inst) => inst.isFullyPaid);
        _loans[i] = loan.copyWith(
          installments: updatedInstallments,
          status: isAllPaid ? LoanStatus.paid : loan.status,
        );
        break;
      }
    }
  }

  Future<void> forgiveLoan(String loanId) async {
    final index = _loans.indexWhere((l) => l.id == loanId);
    if (index != -1) {
      final loan = _loans[index];
      final updatedInstallments = loan.installments.map((inst) {
        if (!inst.isFullyPaid) {
          return inst.copyWith(isForgiven: true);
        }
        return inst;
      }).toList();

      _loans[index] = loan.copyWith(
        status: LoanStatus.forgiven,
        installments: updatedInstallments,
      );
    }
  }

  Future<void> renegotiateLoan(String loanId, int newInstallmentsCount, DateTime newFirstDueDate) async {
    final index = _loans.indexWhere((l) => l.id == loanId);
    if (index != -1) {
      final loan = _loans[index];
      final remaining = loan.remainingAmount;

      // Cancela as parcelas pendentes antigas
      final updatedOldInstallments = loan.installments.map((inst) {
        if (!inst.isFullyPaid) {
          return inst.copyWith(isCancelled: true);
        }
        return inst;
      }).toList();

      final paidOldInstallments = updatedOldInstallments.where((i) => i.isFullyPaid).toList();
      final paidCount = paidOldInstallments.length;
      final totalCombinedCount = paidCount + newInstallmentsCount;

      // Gera as novas parcelas sequenciais a partir do paidCount
      final splitAmounts = remaining.splitEqually(newInstallmentsCount);
      final newInstallments = <P2PInstallment>[];

      for (int i = 0; i < newInstallmentsCount; i++) {
        final dueMonth = newFirstDueDate.month + i;
        final dueYear = newFirstDueDate.year + ((dueMonth - 1) ~/ 12);
        final normalizedMonth = ((dueMonth - 1) % 12) + 1;
        final maxDayInMonth = DateTime(dueYear, normalizedMonth + 1, 0).day;
        final safeDay = newFirstDueDate.day > maxDayInMonth ? maxDayInMonth : newFirstDueDate.day;
        final dueDate = DateTime(dueYear, normalizedMonth, safeDay);

        newInstallments.add(
          P2PInstallment(
            id: '${loanId}_reneg_${i + 1}',
            loanId: loanId,
            number: paidCount + i + 1,
            totalCount: totalCombinedCount,
            amount: splitAmounts[i],
            dueDate: dueDate,
          ),
        );
      }

      _loans[index] = loan.copyWith(
        installmentsCount: totalCombinedCount,
        installments: [...paidOldInstallments, ...newInstallments],
        status: LoanStatus.renegotiated,
      );
    }
  }
}
