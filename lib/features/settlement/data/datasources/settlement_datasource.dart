import '../../../../core/domain/value_objects/financial_cycle.dart';
import '../../domain/entities/settlement_options.dart';
import '../../domain/entities/settlement_summary.dart';

abstract class SettlementDataSource {
  Future<SettlementSummary> getSettlementSummary(
    FinancialCycle cycle, {
    SettlementOptions? options,
  });
  Future<void> confirmSettlement(
    SettlementSummary summary, {
    SettlementOptions? options,
  });
  Future<void> reopenSettlement(FinancialCycle cycle);
}
