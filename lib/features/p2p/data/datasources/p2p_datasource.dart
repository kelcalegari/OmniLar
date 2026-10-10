import '../../domain/entities/p2p_loan.dart';
import '../../../../core/domain/value_objects/money.dart';

abstract class P2PDataSource {
  Future<List<P2PLoan>> getLoans();
  Future<void> createLoan(P2PLoan loan);
  Future<void> payInstallment(String installmentId, Money amount);
  Future<void> forgiveLoan(String loanId);
  Future<void> renegotiateLoan(String loanId, int newInstallmentsCount, DateTime newFirstDueDate);
}
