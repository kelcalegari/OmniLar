import '../../domain/entities/p2p_loan.dart';
import '../../domain/entities/p2p_installment.dart';
import '../../domain/entities/p2p_payment_record.dart';
import '../../domain/services/p2p_calculator.dart';
import '../../../../core/domain/value_objects/money.dart';

import 'p2p_datasource.dart';

class MockP2PDataSource implements P2PDataSource {
  final List<P2PLoan> _loans = [];
  final Map<String, List<P2PPaymentRecord>> _paymentsByLoan = {};

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

  @override
  Future<List<P2PLoan>> getLoans() async {
    return List.unmodifiable(_loans);
  }

  @override
  Future<void> createLoan(P2PLoan loan) async {
    // Como no banco: empréstimo criado sem parcelas ganha as parcelas aqui
    // (sem elas apareceria como quitado)
    final withInstallments = loan.installments.isEmpty && loan.installmentsCount > 0
        ? loan.copyWith(
            installments: P2PCalculator.generateInstallments(
              loanId: loan.id,
              totalAmount: loan.totalAmount,
              installmentsCount: loan.installmentsCount,
              firstDueDate: loan.firstDueDate,
            ),
          )
        : loan;
    _loans.insert(0, withInstallments);
  }

  Future<void> registerPayment({
    required String loanId,
    required String installmentId,
    required Money amount,
  }) =>
      payInstallment(installmentId, amount);

  /// Depósito em Caixinha (ligado ao financeiro de demonstração): como no
  /// banco, o pagamento de um acordo com o Lar pode ir para uma Caixinha.
  Future<void> Function(String vaultId, String memberId, Money amount, String description)?
      depositToVault;

  Future<void> _routeHouseLoanPayment(P2PLoan loan, Money amount, String? chosenVaultId) async {
    if (!loan.isHouseLender) return;
    final target = loan.repayToVaultId ?? chosenVaultId;
    if (target == null) return;
    await depositToVault?.call(
      target,
      loan.borrowerMemberId,
      amount,
      'Pagamento de acordo com o Lar: ${loan.title}',
    );
  }

  @override
  Future<void> payInstallment(String installmentId, Money amount, {String? vaultId}) async {
    for (int i = 0; i < _loans.length; i++) {
      final loan = _loans[i];
      final instIndex = loan.installments.indexWhere((inst) => inst.id == installmentId);
      if (instIndex != -1) {
        await _routeHouseLoanPayment(loan, amount, vaultId);
        final currentInst = loan.installments[instIndex];
        final newPaidAmount = currentInst.paidAmount + amount;
        final updatedInst = currentInst.copyWith(
          paidAmount: newPaidAmount,
          paidAt: DateTime.now(),
        );

        final updatedInstallments = List<P2PInstallment>.from(loan.installments);
        updatedInstallments[instIndex] = updatedInst;

        _paymentsByLoan
            .putIfAbsent(loan.id, () => [])
            .insert(0, P2PPaymentRecord(amount: amount, paidAt: DateTime.now()));

        final isAllPaid = updatedInstallments
            .every((inst) => inst.isFullyPaid || inst.isCancelled || inst.isForgiven);
        _loans[i] = loan.copyWith(
          installments: updatedInstallments,
          status: isAllPaid ? LoanStatus.paid : loan.status,
        );
        break;
      }
    }
  }

  @override
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

  @override
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

      final paidCount = updatedOldInstallments.where((i) => i.isFullyPaid).length;
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
            id: '${loanId}_reneg_${updatedOldInstallments.length + i + 1}',
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
        // Mantém as parcelas canceladas para preservar o valor já abatido nelas.
        installments: [...updatedOldInstallments, ...newInstallments],
        status: LoanStatus.renegotiated,
        // Ao definir um parcelamento, um empréstimo sem prazo passa a ser parcelado.
        repaymentMode: LoanRepaymentMode.installments,
      );
    }
  }

  @override
  Future<void> acceptLoan(String loanId) async {
    final index = _loans.indexWhere((l) => l.id == loanId);
    if (index != -1) _loans[index] = _loans[index].copyWith(awaitingAcceptance: false);
  }

  @override
  Future<void> declineLoan(String loanId) async {
    _loans.removeWhere((l) => l.id == loanId && l.awaitingAcceptance);
  }

  @override
  Future<void> deleteLoan(String loanId) async {
    _loans.removeWhere((l) => l.id == loanId);
  }

  @override
  Future<List<P2PPaymentRecord>> getLoanPayments(String loanId) async {
    return List.unmodifiable(_paymentsByLoan[loanId] ?? const []);
  }

  @override
  Future<void> payLoan(String loanId, Money amount, {String? vaultId}) async {
    final loan = _loans.where((l) => l.id == loanId).firstOrNull;
    if (loan == null) return;
    if (amount.cents <= 0 || amount.cents > loan.remainingAmount.cents) {
      throw ArgumentError('Valor inválido para abatimento do empréstimo');
    }

    int left = amount.cents;
    for (final inst in loan.openInstallments) {
      if (left <= 0) break;
      final part = left < inst.remainingAmount.cents ? left : inst.remainingAmount.cents;
      await payInstallment(inst.id, Money(part), vaultId: vaultId);
      left -= part;
    }
  }

  @override
  Future<void> setSettleInCycle(String loanId, bool settleInCycle) async {
    final index = _loans.indexWhere((l) => l.id == loanId);
    if (index != -1) {
      _loans[index] = _loans[index].copyWith(settleInCycle: settleInCycle);
    }
  }
}
