import '../../../../core/domain/value_objects/financial_cycle.dart';
import '../entities/house_transaction.dart';

enum PeriodMode {
  cycle,     // Filtrado pelo ciclo financeiro da casa
  dateRange, // Filtrado por intervalo de datas
}

enum DateRangePreset {
  thisMonth('Este mês'),
  last30Days('Últimos 30 dias'),
  last90Days('Últimos 90 dias'),
  thisYear('Este ano'),
  custom('Personalizado');

  final String label;
  const DateRangePreset(this.label);
}

class TransactionFilter {
  final PeriodMode periodMode;
  final FinancialCycle? selectedCycle;
  final DateRangePreset? datePreset;
  final DateTime? startDate;
  final DateTime? endDate;
  final TransactionType? type; // null = Todas, expense = Saídas, inflow = Entradas
  final Set<String> categoryIds; // Vazio = Todas as categorias
  final String? memberId; // null = Todos os moradores
  final String? paymentMethodId; // null = Todas as formas
  final bool? onlyPending; // null = Todas, true = Apenas pendentes
  final String searchQuery;

  const TransactionFilter({
    this.periodMode = PeriodMode.cycle,
    this.selectedCycle,
    this.datePreset,
    this.startDate,
    this.endDate,
    this.type,
    this.categoryIds = const {},
    this.memberId,
    this.paymentMethodId,
    this.onlyPending,
    this.searchQuery = '',
  });

  bool get hasActiveFilters =>
      type != null ||
      categoryIds.isNotEmpty ||
      memberId != null ||
      paymentMethodId != null ||
      onlyPending == true ||
      searchQuery.trim().isNotEmpty ||
      periodMode == PeriodMode.dateRange;

  TransactionFilter copyWith({
    PeriodMode? periodMode,
    FinancialCycle? selectedCycle,
    bool clearCycle = false,
    DateRangePreset? datePreset,
    DateTime? startDate,
    DateTime? endDate,
    bool clearDates = false,
    TransactionType? type,
    bool clearType = false,
    Set<String>? categoryIds,
    String? memberId,
    bool clearMember = false,
    String? paymentMethodId,
    bool clearPaymentMethod = false,
    bool? onlyPending,
    bool clearOnlyPending = false,
    String? searchQuery,
  }) {
    return TransactionFilter(
      periodMode: periodMode ?? this.periodMode,
      selectedCycle: clearCycle ? null : (selectedCycle ?? this.selectedCycle),
      datePreset: clearDates ? null : (datePreset ?? this.datePreset),
      startDate: clearDates ? null : (startDate ?? this.startDate),
      endDate: clearDates ? null : (endDate ?? this.endDate),
      type: clearType ? null : (type ?? this.type),
      categoryIds: categoryIds ?? this.categoryIds,
      memberId: clearMember ? null : (memberId ?? this.memberId),
      paymentMethodId: clearPaymentMethod ? null : (paymentMethodId ?? this.paymentMethodId),
      onlyPending: clearOnlyPending ? null : (onlyPending ?? this.onlyPending),
      searchQuery: searchQuery ?? this.searchQuery,
    );
  }
}
