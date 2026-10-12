import 'package:equatable/equatable.dart';
import '../../../../core/domain/value_objects/financial_cycle.dart';
import '../../../finance/domain/entities/savings_vault.dart';
import '../../domain/entities/settlement_options.dart';
import '../../domain/entities/settlement_summary.dart';

enum SettlementCubitStatus {
  initial,
  loading,
  loaded,
  confirming,
  settled,
  error,
}

class SettlementState extends Equatable {
  final SettlementCubitStatus status;
  final FinancialCycle? currentCycle;
  final SettlementSummary? summary;
  final SettlementOptions options;
  final List<SavingsVault> vaults;
  final String? errorMessage;

  const SettlementState({
    this.status = SettlementCubitStatus.initial,
    this.currentCycle,
    this.summary,
    this.options = const SettlementOptions(),
    this.vaults = const [],
    this.errorMessage,
  });

  SettlementState copyWith({
    SettlementCubitStatus? status,
    FinancialCycle? currentCycle,
    SettlementSummary? summary,
    SettlementOptions? options,
    List<SavingsVault>? vaults,
    String? errorMessage,
  }) {
    return SettlementState(
      status: status ?? this.status,
      currentCycle: currentCycle ?? this.currentCycle,
      summary: summary ?? this.summary,
      options: options ?? this.options,
      vaults: vaults ?? this.vaults,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  @override
  List<Object?> get props => [
    status,
    currentCycle,
    summary,
    options,
    vaults,
    errorMessage,
  ];
}
