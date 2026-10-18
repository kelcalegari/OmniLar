import '../../domain/entities/card_invoice.dart';
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
import '../../domain/entities/third_party_receipt.dart';
import '../../domain/entities/financial_cycle_summary.dart';
import '../../domain/entities/audit_entry.dart';
import '../../domain/entities/cycle_funding_estimate.dart';
import '../../domain/services/cycle_funding_estimator.dart';
import '../../domain/entities/house_member.dart';
import '../../../settlement/domain/services/open_invoice_choices.dart';
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
    var targetCycle = _alignToHouse(cycle ?? state.currentCycle);
    if (isBeforeFirstCycle(targetCycle)) targetCycle = firstCycle!;
    // O início da casa só muda com lançamento novo: relê ao recarregar o mesmo
    // ciclo (depois de gravar ou de um aviso de outro aparelho), não ao navegar
    final refreshStartDate = state.houseStartDate == null || targetCycle == state.currentCycle;
    final sequence = ++_loadSequence;
    emit(state.copyWith(status: FinanceStatus.loading, currentCycle: targetCycle));

    try {
      // As leituras não dependem umas das outras: vão todas de uma vez
      final membersFuture = _repository.getMembers();
      final categoriesFuture = _repository.getCategories();
      final paymentMethodsFuture = _repository.getPaymentMethods();
      final expensesFuture = _repository.getExpensesForCycle(targetCycle);
      final contributionsFuture = _repository.getContributionsForCycle(targetCycle);
      // O resumo reaproveita as despesas e os aportes já lidos
      final summaryFuture = Future.wait<Object>([expensesFuture, contributionsFuture]).then(
        (lists) => _repository.getCycleSummary(
          targetCycle,
          expenses: lists[0] as List<HouseExpense>,
          contributions: lists[1] as List<Contribution>,
        ),
      );
      final vaultsFuture = _repository.getSavingsVaults();
      final receiptsFuture = Future<List<ThirdPartyReceipt>?>.sync(
        () => _repository.getThirdPartyReceipts(),
      ).catchError((_) => null);
      // As três abaixo são opcionais: se falharem, vale o que já se tinha
      final splitModelFuture = Future<String?>.sync(
        () => _repository.getHouseSplitModel(),
      ).catchError((_) => null);
      final recurringFuture = Future<List<HouseExpense>?>.sync(
        () => _repository.getRecurringExpenses(),
      ).catchError((_) => null);
      // Histórico do ciclo anterior para as médias de variáveis (ex: Mercado)
      final invoiceCodesFuture = Future<List<CardInvoiceCode>?>.sync(
        () => _repository.getCardInvoiceCodes(),
      ).catchError((_) => null);
      final startDateFuture = refreshStartDate
          ? Future<DateTime?>.sync(() => _repository.getHouseStartDate()).catchError((_) => null)
          : Future<DateTime?>.value(state.houseStartDate);
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
        receiptsFuture,
        splitModelFuture,
        recurringFuture,
        invoiceCodesFuture,
        historicalFuture,
        startDateFuture,
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
      final receipts = await receiptsFuture;
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
      final invoiceCodes = await invoiceCodesFuture;
      final houseStartDate = await startDateFuture;

      _historicalExpenses = historicalExpenses.isNotEmpty ? historicalExpenses : expenses;

      final fundingEstimate = _estimate(
        cycle: targetCycle,
        members: members,
        categories: categories,
        expenses: expenses,
        paymentMethods: paymentMethods,
        contributions: contributions,
        summary: summary,
        mode: state.fundingEstimateMode,
        overrides: state.customCategoryOverrides,
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
        thirdPartyReceipts: receipts,
        splitModel: splitModel,
        recurringSeries: recurringSeries,
        cardInvoiceCodes: invoiceCodes == null ? null : {for (final c in invoiceCodes) c.key: c.barcode},
        houseStartDate: houseStartDate,
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

  /// Planejador de aportes com a mesma visão do fechamento: faturas e contas
  /// pendentes entram como pagas por quem o fechamento escolheria por padrão.
  /// O histórico é sempre um ciclo só (o anterior, ou o próprio ciclo).
  CycleFundingEstimate _estimate({
    required FinancialCycle cycle,
    required List<HouseMember> members,
    required List<ExpenseCategory> categories,
    required List<HouseExpense> expenses,
    required List<PaymentMethod> paymentMethods,
    required List<Contribution> contributions,
    required FinancialCycleSummary? summary,
    required FundingEstimateMode mode,
    required Map<String, Money> overrides,
  }) =>
      _fundingEstimator.calculateEstimate(
        cycle: cycle,
        members: members,
        categories: categories,
        currentCycleExpenses: applyOpenInvoiceChoices(expenses, paymentMethods, const {}),
        historicalExpenses: _historicalExpenses,
        currentCycleContributions: contributions,
        currentHouseBalance: _openingBalanceOf(summary),
        mode: mode,
        customCategoryOverrides: overrides,
        historicalCyclesCount: 1,
      );

  /// Sobra que o ciclo anterior deixou no Caixa. O fôlego já desconta as
  /// contas e soma os aportes do ciclo, então não serve de saldo inicial. O que
  /// voltou das caixinhas fica de fora: cobre falta de caixa, mas cada morador
  /// continua devendo a parte dele no ciclo.
  Money _openingBalanceOf(FinancialCycleSummary? summary) =>
      summary?.rolledOverBalance ?? const Money.zero();

  void updateFundingEstimateMode(FundingEstimateMode mode) {
    final updated = _estimate(
      cycle: state.currentCycle,
      members: state.members,
      categories: state.categories,
      expenses: state.expenses,
      paymentMethods: state.paymentMethods,
      contributions: state.contributions,
      summary: state.summary,
      mode: mode,
      overrides: state.customCategoryOverrides,
    );
    emit(state.copyWith(
      fundingEstimateMode: mode,
      fundingEstimate: updated,
    ));
  }

  void updateCustomCategoryFunding(String categoryId, Money amount) {
    final newOverrides = Map<String, Money>.from(state.customCategoryOverrides);
    newOverrides[categoryId] = amount;
    final updated = _estimate(
      cycle: state.currentCycle,
      members: state.members,
      categories: state.categories,
      expenses: state.expenses,
      paymentMethods: state.paymentMethods,
      contributions: state.contributions,
      summary: state.summary,
      mode: state.fundingEstimateMode,
      overrides: newOverrides,
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
    if (!canGoToPreviousCycle) return;
    final prev = cycleSchedule.previous(state.currentCycle);
    loadCycleData(cycle: prev);
  }

  /// Primeiro ciclo da casa (null enquanto não se sabe): antes dele a casa não existia.
  FinancialCycle? get firstCycle {
    final start = state.houseStartDate;
    return start == null ? null : cycleSchedule.cycleFor(start);
  }

  /// Se [cycle] é de antes do primeiro ciclo da casa.
  bool isBeforeFirstCycle(FinancialCycle cycle) {
    final first = firstCycle;
    return first != null && cycle.startDate.isBefore(first.startDate);
  }

  /// Se dá para ir ao ciclo anterior a [cycle] sem sair da vida da casa.
  bool canGoBackFrom(FinancialCycle cycle) => !isBeforeFirstCycle(cycleSchedule.previous(cycle));

  bool get canGoToPreviousCycle => canGoBackFrom(state.currentCycle);

  /// Volta para o ciclo em andamento hoje.
  void goToCurrentCycle() {
    loadCycleData(cycle: cycleSchedule.cycleFor(DateTime.now()));
  }

  Future<bool> addExpense(HouseExpense expense) async {
    try {
      await _repository.addExpense(expense);
      await loadCycleData(cycle: state.currentCycle);
      return true;
    } catch (e) {
      emit(state.copyWith(
        status: FinanceStatus.failure,
        errorMessage: 'Erro ao adicionar despesa: $e',
      ));
      return false;
    }
  }

  Future<bool> updateExpense(
    HouseExpense expense, {
    RecurrenceScope scope = RecurrenceScope.thisInstanceOnly,
  }) async {
    try {
      await _repository.updateExpense(expense, scope: scope);
      await loadCycleData(cycle: state.currentCycle);
      return true;
    } catch (e) {
      emit(state.copyWith(
        status: FinanceStatus.failure,
        errorMessage: 'Erro ao atualizar despesa: $e',
      ));
      return false;
    }
  }

  Future<bool> deleteExpense(
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
      return true;
    } catch (e) {
      // A exclusão não aconteceu: a despesa volta para a lista
      emit(before.copyWith(
        status: FinanceStatus.failure,
        errorMessage: 'Erro ao excluir despesa: $e',
      ));
      return false;
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

  Future<bool> addContribution(Contribution contribution) async {
    try {
      await _repository.addContribution(contribution);
      await loadCycleData(cycle: state.currentCycle);
      return true;
    } catch (e) {
      emit(state.copyWith(
        status: FinanceStatus.failure,
        errorMessage: 'Erro ao registrar aporte: $e',
      ));
      return false;
    }
  }

  Future<bool> addCategory(ExpenseCategory category) async {
    try {
      await _repository.addCategory(category);
      await loadCycleData(cycle: state.currentCycle);
      return true;
    } catch (e) {
      emit(state.copyWith(
        status: FinanceStatus.failure,
        errorMessage: 'Erro ao cadastrar categoria: $e',
      ));
      return false;
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
  Future<String?> deleteCategory(String categoryId, {String? moveToCategoryId}) async {
    try {
      await _repository.deleteCategory(categoryId, moveToCategoryId: moveToCategoryId);
      await loadCycleData(cycle: state.currentCycle);
      return null;
    } catch (e) {
      return '$e';
    }
  }

  Future<bool> addPaymentMethod(PaymentMethod paymentMethod) async {
    try {
      await _repository.addPaymentMethod(paymentMethod);
      final updatedList = [...state.paymentMethods, paymentMethod];
      emit(state.copyWith(paymentMethods: updatedList));
      await loadCycleData(cycle: state.currentCycle);
      return true;
    } catch (e) {
      emit(state.copyWith(
        status: FinanceStatus.failure,
        errorMessage: 'Erro ao cadastrar forma de pagamento: $e',
      ));
      return false;
    }
  }

  Future<bool> updatePaymentMethod(PaymentMethod paymentMethod) async {
    try {
      await _repository.updatePaymentMethod(paymentMethod);
      final updatedList = state.paymentMethods
          .map((p) => p.id == paymentMethod.id ? paymentMethod : p)
          .toList();
      emit(state.copyWith(paymentMethods: updatedList));
      await loadCycleData(cycle: state.currentCycle);
      return true;
    } catch (e) {
      emit(state.copyWith(
        status: FinanceStatus.failure,
        errorMessage: 'Erro ao atualizar forma de pagamento: $e',
      ));
      return false;
    }
  }

  Future<bool> deletePaymentMethod(String paymentMethodId) async {
    try {
      await _repository.deletePaymentMethod(paymentMethodId);
      final updatedList = state.paymentMethods
          .where((p) => p.id != paymentMethodId)
          .toList();
      emit(state.copyWith(paymentMethods: updatedList));
      await loadCycleData(cycle: state.currentCycle);
      return true;
    } catch (e) {
      emit(state.copyWith(
        status: FinanceStatus.failure,
        errorMessage: 'Erro ao excluir forma de pagamento: $e',
      ));
      return false;
    }
  }

  Future<bool> updateHouseSplitModel({
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
      return true;
    } catch (e) {
      emit(state.copyWith(
        status: FinanceStatus.failure,
        errorMessage: 'Erro ao salvar modelo de rateio: $e',
      ));
      return false;
    }
  }

  /// Registra o dia em que a fatura do cartão foi paga. Retorna false em caso de erro.
  Future<bool> payCardInvoice({
    required String paymentMethodId,
    required DateTime invoiceDueDate,
    required DateTime paidAt,
    bool paidByHouse = false,
    List<String> thirdPartyReceiptIds = const [],
  }) async {
    try {
      await _repository.payCardInvoice(
        paymentMethodId: paymentMethodId,
        invoiceDueDate: invoiceDueDate,
        paidAt: paidAt,
        paidByHouse: paidByHouse,
      );
      if (thirdPartyReceiptIds.isNotEmpty) {
        final card = state.paymentMethods.where((p) => p.id == paymentMethodId).firstOrNull;
        try {
          // Pela Casa (ou cartão sem dono) o repasse sai pelo banco; pelo
          // titular, ele recebe o repasse
          await _repository.useThirdPartyReceipts(
            receiptIds: thirdPartyReceiptIds,
            use: paidByHouse || card?.ownerMemberId == null
                ? ThirdPartyReceiptUse.housePaid
                : ThirdPartyReceiptUse.passedToOwner,
            paymentMethodId: paymentMethodId,
            invoiceDueDate: invoiceDueDate,
          );
        } catch (e) {
          // A fatura já está paga: o repasse fica guardado para usar depois
          await loadCycleData(cycle: state.currentCycle);
          emit(state.copyWith(
            status: FinanceStatus.failure,
            errorMessage: 'A fatura foi paga, mas o repasse continua na caixinha: $e',
          ));
          return false;
        }
      }
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

  /// Guarda (ou apaga, com [barcode] nulo) o código do boleto de uma fatura.
  Future<bool> saveCardInvoiceCode({
    required String paymentMethodId,
    required DateTime invoiceDueDate,
    String? barcode,
  }) async {
    try {
      await _repository.saveCardInvoiceCode(
        paymentMethodId: paymentMethodId,
        invoiceDueDate: invoiceDueDate,
        barcode: barcode,
      );
      final key = CardInvoiceCode.keyOf(paymentMethodId, invoiceDueDate);
      final codes = Map<String, String>.of(state.cardInvoiceCodes);
      if (barcode == null || barcode.trim().isEmpty) {
        codes.remove(key);
      } else {
        codes[key] = barcode.trim();
      }
      emit(state.copyWith(cardInvoiceCodes: codes));
      return true;
    } catch (e) {
      emit(state.copyWith(
        status: FinanceStatus.failure,
        errorMessage: 'Erro ao guardar o código da fatura: $e',
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
      // Repasses usados nesta fatura voltam para a caixinha
      final usedHere = state.thirdPartyReceipts.any((r) =>
          r.isUsed &&
          r.usedPaymentMethodId == paymentMethodId &&
          r.usedDueDate?.year == invoiceDueDate.year &&
          r.usedDueDate?.month == invoiceDueDate.month &&
          r.usedDueDate?.day == invoiceDueDate.day);
      if (usedHere) {
        await _repository.reopenThirdPartyReceipts(
          paymentMethodId: paymentMethodId,
          invoiceDueDate: invoiceDueDate,
        );
      }
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
  Future<bool> createSavingsVault(SavingsVault vault) async {
    try {
      await _repository.createSavingsVault(vault);
      await loadCycleData(cycle: state.currentCycle);
      return true;
    } catch (e) {
      emit(state.copyWith(
        status: FinanceStatus.failure,
        errorMessage: 'Erro ao criar caixinha: $e',
      ));
      return false;
    }
  }

  Future<bool> updateSavingsVault(SavingsVault vault) =>
      _runVaultAction(() => _repository.updateSavingsVault(vault), 'Erro ao salvar a caixinha');

  Future<bool> deleteSavingsVault(String vaultId) =>
      _runVaultAction(() => _repository.deleteSavingsVault(vaultId), 'Erro ao excluir a caixinha');

  Future<bool> transferBetweenVaults({
    required String fromVaultId,
    required String toVaultId,
    required Money amount,
    required String description,
  }) =>
      _runVaultAction(
        () => _repository.transferBetweenVaults(
          fromVaultId: fromVaultId,
          toVaultId: toVaultId,
          amount: amount,
          description: description,
        ),
        'Erro ao transferir entre caixinhas',
      );

  Future<bool> _runVaultAction(Future<void> Function() action, String failure) async {
    try {
      await action();
      await loadCycleData(cycle: state.currentCycle);
      return true;
    } catch (e) {
      emit(state.copyWith(
        status: FinanceStatus.failure,
        errorMessage: '$failure: $e',
      ));
      return false;
    }
  }

  Future<bool> depositToVault({
    required String vaultId,
    required String memberId,
    required Money amount,
    required String description,
    DateTime? fromCycleStart,
  }) async {
    try {
      await _repository.depositToVault(
        vaultId: vaultId,
        memberId: memberId,
        amount: amount,
        description: description,
        fromCycleStart: fromCycleStart,
      );
      await loadCycleData(cycle: state.currentCycle);
      return true;
    } catch (e) {
      emit(state.copyWith(
        status: FinanceStatus.failure,
        errorMessage: 'Erro ao guardar dinheiro na caixinha: $e',
      ));
      return false;
    }
  }

  Future<bool> withdrawFromVault({
    required String vaultId,
    required String memberId,
    required Money amount,
    required String description,
    DateTime? returnToCycleStart,
  }) async {
    try {
      await _repository.withdrawFromVault(
        vaultId: vaultId,
        memberId: memberId,
        amount: amount,
        description: description,
        returnToCycleStart: returnToCycleStart,
      );
      await loadCycleData(cycle: state.currentCycle);
      return true;
    } catch (e) {
      emit(state.copyWith(
        status: FinanceStatus.failure,
        errorMessage: 'Erro ao resgatar dinheiro da caixinha: $e',
      ));
      return false;
    }
  }

  // --- Entradas de terceiros (repasses guardados em caixinha) ---
  Future<bool> registerThirdPartyReceipt({
    required String payerName,
    required Money amount,
    required DateTime receivedOn,
    required String vaultId,
    String? paymentMethodId,
    String? description,
  }) =>
      _runVaultAction(
        () => _repository.registerThirdPartyReceipt(
          payerName: payerName,
          amount: amount,
          receivedOn: receivedOn,
          vaultId: vaultId,
          paymentMethodId: paymentMethodId,
          description: description,
        ),
        'Erro ao registrar o repasse',
      );

  Future<bool> useThirdPartyReceipts({
    required List<String> receiptIds,
    required ThirdPartyReceiptUse use,
    String? paymentMethodId,
    DateTime? invoiceDueDate,
  }) =>
      _runVaultAction(
        () => _repository.useThirdPartyReceipts(
          receiptIds: receiptIds,
          use: use,
          paymentMethodId: paymentMethodId,
          invoiceDueDate: invoiceDueDate,
        ),
        'Erro ao usar o repasse',
      );

  Future<bool> reopenThirdPartyReceipt(String receiptId) => _runVaultAction(
        () => _repository.reopenThirdPartyReceipts(receiptIds: [receiptId]),
        'Erro ao devolver o repasse para a caixinha',
      );

  Future<bool> deleteThirdPartyReceipt(String receiptId) => _runVaultAction(
        () => _repository.deleteThirdPartyReceipt(receiptId),
        'Erro ao excluir o repasse',
      );

  Future<List<AuditEntry>> getAuditLog({String? entityId, int limit = 50}) async {
    try {
      return await _repository.getAuditLog(entityId: entityId, limit: limit);
    } catch (_) {
      return [];
    }
  }
}
