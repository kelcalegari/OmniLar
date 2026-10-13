import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/repositories/finance_repository.dart';
import '../../domain/entities/house_expense.dart';
import '../../domain/entities/contribution.dart';
import '../../domain/entities/category.dart';
import '../../domain/entities/payment_method.dart';
import '../../domain/entities/savings_vault.dart';
import '../../domain/entities/financial_cycle_summary.dart';
import '../../domain/entities/audit_entry.dart';
import '../../domain/entities/cycle_funding_estimate.dart';
import '../../domain/services/cycle_funding_estimator.dart';
import '../../../../core/domain/enums/recurrence.dart';
import '../../../../core/domain/value_objects/money.dart';
import '../../../../core/domain/value_objects/financial_cycle.dart';
import 'finance_state.dart';

class FinanceCubit extends Cubit<FinanceState> {
  final FinanceRepository _repository;
  final CycleFundingEstimator _fundingEstimator;
  static const int defaultCycleStartDay = 5;

  /// Dia de início do ciclo configurado na casa atual (null = casa ainda não carregada).
  final int? Function()? _cycleStartDayOf;

  FinanceCubit(
    this._repository, [
    this._fundingEstimator = const CycleFundingEstimator(),
    this._cycleStartDayOf,
  ]) : super(
          FinanceState(
            currentCycle: FinancialCycle.fromDate(
              date: DateTime.now(),
              cycleStartDay: _cycleStartDayOf?.call() ?? defaultCycleStartDay,
            ),
          ),
        );

  /// Dia em que o ciclo financeiro da casa começa.
  int get cycleStartDay => _cycleStartDayOf?.call() ?? defaultCycleStartDay;

  void resetState() {
    emit(
      FinanceState(
        currentCycle: FinancialCycle.fromDate(
          date: DateTime.now(),
          cycleStartDay: cycleStartDay,
        ),
      ),
    );
  }

  /// O cubit pode ter nascido antes de a casa ser carregada (ou o dia de início
  /// pode ter mudado nos Ajustes): devolve o ciclo no dia de início atual.
  FinancialCycle _alignToHouse(FinancialCycle cycle) {
    final startDay = cycleStartDay;
    if (FinancialCycle.fromDate(date: cycle.startDate, cycleStartDay: startDay) == cycle) {
      return cycle;
    }
    final now = DateTime.now();
    return FinancialCycle.fromDate(
      date: cycle.contains(now) ? now : cycle.startDate,
      cycleStartDay: startDay,
    );
  }

  Future<void> loadCycleData({FinancialCycle? cycle}) async {
    final targetCycle = _alignToHouse(cycle ?? state.currentCycle);
    emit(state.copyWith(status: FinanceStatus.loading, currentCycle: targetCycle));

    try {
      final members = await _repository.getMembers();
      final categories = await _repository.getCategories();
      final paymentMethods = await _repository.getPaymentMethods();
      final summary = await _repository.getCycleSummary(targetCycle);
      final expenses = await _repository.getExpensesForCycle(targetCycle);
      final contributions = await _repository.getContributionsForCycle(targetCycle);
      final vaults = await _repository.getSavingsVaults();

      // Busca histórico de despesas do ciclo anterior para cálculo de médias de variáveis (ex: Mercado)
      List<HouseExpense> historicalExpenses = [];
      try {
        final prevCycle = targetCycle.previous(cycleStartDay);
        final prevExpenses = await _repository.getExpensesForCycle(prevCycle);
        historicalExpenses.addAll(prevExpenses);
      } catch (_) {}

      final fundingEstimate = _fundingEstimator.calculateEstimate(
        cycle: targetCycle,
        members: members,
        categories: categories,
        currentCycleExpenses: expenses,
        historicalExpenses: historicalExpenses.isNotEmpty ? historicalExpenses : expenses,
        currentCycleContributions: contributions,
        currentHouseBalance: summary.folego.isPositive ? summary.folego : const Money.zero(),
        mode: state.fundingEstimateMode,
        customCategoryOverrides: state.customCategoryOverrides,
      );

      emit(state.copyWith(
        status: FinanceStatus.success,
        currentCycle: targetCycle,
        summary: summary,
        fundingEstimate: fundingEstimate,
        expenses: expenses,
        contributions: contributions,
        members: members,
        categories: categories,
        paymentMethods: paymentMethods,
        savingsVaults: vaults,
      ));
    } catch (e) {
      emit(state.copyWith(
        status: FinanceStatus.failure,
        errorMessage: 'Erro ao carregar dados do ciclo: $e',
      ));
    }
  }

  void updateFundingEstimateMode(FundingEstimateMode mode) {
    final updated = _fundingEstimator.calculateEstimate(
      cycle: state.currentCycle,
      members: state.members,
      categories: state.categories,
      currentCycleExpenses: state.expenses,
      historicalExpenses: state.expenses,
      currentCycleContributions: state.contributions,
      currentHouseBalance: state.summary?.folego.isPositive == true ? state.summary!.folego : const Money.zero(),
      mode: mode,
      customCategoryOverrides: state.customCategoryOverrides,
    );
    emit(state.copyWith(
      fundingEstimateMode: mode,
      fundingEstimate: updated,
    ));
  }

  void updateCustomCategoryFunding(String categoryId, Money amount) {
    final newOverrides = Map<String, Money>.from(state.customCategoryOverrides);
    newOverrides[categoryId] = amount;
    final updated = _fundingEstimator.calculateEstimate(
      cycle: state.currentCycle,
      members: state.members,
      categories: state.categories,
      currentCycleExpenses: state.expenses,
      historicalExpenses: state.expenses,
      currentCycleContributions: state.contributions,
      currentHouseBalance: state.summary?.folego.isPositive == true ? state.summary!.folego : const Money.zero(),
      mode: state.fundingEstimateMode,
      customCategoryOverrides: newOverrides,
    );
    emit(state.copyWith(
      customCategoryOverrides: newOverrides,
      fundingEstimate: updated,
    ));
  }

  void nextCycle() {
    final next = state.currentCycle.next(cycleStartDay);
    loadCycleData(cycle: next);
  }

  void previousCycle() {
    final prev = state.currentCycle.previous(cycleStartDay);
    loadCycleData(cycle: prev);
  }

  Future<void> addExpense(HouseExpense expense) async {
    try {
      await _repository.addExpense(expense);
      await loadCycleData(cycle: state.currentCycle);
    } catch (e) {
      emit(state.copyWith(
        status: FinanceStatus.failure,
        errorMessage: 'Erro ao adicionar despesa: $e',
      ));
    }
  }

  Future<void> updateExpense(
    HouseExpense expense, {
    RecurrenceScope scope = RecurrenceScope.thisInstanceOnly,
  }) async {
    try {
      await _repository.updateExpense(expense, scope: scope);
      await loadCycleData(cycle: state.currentCycle);
    } catch (e) {
      emit(state.copyWith(
        status: FinanceStatus.failure,
        errorMessage: 'Erro ao atualizar despesa: $e',
      ));
    }
  }

  Future<void> deleteExpense(
    String expenseId, {
    RecurrenceScope scope = RecurrenceScope.thisInstanceOnly,
  }) async {
    final before = state;
    try {
      // Atualização otimista: remove imediatamente da lista local e recalcula saldo do fôlego
      final deleted = state.expenses.where((e) => e.id == expenseId).firstOrNull;
      final seriesId = deleted?.recurringSeriesId ?? expenseId;
      final remaining = (deleted != null && scope == RecurrenceScope.allInstances && deleted.isRecurring)
          ? state.expenses.where((e) {
              return e.id != expenseId && e.id != seriesId && e.recurringSeriesId != seriesId;
            }).toList()
          : state.expenses.where((e) => e.id != expenseId).toList();

      FinancialCycleSummary? updatedSummary = state.summary;
      if (deleted != null && state.summary != null) {
        final currentSummary = state.summary!;
        final deletedAmount = deleted.amount;
        if (deleted.isPaid) {
          final newPaid = currentSummary.totalExpensesPaid - deletedAmount;
          final newFolego = currentSummary.totalContributions - (newPaid + currentSummary.committedFutureExpenses);
          updatedSummary = FinancialCycleSummary(
            cycle: currentSummary.cycle,
            totalContributions: currentSummary.totalContributions,
            totalExpensesPaid: newPaid,
            committedFutureExpenses: currentSummary.committedFutureExpenses,
            folego: newFolego,
            memberContributions: currentSummary.memberContributions,
            memberExpensesPaid: currentSummary.memberExpensesPaid,
          );
        } else {
          final newCommitted = currentSummary.committedFutureExpenses - deletedAmount;
          final newFolego = currentSummary.totalContributions - (currentSummary.totalExpensesPaid + newCommitted);
          updatedSummary = FinancialCycleSummary(
            cycle: currentSummary.cycle,
            totalContributions: currentSummary.totalContributions,
            totalExpensesPaid: currentSummary.totalExpensesPaid,
            committedFutureExpenses: newCommitted,
            folego: newFolego,
            memberContributions: currentSummary.memberContributions,
            memberExpensesPaid: currentSummary.memberExpensesPaid,
          );
        }
      }

      emit(state.copyWith(
        expenses: remaining,
        summary: updatedSummary,
      ));

      await _repository.deleteExpense(expenseId, scope: scope);
      await loadCycleData(cycle: state.currentCycle);
    } catch (e) {
      // A exclusão não aconteceu: a despesa volta para a lista
      emit(before.copyWith(
        status: FinanceStatus.failure,
        errorMessage: 'Erro ao excluir despesa: $e',
      ));
    }
  }

  Future<void> markExpenseAsPaid(String expenseId, {Money? actualAmount}) async {
    try {
      final expense = state.expenses.firstWhere((e) => e.id == expenseId);
      final updated = expense.copyWith(
        status: ExpenseStatus.paid,
        amount: actualAmount ?? expense.amount,
        date: DateTime.now(),
        paidAt: DateTime.now(),
      );
      await _repository.updateExpense(updated);
      await loadCycleData(cycle: state.currentCycle);
    } catch (e) {
      emit(state.copyWith(
        status: FinanceStatus.failure,
        errorMessage: 'Erro ao confirmar pagamento: $e',
      ));
    }
  }

  Future<void> addContribution(Contribution contribution) async {
    try {
      await _repository.addContribution(contribution);
      await loadCycleData(cycle: state.currentCycle);
    } catch (e) {
      emit(state.copyWith(
        status: FinanceStatus.failure,
        errorMessage: 'Erro ao registrar aporte: $e',
      ));
    }
  }

  Future<void> addCategory(ExpenseCategory category) async {
    try {
      await _repository.addCategory(category);
      await loadCycleData(cycle: state.currentCycle);
    } catch (e) {
      emit(state.copyWith(
        status: FinanceStatus.failure,
        errorMessage: 'Erro ao cadastrar categoria: $e',
      ));
    }
  }

  Future<void> addPaymentMethod(PaymentMethod paymentMethod) async {
    try {
      await _repository.addPaymentMethod(paymentMethod);
      final updatedList = [...state.paymentMethods, paymentMethod];
      emit(state.copyWith(paymentMethods: updatedList));
      await loadCycleData(cycle: state.currentCycle);
    } catch (e) {
      emit(state.copyWith(
        status: FinanceStatus.failure,
        errorMessage: 'Erro ao cadastrar forma de pagamento: $e',
      ));
    }
  }

  Future<void> updatePaymentMethod(PaymentMethod paymentMethod) async {
    try {
      await _repository.updatePaymentMethod(paymentMethod);
      final updatedList = state.paymentMethods
          .map((p) => p.id == paymentMethod.id ? paymentMethod : p)
          .toList();
      emit(state.copyWith(paymentMethods: updatedList));
      await loadCycleData(cycle: state.currentCycle);
    } catch (e) {
      emit(state.copyWith(
        status: FinanceStatus.failure,
        errorMessage: 'Erro ao atualizar forma de pagamento: $e',
      ));
    }
  }

  Future<void> deletePaymentMethod(String paymentMethodId) async {
    try {
      await _repository.deletePaymentMethod(paymentMethodId);
      final updatedList = state.paymentMethods
          .where((p) => p.id != paymentMethodId)
          .toList();
      emit(state.copyWith(paymentMethods: updatedList));
      await loadCycleData(cycle: state.currentCycle);
    } catch (e) {
      emit(state.copyWith(
        status: FinanceStatus.failure,
        errorMessage: 'Erro ao excluir forma de pagamento: $e',
      ));
    }
  }

  Future<void> updateHouseSplitModel({
    required String splitModel,
    required Map<String, double> percentages,
    required Map<String, int> fixedAmountsCents,
  }) async {
    try {
      await _repository.updateHouseSplitModel(
        splitModel: splitModel,
        percentages: percentages,
        fixedAmountsCents: fixedAmountsCents,
      );
      await loadCycleData(cycle: state.currentCycle);
    } catch (e) {
      emit(state.copyWith(
        status: FinanceStatus.failure,
        errorMessage: 'Erro ao salvar modelo de rateio: $e',
      ));
    }
  }

  /// Registra o dia em que a fatura do cartão foi paga. Retorna false em caso de erro.
  Future<bool> payCardInvoice({
    required String paymentMethodId,
    required DateTime invoiceDueDate,
    required DateTime paidAt,
  }) async {
    try {
      await _repository.payCardInvoice(
        paymentMethodId: paymentMethodId,
        invoiceDueDate: invoiceDueDate,
        paidAt: paidAt,
      );
      await loadCycleData(cycle: state.currentCycle);
      return true;
    } catch (e) {
      emit(state.copyWith(
        status: FinanceStatus.failure,
        errorMessage: 'Erro ao registrar pagamento da fatura: $e',
      ));
      return false;
    }
  }

  /// Desfaz o registro de pagamento de uma fatura. Retorna false em caso de erro.
  Future<bool> undoCardInvoicePayment({
    required String paymentMethodId,
    required DateTime invoiceDueDate,
  }) async {
    try {
      await _repository.undoCardInvoicePayment(
        paymentMethodId: paymentMethodId,
        invoiceDueDate: invoiceDueDate,
      );
      await loadCycleData(cycle: state.currentCycle);
      return true;
    } catch (e) {
      emit(state.copyWith(
        status: FinanceStatus.failure,
        errorMessage: 'Erro ao desfazer pagamento da fatura: $e',
      ));
      return false;
    }
  }

  // --- Ações de Caixinhas & Metas da Casa (Dinheiro Blindado) ---
  Future<void> createSavingsVault(SavingsVault vault) async {
    try {
      await _repository.createSavingsVault(vault);
      await loadCycleData(cycle: state.currentCycle);
    } catch (e) {
      emit(state.copyWith(
        status: FinanceStatus.failure,
        errorMessage: 'Erro ao criar caixinha: $e',
      ));
    }
  }

  Future<void> depositToVault({
    required String vaultId,
    required String memberId,
    required Money amount,
    required String description,
  }) async {
    try {
      await _repository.depositToVault(
        vaultId: vaultId,
        memberId: memberId,
        amount: amount,
        description: description,
      );
      await loadCycleData(cycle: state.currentCycle);
    } catch (e) {
      emit(state.copyWith(
        status: FinanceStatus.failure,
        errorMessage: 'Erro ao guardar dinheiro na caixinha: $e',
      ));
    }
  }

  Future<void> withdrawFromVault({
    required String vaultId,
    required String memberId,
    required Money amount,
    required String description,
  }) async {
    try {
      await _repository.withdrawFromVault(
        vaultId: vaultId,
        memberId: memberId,
        amount: amount,
        description: description,
      );
      await loadCycleData(cycle: state.currentCycle);
    } catch (e) {
      emit(state.copyWith(
        status: FinanceStatus.failure,
        errorMessage: 'Erro ao resgatar dinheiro da caixinha: $e',
      ));
    }
  }

  Future<List<AuditEntry>> getAuditLog({String? entityId, int limit = 50}) async {
    try {
      return await _repository.getAuditLog(entityId: entityId, limit: limit);
    } catch (_) {
      return [];
    }
  }
}
