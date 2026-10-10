import 'package:equatable/equatable.dart';
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
  final SettlementSummary? summary;
  final String? errorMessage;

  const SettlementState({
    this.status = SettlementCubitStatus.initial,
    this.summary,
    this.errorMessage,
  });

  SettlementState copyWith({
    SettlementCubitStatus? status,
    SettlementSummary? summary,
    String? errorMessage,
  }) {
    return SettlementState(
      status: status ?? this.status,
      summary: summary ?? this.summary,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  @override
  List<Object?> get props => [status, summary, errorMessage];
}
