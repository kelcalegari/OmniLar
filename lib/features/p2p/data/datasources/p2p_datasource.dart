import '../../domain/entities/p2p_loan.dart';
import '../../domain/entities/p2p_payment_record.dart';
import '../../../../core/domain/value_objects/money.dart';

abstract class P2PDataSource {
  Future<List<P2PLoan>> getLoans();
  Future<void> createLoan(P2PLoan loan);
  /// [vaultId]: Caixinha que recebe o pagamento de um acordo com o Lar.
  Future<void> payInstallment(String installmentId, Money amount, {String? vaultId});

  /// Abate [amount] do empréstimo, distribuindo das parcelas mais antigas para as mais novas.
  Future<void> payLoan(String loanId, Money amount, {String? vaultId});

  /// Define se as parcelas são cobradas no Fechamento do Ciclo.
  Future<void> setSettleInCycle(String loanId, bool settleInCycle);
  Future<void> forgiveLoan(String loanId);
  Future<void> renegotiateLoan(String loanId, int newInstallmentsCount, DateTime newFirstDueDate);
  Future<void> deleteLoan(String loanId);

  /// Histórico de pagamentos/abatimentos registrados para o empréstimo (mais recente primeiro).
  Future<List<P2PPaymentRecord>> getLoanPayments(String loanId);
}
