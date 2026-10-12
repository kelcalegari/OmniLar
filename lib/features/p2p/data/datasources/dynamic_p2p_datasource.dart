import '../../domain/entities/p2p_loan.dart';
import '../../domain/entities/p2p_payment_record.dart';
import '../../../../core/domain/value_objects/money.dart';
import 'p2p_datasource.dart';

class DynamicP2PDataSource implements P2PDataSource {
  final P2PDataSource remote;
  final P2PDataSource mock;
  final bool Function() isDemoMode;

  DynamicP2PDataSource({
    required this.remote,
    required this.mock,
    required this.isDemoMode,
  });

  P2PDataSource get _active => isDemoMode() ? mock : remote;

  @override
  Future<List<P2PLoan>> getLoans() => _active.getLoans();

  @override
  Future<void> createLoan(P2PLoan loan) => _active.createLoan(loan);

  @override
  Future<void> payInstallment(String installmentId, Money amount) =>
      _active.payInstallment(installmentId, amount);

  @override
  Future<void> forgiveLoan(String loanId) => _active.forgiveLoan(loanId);

  @override
  Future<void> renegotiateLoan(String loanId, int newInstallmentsCount, DateTime newFirstDueDate) =>
      _active.renegotiateLoan(loanId, newInstallmentsCount, newFirstDueDate);

  @override
  Future<void> deleteLoan(String loanId) => _active.deleteLoan(loanId);

  @override
  Future<List<P2PPaymentRecord>> getLoanPayments(String loanId) => _active.getLoanPayments(loanId);

  @override
  Future<void> payLoan(String loanId, Money amount) => _active.payLoan(loanId, amount);

  @override
  Future<void> setSettleInCycle(String loanId, bool settleInCycle) =>
      _active.setSettleInCycle(loanId, settleInCycle);
}
