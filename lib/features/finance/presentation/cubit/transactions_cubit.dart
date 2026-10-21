import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/domain/value_objects/cycle_schedule.dart';
import '../../../../core/domain/value_objects/financial_cycle.dart';
import '../../domain/entities/category.dart';
import '../../domain/entities/contribution.dart';
import '../../domain/entities/house_expense.dart';
import '../../domain/entities/house_inflow.dart';
import '../../domain/entities/house_member.dart';
import '../../domain/entities/house_transaction.dart';
import '../../domain/entities/payment_method.dart';
import '../../domain/entities/third_party_receipt.dart';
import '../../domain/repositories/finance_repository.dart';
import '../../domain/services/transaction_aggregator.dart';
import '../../domain/value_objects/transaction_filter.dart';
import '../../../../core/di/service_locator.dart';
import '../../../p2p/domain/entities/p2p_loan.dart';
import '../../../p2p/domain/repositories/p2p_repository.dart';
import 'transactions_state.dart';

class TransactionsCubit extends Cubit<TransactionsState> {
  final FinanceRepository repository;
  final CycleSchedule cycleSchedule;
  final P2PRepository? p2pRepository;

  List<ExpenseCategory> _categories = [];
  List<HouseMember> _members = [];
  List<PaymentMethod> _paymentMethods = [];

  List<ExpenseCategory> get categories => _categories;
  List<HouseMember> get members => _members;
  List<PaymentMethod> get paymentMethods => _paymentMethods;

  TransactionsCubit({
    required this.repository,
    required this.cycleSchedule,
    this.p2pRepository,
  }) : super(const TransactionsState());

  /// Inicializa a tela com os dados da casa e o ciclo atual selecionado.
  Future<void> initialize({
    FinancialCycle? initialCycle,
    List<ExpenseCategory>? categories,
    List<HouseMember>? members,
    List<PaymentMethod>? paymentMethods,
  }) async {
    emit(state.copyWith(status: TransactionsStatus.loading));
    try {
      final currentCycle = initialCycle ?? cycleSchedule.cycleFor(DateTime.now());

      // 1. Carregar dependências de domínio se não foram injetadas
      _categories = categories ?? await repository.getCategories();
      _members = members ?? await repository.getMembers();
      _paymentMethods = paymentMethods ?? await repository.getPaymentMethods();

      // 2. Montar lista de ciclos disponíveis (últimos 12 ciclos)
      final availableCycles = <FinancialCycle>[currentCycle];
      var iterCycle = currentCycle;
      for (var i = 0; i < 11; i++) {
        iterCycle = cycleSchedule.previous(iterCycle);
        availableCycles.add(iterCycle);
      }

      final initialFilter = state.filter.copyWith(
        periodMode: PeriodMode.cycle,
        selectedCycle: currentCycle,
      );

      // 3. Carregar dados do ciclo inicial
      await _loadDataForFilter(initialFilter, availableCycles: availableCycles);
    } catch (e) {
      emit(state.copyWith(
        status: TransactionsStatus.failure,
        errorMessage: 'Não foi possível carregar as transações: $e',
      ));
    }
  }

  /// Troca o ciclo selecionado.
  Future<void> selectCycle(FinancialCycle cycle) async {
    final updatedFilter = state.filter.copyWith(
      periodMode: PeriodMode.cycle,
      selectedCycle: cycle,
      clearDates: true,
    );
    await _loadDataForFilter(updatedFilter);
  }

  /// Define um intervalo de datas personalizado ou pré-definido.
  Future<void> setDateRange({
    required DateTime startDate,
    required DateTime endDate,
    DateRangePreset? preset,
  }) async {
    final updatedFilter = state.filter.copyWith(
      periodMode: PeriodMode.dateRange,
      startDate: startDate,
      endDate: endDate,
      datePreset: preset ?? DateRangePreset.custom,
      clearCycle: true,
    );
    await _loadDataForFilter(updatedFilter);
  }

  /// Altera o filtro de tipo (Todas, Saídas, Entradas).
  void setTypeFilter(TransactionType? type) {
    final newFilter = state.filter.copyWith(
      type: type,
      clearType: type == null,
    );
    _applyInMemoryFilters(newFilter);
  }

  /// Altera a seleção de categorias.
  void setCategoryFilter(Set<String> categoryIds) {
    final newFilter = state.filter.copyWith(categoryIds: categoryIds);
    _applyInMemoryFilters(newFilter);
  }

  /// Altera o morador filtrado.
  void setMemberFilter(String? memberId) {
    final newFilter = state.filter.copyWith(
      memberId: memberId,
      clearMember: memberId == null,
    );
    _applyInMemoryFilters(newFilter);
  }

  /// Altera a forma de pagamento filtrada.
  void setPaymentMethodFilter(String? paymentMethodId) {
    final newFilter = state.filter.copyWith(
      paymentMethodId: paymentMethodId,
      clearPaymentMethod: paymentMethodId == null,
    );
    _applyInMemoryFilters(newFilter);
  }

  /// Altera o filtro de apenas pendentes.
  void toggleOnlyPending() {
    final isPending = state.filter.onlyPending == true ? null : true;
    final newFilter = state.filter.copyWith(
      onlyPending: isPending,
      clearOnlyPending: isPending == null,
    );
    _applyInMemoryFilters(newFilter);
  }

  /// Atualiza o texto de busca instantânea.
  void setSearchQuery(String query) {
    final newFilter = state.filter.copyWith(searchQuery: query);
    _applyInMemoryFilters(newFilter);
  }

  /// Limpa todos os filtros mantendo o período atual.
  void clearFilters() {
    final resetFilter = TransactionFilter(
      periodMode: state.filter.periodMode,
      selectedCycle: state.filter.selectedCycle,
      startDate: state.filter.startDate,
      endDate: state.filter.endDate,
      datePreset: state.filter.datePreset,
    );
    _applyInMemoryFilters(resetFilter);
  }

  /// Recarrega os dados do período atual (após uma edição ou adição).
  Future<void> refresh() async {
    await _loadDataForFilter(state.filter);
  }

  // --- MÉTODOS INTERNOS ---

  Future<void> _loadDataForFilter(
    TransactionFilter filter, {
    List<FinancialCycle>? availableCycles,
  }) async {
    emit(state.copyWith(
      status: TransactionsStatus.loading,
      filter: filter,
      availableCycles: availableCycles ?? state.availableCycles,
    ));

    try {
      final List<HouseExpense> expenses = [];
      final List<Contribution> contributions = [];
      final List<HouseInflow> inflows = [];
      final List<ThirdPartyReceipt> receipts = [];

      if (filter.periodMode == PeriodMode.cycle && filter.selectedCycle != null) {
        final cycle = filter.selectedCycle!;
        final expFuture = repository.getExpensesForCycle(cycle);
        final contFuture = repository.getContributionsForCycle(cycle);
        final infFuture = repository.getHouseInflowsForCycle(cycle);
        final recFuture = repository.getThirdPartyReceipts();

        expenses.addAll(await expFuture);
        contributions.addAll(await contFuture);
        inflows.addAll(await infFuture);
        receipts.addAll(await recFuture);
      } else {
        // Modo Intervalo de Datas: Identifica os ciclos abrangidos pelo intervalo
        final start = filter.startDate ?? DateTime.now().subtract(const Duration(days: 30));
        final end = filter.endDate ?? DateTime.now();

        var cycleStart = cycleSchedule.cycleFor(start);
        final cycleEnd = cycleSchedule.cycleFor(end);

        final touchedCycles = <FinancialCycle>{cycleStart};
        while (cycleStart.startDate.isBefore(cycleEnd.startDate)) {
          cycleStart = cycleSchedule.next(cycleStart);
          touchedCycles.add(cycleStart);
        }

        final recFuture = repository.getThirdPartyReceipts();

        for (final c in touchedCycles) {
          expenses.addAll(await repository.getExpensesForCycle(c));
          contributions.addAll(await repository.getContributionsForCycle(c));
          inflows.addAll(await repository.getHouseInflowsForCycle(c));
        }
        receipts.addAll(await recFuture);
      }

      // Buscar empréstimos para incluir amortizações/pagamentos no extrato
      List<P2PLoan> loans = const [];
      try {
        final p2pRepo = p2pRepository ?? (sl.isRegistered<P2PRepository>() ? sl<P2PRepository>() : null);
        if (p2pRepo != null) {
          loans = await p2pRepo.getLoans();
        }
      } catch (_) {}

      // Agrega todas as fontes em HouseTransaction
      final all = TransactionAggregator.aggregate(
        expenses: expenses,
        contributions: contributions,
        inflows: inflows,
        receipts: receipts,
        categories: _categories,
        members: _members,
        paymentMethods: _paymentMethods,
        loans: loans,
      );

      final filtered = TransactionAggregator.filter(all, filter);
      final metrics = TransactionAggregator.calculateMetrics(filtered);

      emit(state.copyWith(
        status: TransactionsStatus.success,
        allTransactions: all,
        filteredTransactions: filtered,
        metrics: metrics,
        filter: filter,
      ));
    } catch (e) {
      emit(state.copyWith(
        status: TransactionsStatus.failure,
        errorMessage: 'Falha ao buscar dados das transações: $e',
      ));
    }
  }

  void _applyInMemoryFilters(TransactionFilter newFilter) {
    final filtered = TransactionAggregator.filter(state.allTransactions, newFilter);
    final metrics = TransactionAggregator.calculateMetrics(filtered);

    emit(state.copyWith(
      filter: newFilter,
      filteredTransactions: filtered,
      metrics: metrics,
    ));
  }
}
