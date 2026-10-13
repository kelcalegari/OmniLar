import '../../../../core/domain/value_objects/financial_cycle.dart';
import '../../../../core/domain/value_objects/money.dart';
import 'member_audit_trail.dart';
import 'member_net_balance.dart';
import 'super_pix_transfer.dart';

enum SettlementStatus { open, readyToSettle, settled }

class SettlementSummary {
  final FinancialCycle cycle;
  final List<MemberNetBalance> memberBalances;
  final List<SuperPixTransfer> transfers;
  final Money totalHouseExpenses;
  final Money totalContributions;
  final Money totalP2PCleared;
  final Money houseTreasuryBalance;
  final SettlementStatus status;
  final DateTime? settledAt;
  final Map<String, MemberAuditTrail> auditTrails;

  /// Quanto os gastos passaram do balde (só no modelo de aportes fixos).
  final Money bucketDeficit;

  /// Parte do excedente coberta pela Caixinha escolhida no fechamento.
  final Money deficitCoveredByVault;

  /// O ciclo já foi fechado antes e está reaberto: só entra no acerto o que
  /// mudou desde o último fechamento.
  final bool isReopened;

  /// Versão dos dados da casa lida no banco antes do cálculo. O fechamento é
  /// recusado se ela já for outra na hora de gravar (null no modo demo).
  final String? dataVersion;

  const SettlementSummary({
    required this.cycle,
    required this.memberBalances,
    required this.transfers,
    required this.totalHouseExpenses,
    required this.totalContributions,
    required this.totalP2PCleared,
    required this.houseTreasuryBalance,
    this.status = SettlementStatus.readyToSettle,
    this.settledAt,
    this.auditTrails = const {},
    this.bucketDeficit = const Money.zero(),
    this.deficitCoveredByVault = const Money.zero(),
    this.isReopened = false,
    this.dataVersion,
  });

  /// Verifica se os saldos fecham matematicamente
  bool get isNetZeroSum {
    final sum = memberBalances.fold<int>(
      0,
      (acc, m) => acc + m.netBalance.cents,
    );
    return sum == 0;
  }

  /// Total de itens pessoais exclusivos embutidos em faturas/boletos da Casa
  Money get totalPersonalExpensesInBills {
    int cents = 0;
    for (final trail in auditTrails.values) {
      cents += trail.personalItemsSharesTotal.cents;
    }
    return Money(cents);
  }

  /// Total de despesas estritamente compartilhadas da Casa
  Money get totalSharedHouseExpenses {
    final diff = totalHouseExpenses.cents - totalPersonalExpensesInBills.cents;
    return diff > 0 ? Money(diff) : totalHouseExpenses;
  }

  SettlementSummary copyWith({
    FinancialCycle? cycle,
    List<MemberNetBalance>? memberBalances,
    List<SuperPixTransfer>? transfers,
    Money? totalHouseExpenses,
    Money? totalContributions,
    Money? totalP2PCleared,
    Money? houseTreasuryBalance,
    SettlementStatus? status,
    DateTime? settledAt,
    Map<String, MemberAuditTrail>? auditTrails,
    Money? bucketDeficit,
    Money? deficitCoveredByVault,
    bool? isReopened,
    String? dataVersion,
  }) {
    return SettlementSummary(
      cycle: cycle ?? this.cycle,
      memberBalances: memberBalances ?? this.memberBalances,
      transfers: transfers ?? this.transfers,
      totalHouseExpenses: totalHouseExpenses ?? this.totalHouseExpenses,
      totalContributions: totalContributions ?? this.totalContributions,
      totalP2PCleared: totalP2PCleared ?? this.totalP2PCleared,
      houseTreasuryBalance: houseTreasuryBalance ?? this.houseTreasuryBalance,
      status: status ?? this.status,
      settledAt: settledAt ?? this.settledAt,
      auditTrails: auditTrails ?? this.auditTrails,
      bucketDeficit: bucketDeficit ?? this.bucketDeficit,
      deficitCoveredByVault: deficitCoveredByVault ?? this.deficitCoveredByVault,
      isReopened: isReopened ?? this.isReopened,
      dataVersion: dataVersion ?? this.dataVersion,
    );
  }
}
