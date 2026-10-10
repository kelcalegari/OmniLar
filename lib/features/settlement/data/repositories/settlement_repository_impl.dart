import '../../../../core/domain/value_objects/financial_cycle.dart';
import '../../domain/entities/settlement_summary.dart';
import '../../domain/repositories/settlement_repository.dart';
import '../datasources/mock_settlement_datasource.dart';

class SettlementRepositoryImpl implements SettlementRepository {
  final MockSettlementDataSource _dataSource;

  SettlementRepositoryImpl(this._dataSource);

  @override
  Future<SettlementSummary> getSettlementSummary(FinancialCycle cycle) =>
      _dataSource.getSettlementSummary(cycle);

  @override
  Future<void> confirmSettlement(SettlementSummary summary) =>
      _dataSource.confirmSettlement(summary);
}
