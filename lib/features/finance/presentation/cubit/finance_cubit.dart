import 'dart:async';

import '../../../../core/domain/value_objects/cycle_schedule.dart';
import '../../domain/services/pending_payment.dart';
import '../../domain/services/recurring_series.dart';
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

  /// Calendário de ciclos da casa, com as trocas de dia (null = usa só o dia).
  final CycleSchedule? Function()? _cycleScheduleOf;

  FinanceCubit(
    this._repository, [
    this._fundingEstimator = const CycleFundingEstimator(),
    this._cycleStartDayOf,
    this._cycleScheduleOf,
  ]) : super(
          FinanceState(
            currentCycle: (_cycleScheduleOf?.call() ??
                    CycleSchedule(_cycleStartDayOf?.call() ?? defaultCycleStartDay))
                .cycleFor(DateTime.now()),
          ),
        );

  /// Dia em que o ciclo financeiro da casa começa.
  int get cycleStartDay => _cycleStartDayOf?.call() ?? defaultCycleStartDay;

  /// Calendário de ciclos da casa: sabe em que ciclo cai cada data, inclusive
  /// em volta de uma troca do dia de início.
  CycleSchedule get cycleSchedule => _cycleScheduleOf?.call() ?? CycleSchedule(cycleStartDay);

  // Mudanças feitas em outro aparelho (despesas e moradores) recarregam o ciclo
  StreamSubscription<void>? _houseChangesSubscription;
  Timer? _houseChangesDebounce;

  /// Liga o aviso de mudanças da casa, se ainda não estiver ligado. Enquanto a
  /// casa não carregou a fonte recusa; a próxima carga do ciclo tenta de novo.
  void _watchHouseChanges() {
    if (_houseChangesSubscription != null || isClosed) return;
    try {
      _houseChangesSubscription = _repository.watchHouseChanges().listen(
        (_) {
          // Um lançamento gera vários avisos seguidos: recarrega uma vez só
          _houseChangesDebounce?.cancel();
          _houseChangesDebounce = Timer(const Duration(milliseconds: 600), () {
            if (!isClosed) loadCycleData(cycle: state.currentCycle);
          });
        },
        onError: (_) {},
      );
    } catch (_) {}
  }

  void _stopWatchingHouseChanges() {
    _houseChangesDebounce?.cancel();
    _houseChangesDebounce = null;
    _houseChangesSubscription?.cancel();
    _houseChangesSubscription = null;
  }

  @override
  Future<void> close() {
    _stopWatchingHouseChanges();
    return super.close();
  }

  void resetState() {
    // Troca de conta ou de casa: o aviso volta a ser ligado para a casa nova
    _stopWatchingHouseChanges();
    emit(
      FinanceState(
        currentCycle: cycleSchedule.cycleFor(DateTime.now()),
      ),
    );
  }

  /// O cubit pode ter nascido antes de a casa ser carregada (ou o dia de início
  /// pode ter mudado nos Ajustes): devolve o ciclo no dia de início atual.
  FinancialCycle _alignToHouse(FinancialCycle cycle) {
    final schedule = cycleSchedule;
    if (schedule.cycleFor(cycle.startDate) == cycle) {
      return cycle;
    }
    final now = DateTime.now();
    return schedule.cycleFor(cycle.contains(now) ? now : cycle.startDate);
  }

  /// Relê só os moradores, sem recarregar o ciclo. Em caso de erro, mantém a lista atual.
  Future<void> refreshMembers() async {
    try {
      final members = await _repository.getMembers();
      emit(state.copyWith(members: members));
    } catch (_) {}
  }

  /// Número da carga mais recente: resposta de uma carga antiga é descartada.
  int _loadSequence = 0;

  Future<void> loadCycleData({FinancialCycle? cycle}) async {
    final targetCycle = _alignToHouse(cycle ?? state.currentCycle);
    final sequence = ++_loadSequence;
    emit(state.copyWith(status: FinanceStatus.loading, currentCycle: targetCycle));

    try {
      // As leituras não dependem umas das outras: vão todas de uma vez
      final membersFuture = _repository.getMembers();
      final categoriesFuture = _repository.getCategories();
      final paymentMethodsFuture = _repository.getPaymentMethods();
      final summaryFuture = _repository.getCycleSummary(targetCycle);
      final expensesFuture = _repository.getExpensesForCycle(targetCycle);
      final contributionsFuture = _repository.getContributionsForCycle(targetCycle);
      final vaultsFuture = _repository.getSavingsVaults();
      // As três abaixo são opcionais: se falharem, vale o que já se tinha
      final splitModelFuture = Future<String?>.sync(
        () => _repository.getHouseSplitModel(),
      ).catchError((_) => null);
      final recurringFuture = Future<List<HouseExpense>?>.sync(
        () => _repository.getRecurringExpenses(),
      ).catchError((_) => null);
      // Histórico do ciclo anterior para as médias de variáveis (ex: Mercado)
      final historicalFuture = Future<List<HouseExpense>>.sync(
        () => _repository.getExpensesForCycle(cycleSchedule.previous(targetCycle)),
      ).catchError((_) => <HouseExpense>[]);

      await Future.wait<void>([
        membersFuture,
        categoriesFuture,
        paymentMethodsFuture,
        summaryFuture,
        expensesFuture,
        contributionsFuture,
        vaultsFuture,
        splitModelFuture,
        recurringFuture,
        historicalFuture,
      ]);
      // Outro ciclo foi pedido enquanto este carregava: o dele é que vale
      if (sequence != _loadSequence || isClosed) return;

      final members = await membersFuture;
      final categories = await categoriesFuture;
      final paymentMethods = await paymentMethodsFuture;
      final summary = await summaryFuture;
      final expenses = await expensesFuture;
      final contributions = await contributionsFuture;
      final vaults = await vaultsFuture;
      final splitModel = await splitModelFuture ?? state.splitModel;
      // Sem a lista da casa, valem as recorrentes do ciclo aberto
      var recurringSeries = expenses.where((e) => e.isRecurring).toList();
      final recurringRows = await recurringFuture;
      if (recurringRows != null) {
        // O repositório já devolve só as ocorrências de séries ativas
        recurringSeries = latestOccurrencePerSeries(
          recurringRows,
          activeSeriesIds: {for (final e in recurringRows) e.recurringSeriesId ?? e.id},
        );
      }
      final historicalExpenses = await historicalFuture;

      _historicalExpenses = historicalExpenses.isNotEmpty ? historicalExpenses : expenses;

      final fundingEstimate = _fundingEstimator.calculateEstimate(
        cycle: targetCycle,
        members: members,
        categories: categories,
        currentCycleExpenses: expenses,
        historicalExpenses: _historicalExpenses,
        currentCycleContributions: contributions,
        currentHouseBalance: _openingBalanceOf(summary),
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
        splitModel: splitModel,
        recurringSeries: recurringSeries,
      ));
      _watchHouseChanges();
    } catch (e) {
      if (sequence != _loadSequence || isClosed) return;
      emit(state.copyWith(
        status: FinanceStatus.failure,
        errorMessage: 'Erro ao carregar dados do ciclo: $e',
      ));
    }
  }

  /// Histórico usado nas médias do planejador (ciclo anterior, quando existe).
  List<HouseExpense> _historicalExpenses = const [];

  /// Sobra que o ciclo anterior deixou no Caixa. O fôlego já desconta as
  /// contas e soma os aportes do ciclo, então não serve de saldo inicial.
  Money _openingBalanceOf(FinancialCycleSummary? summary) {
    if (summary == null) return const Money.zero();
    final cents = summary.folego.cents +
        summary.totalExpensesPaid.cents +
        summary.committedFutureExpenses.cents -
        summary.totalContributions.cents;
    return Money(cents > 0 ? cents : 0);
  }

  void updateFundingEstimateMode(FundingEstimateMode mode) {
    final updated = _fundingEstimator.calculateEstimate(
      cycle: state.currentCycle,
      members: state.members,
      categories: state.categories,
      currentCycleExpenses: state.expenses,
      historicalExpenses: _historicalExpenses,
      currentCycleContributions: state.contributions,
      currentHouseBalance: _openingBalanceOf(state.summary),
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
      historicalExpenses: _historicalExpenses,
      currentCycleContributions: state.contributions,
      currentHouseBalance: _openingBalanceOf(state.summary),
      mode: state.fundingEstimateMode,
      customCategoryOverrides: newOverrides,
    );
    emit(state.copyWith(
      customCategoryOverrides: newOverrides,
      fundingEstimate: updated,
    ));
  }

  void nextCycle() {
    final next = cycleSchedule.next(state.currentCycle);
    loadCycleData(cycle: next);
  }

  void previousCycle() {
    final prev = cycleSchedule.previous(state.currentCycle);
    loadCycleData(cycle: prev);
  }

  /// Volta para o ciclo em andamento hoje.
  void goToCurrentCycle() {
    loadCycleData(cycle: cycleSchedule.cycleFor(DateTime.now()));
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

  /// Registra o pagamento de uma conta pendente no dia [paidOn] com o meio
  /// [method]. Quem pagou sai do meio: com dono, o dono (reembolsado no
  /// fechamento); da casa, a casa. Cartão de crédito transforma a conta numa
  /// compra da fatura, que fica pendente até a fatura ser paga (conta
  /// recorrente no cartão recebe baixa direto, como antes). Retorna false em
  /// caso de erro.
  Future<bool> payPendingExpense(
    HouseExpense expense, {
    required DateTime paidOn,
    required PaymentMethod? method,
    Money? amount,
  }) async {
    final updated = paidWith(expense, paidOn: paidOn, method: method, amount: amount);

    try {
      await _repository.updateExpense(updated);
      await loadCycleData(cycle: state.currentCycle);
      return true;
    } catch (e) {
      emit(state.copyWith(
        status: FinanceStatus.failure,
        errorMessage: 'Erro ao registrar pagamento: $e',
      ));
      return false;
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

  /// Devolve a mensagem de erro para a tela mostrar, ou null se gravou.
  Future<String?> updateCategory(ExpenseCategory category) async {
    try {
      await _repository.updateCategory(category);
      await loadCycleData(cycle: state.currentCycle);
      return null;
    } catch (e) {
      return '$e';
    }
  }

  /// Devolve a mensagem de erro para a tela mostrar, ou null se excluiu.
  Future<String?> deleteCategory(String categoryId) async {
    try {
      await _repository.deleteCategory(categoryId);
      await loadCycleData(cycle: state.currentCycle);
      return null;
    } catch (e) {
      return '$e';
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
    bool paidByHouse = false,
  }) async {
    try {
      await _repository.payCardInvoice(
        paymentMethodId: paymentMethodId,
        invoiceDueDate: invoiceDueDate,
        paidAt: paidAt,
        paidByHouse: paidByHouse,
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
