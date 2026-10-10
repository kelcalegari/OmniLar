import '../../../../core/domain/value_objects/financial_cycle.dart';
import '../entities/settlement_summary.dart';

abstract class SettlementRepository {
  Future<SettlementSummary> getSettlementSummary(FinancialCycle cycle);
  Future<void> confirmSettlement(SettlementSummary summary);
}
