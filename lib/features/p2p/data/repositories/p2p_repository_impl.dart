import '../../../../core/network/offline_queue.dart';
import '../../../../core/network/offline_sync_service.dart';
import '../../../../core/utils/uuid.dart';
import '../offline/p2p_loan_offline_codec.dart';
import '../../domain/entities/p2p_loan.dart';
import '../../domain/entities/p2p_payment_record.dart';
import '../../domain/repositories/p2p_repository.dart';
import '../datasources/p2p_datasource.dart';
import '../../../../core/domain/value_objects/money.dart';

class P2PRepositoryImpl implements P2PRepository {
  final P2PDataSource _dataSource;
  final OfflineSyncService? _offlineSync;

  P2PRepositoryImpl(this._dataSource, [this._offlineSync]);

  @override
  Future<List<P2PLoan>> getLoans() => _dataSource.getLoans();

  @override
  Future<void> createLoan(P2PLoan loan) async {
    final sync = _offlineSync;
    if (sync == null || !sync.isActive) return _dataSource.createLoan(loan);

    // Id real desde já: se o envio for repetido, o banco não cria o empréstimo em dobro
    final withId = isUuid(loan.id) ? loan : p2pLoanFromJson(p2pLoanToJson(loan, id: generateUuidV4()));
    await sync.runOrQueue(
      OfflineActionType.createLoan,
      () => p2pLoanToJson(withId),
      () => _dataSource.createLoan(withId),
    );
  }

  @override
  Future<void> payInstallment(String installmentId, Money amount, {String? vaultId}) =>
      _dataSource.payInstallment(installmentId, amount, vaultId: vaultId);

  @override
  Future<void> forgiveLoan(String loanId) => _dataSource.forgiveLoan(loanId);

  @override
  Future<void> renegotiateLoan(String loanId, int newInstallmentsCount, DateTime newFirstDueDate) =>
      _dataSource.renegotiateLoan(loanId, newInstallmentsCount, newFirstDueDate);

  @override
  Future<void> deleteLoan(String loanId) => _dataSource.deleteLoan(loanId);

  @override
  Future<List<P2PPaymentRecord>> getLoanPayments(String loanId) => _dataSource.getLoanPayments(loanId);

  @override
  Future<void> payLoan(String loanId, Money amount, {String? vaultId}) =>
      _dataSource.payLoan(loanId, amount, vaultId: vaultId);

  @override
  Future<void> setSettleInCycle(String loanId, bool settleInCycle) =>
      _dataSource.setSettleInCycle(loanId, settleInCycle);
}
