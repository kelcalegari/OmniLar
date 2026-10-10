import '../../domain/entities/p2p_loan.dart';
import '../../domain/repositories/p2p_repository.dart';
import '../datasources/mock_p2p_datasource.dart';
import '../../../../core/domain/value_objects/money.dart';

class P2PRepositoryImpl implements P2PRepository {
  final MockP2PDataSource _dataSource;

  P2PRepositoryImpl(this._dataSource);

  @override
  Future<List<P2PLoan>> getLoans() => _dataSource.getLoans();

  @override
  Future<void> createLoan(P2PLoan loan) => _dataSource.createLoan(loan);

  @override
  Future<void> payInstallment(String installmentId, Money amount) =>
      _dataSource.payInstallment(installmentId, amount);

  @override
  Future<void> forgiveLoan(String loanId) => _dataSource.forgiveLoan(loanId);

  @override
  Future<void> renegotiateLoan(String loanId, int newInstallmentsCount, DateTime newFirstDueDate) =>
      _dataSource.renegotiateLoan(loanId, newInstallmentsCount, newFirstDueDate);
}
