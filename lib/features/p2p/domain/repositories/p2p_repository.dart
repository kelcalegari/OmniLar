import '../entities/p2p_loan.dart';
import '../entities/p2p_payment_record.dart';
import '../../../../core/domain/value_objects/money.dart';

abstract class P2PRepository {
  Future<List<P2PLoan>> getLoans();
  Future<void> createLoan(P2PLoan loan);
  Future<void> payInstallment(String installmentId, Money amount);

  /// Abate [amount] do empréstimo, distribuindo das parcelas mais antigas para as mais novas.
  Future<void> payLoan(String loanId, Money amount);

  /// Define se as parcelas são cobradas no Fechamento do Ciclo.
  Future<void> setSettleInCycle(String loanId, bool settleInCycle);
  Future<void> forgiveLoan(String loanId);
  Future<void> renegotiateLoan(String loanId, int newInstallmentsCount, DateTime newFirstDueDate);
  Future<void> deleteLoan(String loanId);
  Future<List<P2PPaymentRecord>> getLoanPayments(String loanId);
}
