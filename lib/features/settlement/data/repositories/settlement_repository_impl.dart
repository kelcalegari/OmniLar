import '../../../../core/domain/value_objects/financial_cycle.dart';
import '../../domain/entities/settlement_options.dart';
import '../../domain/entities/settlement_summary.dart';
import '../../domain/repositories/settlement_repository.dart';
import '../datasources/settlement_datasource.dart';

class SettlementRepositoryImpl implements SettlementRepository {
  final SettlementDataSource _dataSource;

  SettlementRepositoryImpl(this._dataSource);

  @override
  Future<SettlementSummary> getSettlementSummary(
    FinancialCycle cycle, {
    SettlementOptions? options,
  }) => _dataSource.getSettlementSummary(cycle, options: options);

  @override
  Future<void> confirmSettlement(
    SettlementSummary summary, {
    SettlementOptions? options,
  }) => _dataSource.confirmSettlement(summary, options: options);

  @override
  Future<void> reopenSettlement(FinancialCycle cycle) =>
      _dataSource.reopenSettlement(cycle);

  @override
  Future<bool> isCycleSettled(FinancialCycle cycle) => _dataSource.isCycleSettled(cycle);
}
