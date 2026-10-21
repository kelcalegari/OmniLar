import 'package:equatable/equatable.dart';
import '../../../../core/domain/value_objects/financial_cycle.dart';
import '../../domain/entities/house_transaction.dart';
import '../../domain/services/transaction_aggregator.dart';
import '../../domain/value_objects/transaction_filter.dart';

enum TransactionsStatus { initial, loading, success, failure }

class TransactionsState extends Equatable {
  final TransactionsStatus status;
  final List<HouseTransaction> allTransactions;
  final List<HouseTransaction> filteredTransactions;
  final TransactionFilter filter;
  final TransactionAggregatorMetrics metrics;
  final List<FinancialCycle> availableCycles;
  final String? errorMessage;

  const TransactionsState({
    this.status = TransactionsStatus.initial,
    this.allTransactions = const [],
    this.filteredTransactions = const [],
    this.filter = const TransactionFilter(),
    this.metrics = TransactionAggregatorMetrics.empty,
    this.availableCycles = const [],
    this.errorMessage,
  });

  TransactionsState copyWith({
    TransactionsStatus? status,
    List<HouseTransaction>? allTransactions,
    List<HouseTransaction>? filteredTransactions,
    TransactionFilter? filter,
    TransactionAggregatorMetrics? metrics,
    List<FinancialCycle>? availableCycles,
    String? errorMessage,
  }) {
    return TransactionsState(
      status: status ?? this.status,
      allTransactions: allTransactions ?? this.allTransactions,
      filteredTransactions: filteredTransactions ?? this.filteredTransactions,
      filter: filter ?? this.filter,
      metrics: metrics ?? this.metrics,
      availableCycles: availableCycles ?? this.availableCycles,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  @override
  List<Object?> get props => [
        status,
        allTransactions,
        filteredTransactions,
        filter,
        metrics,
        availableCycles,
        errorMessage,
      ];
}
