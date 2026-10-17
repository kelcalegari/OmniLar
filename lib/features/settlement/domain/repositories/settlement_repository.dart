import '../../../../core/domain/value_objects/financial_cycle.dart';
import '../entities/settlement_options.dart';
import '../entities/settlement_summary.dart';

abstract class SettlementRepository {
  Future<SettlementSummary> getSettlementSummary(
    FinancialCycle cycle, {
    SettlementOptions? options,
  });
  Future<void> confirmSettlement(
    SettlementSummary summary, {
    SettlementOptions? options,
  });
  Future<void> reopenSettlement(FinancialCycle cycle);

  /// Se o ciclo já tem fechamento confirmado, sem montar o resumo inteiro.
  Future<bool> isCycleSettled(FinancialCycle cycle);

  /// Marca o Super Pix [recordId] como enviado (quem paga) ou recebido (quem recebe).
  Future<void> markTransferSent(String recordId);
}
