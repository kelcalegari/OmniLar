import 'package:equatable/equatable.dart';
import '../../../../core/domain/value_objects/financial_cycle.dart';
import '../../../finance/domain/entities/savings_vault.dart';
import '../../../finance/domain/services/cycle_expense_grouping.dart';
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

  /// Faturas de cartão em aberto que pesam no ciclo.
  final List<CardInvoiceEntry> openInvoices;
  final String? errorMessage;

  const SettlementState({
    this.status = SettlementCubitStatus.initial,
    this.currentCycle,
    this.summary,
    this.options = const SettlementOptions(),
    this.vaults = const [],
    this.openInvoices = const [],
    this.errorMessage,
  });

  SettlementState copyWith({
    SettlementCubitStatus? status,
    FinancialCycle? currentCycle,
    SettlementSummary? summary,
    SettlementOptions? options,
    List<SavingsVault>? vaults,
    List<CardInvoiceEntry>? openInvoices,
    String? errorMessage,
  }) {
    return SettlementState(
      status: status ?? this.status,
      currentCycle: currentCycle ?? this.currentCycle,
      summary: summary ?? this.summary,
      options: options ?? this.options,
      vaults: vaults ?? this.vaults,
      openInvoices: openInvoices ?? this.openInvoices,
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
    openInvoices,
    errorMessage,
  ];
}
