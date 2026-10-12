import '../../../../core/domain/value_objects/financial_cycle.dart';
import '../../domain/entities/settlement_options.dart';
import '../../domain/entities/settlement_summary.dart';
import 'settlement_datasource.dart';

class DynamicSettlementDataSource implements SettlementDataSource {
  final SettlementDataSource remote;
  final SettlementDataSource mock;
  final bool Function() isDemoMode;

  DynamicSettlementDataSource({
    required this.remote,
    required this.mock,
    required this.isDemoMode,
  });

  SettlementDataSource get _active => isDemoMode() ? mock : remote;

  @override
  Future<SettlementSummary> getSettlementSummary(FinancialCycle cycle) =>
      _active.getSettlementSummary(cycle);

  @override
  Future<void> confirmSettlement(
    SettlementSummary summary, {
    SettlementOptions? options,
  }) =>
      _active.confirmSettlement(summary, options: options);

  @override
  Future<void> reopenSettlement(FinancialCycle cycle) =>
      _active.reopenSettlement(cycle);
}
