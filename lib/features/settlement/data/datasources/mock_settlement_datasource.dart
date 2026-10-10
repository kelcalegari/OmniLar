import '../../../../core/domain/value_objects/financial_cycle.dart';
import '../../../finance/data/datasources/finance_datasource.dart';
import '../../../p2p/data/datasources/p2p_datasource.dart';
import '../../domain/entities/settlement_summary.dart';
import '../../domain/entities/super_pix_transfer.dart';
import '../../domain/services/global_clearing_engine.dart';

class MockSettlementDataSource {
  final FinanceDataSource financeDataSource;
  final P2PDataSource p2pDataSource;
  final GlobalClearingEngine engine;

  SettlementSummary? _cachedSettlement;

  MockSettlementDataSource({
    required this.financeDataSource,
    required this.p2pDataSource,
    this.engine = const GlobalClearingEngine(),
  });

  Future<SettlementSummary> getSettlementSummary(FinancialCycle cycle) async {
    // Se já estiver liquidado em memória, devolve o estado atual
    if (_cachedSettlement != null && _cachedSettlement!.cycle == cycle) {
      return _cachedSettlement!;
    }

    final members = await financeDataSource.getMembers();
    final expenses = await financeDataSource.getExpensesForCycle(cycle);
    final contributions = await financeDataSource.getContributionsForCycle(cycle);
    final loans = await p2pDataSource.getLoans();

    final summary = engine.computeSettlement(
      cycle: cycle,
      members: members,
      expenses: expenses,
      contributions: contributions,
      loans: loans,
    );

    _cachedSettlement = summary;
    return summary;
  }

  Future<void> confirmSettlement(SettlementSummary summary) async {
    // 1. Marca as transferências como pagas
    final confirmedTransfers = summary.transfers.map((t) {
      return t.copyWith(
        status: TransferStatus.confirmed,
        paidAt: DateTime.now(),
      );
    }).toList();

    // 2. Atualiza estado de liquidação
    _cachedSettlement = summary.copyWith(
      status: SettlementStatus.settled,
      transfers: confirmedTransfers,
      settledAt: DateTime.now(),
    );

    // 3. Quita as parcelas P2P que venciam neste ciclo
    final loans = await p2pDataSource.getLoans();
    for (final loan in loans) {
      for (final inst in loan.installments) {
        if (summary.cycle.contains(inst.dueDate) && !inst.isFullyPaid) {
          await p2pDataSource.payInstallment(
            inst.id,
            inst.remainingAmount,
          );
        }
      }
    }
  }
}
