import '../../../../core/domain/value_objects/financial_cycle.dart';
import '../../../finance/data/datasources/mock_finance_datasource.dart';
import '../../../p2p/data/datasources/mock_p2p_datasource.dart';
import '../../domain/entities/settlement_summary.dart';
import '../../domain/entities/super_pix_transfer.dart';
import '../../domain/services/global_clearing_engine.dart';

class MockSettlementDataSource {
  final MockFinanceDataSource _financeDataSource;
  final MockP2PDataSource _p2pDataSource;
  final GlobalClearingEngine _engine;

  SettlementSummary? _cachedSettlement;

  MockSettlementDataSource({
    required MockFinanceDataSource financeDataSource,
    required MockP2PDataSource p2pDataSource,
    GlobalClearingEngine engine = const GlobalClearingEngine(),
  })  : _financeDataSource = financeDataSource,
        _p2pDataSource = p2pDataSource,
        _engine = engine;

  Future<SettlementSummary> getSettlementSummary(FinancialCycle cycle) async {
    // Se já estiver liquidado em memória, devolve o estado atual
    if (_cachedSettlement != null && _cachedSettlement!.cycle == cycle) {
      return _cachedSettlement!;
    }

    final members = await _financeDataSource.getMembers();
    final expenses = await _financeDataSource.getExpensesForCycle(cycle);
    final contributions = await _financeDataSource.getContributionsForCycle(cycle);
    final loans = await _p2pDataSource.getLoans();

    final summary = _engine.computeSettlement(
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
    final loans = await _p2pDataSource.getLoans();
    for (final loan in loans) {
      for (final inst in loan.installments) {
        if (summary.cycle.contains(inst.dueDate) && !inst.isFullyPaid) {
          await _p2pDataSource.registerPayment(
            loanId: loan.id,
            installmentId: inst.id,
            amount: inst.remainingAmount,
          );
        }
      }
    }
  }
}
