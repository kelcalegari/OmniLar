import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/domain/value_objects/cycle_schedule.dart';
import '../../../../core/domain/value_objects/financial_cycle.dart';
import '../../../finance/domain/entities/house_expense.dart';
import '../../../finance/domain/repositories/finance_repository.dart';
import '../../../finance/presentation/cubit/finance_state.dart';
import '../../../p2p/domain/entities/p2p_loan.dart';
import '../../../p2p/domain/repositories/p2p_repository.dart';
import '../../../reconciliation/domain/entities/installment_plan.dart';
import '../../../reconciliation/domain/repositories/import_repository.dart';
import '../../../settlement/domain/entities/settlement_summary.dart';
import '../../../settlement/domain/repositories/settlement_repository.dart';
import '../../domain/entities/cycle_insights.dart';
import '../../domain/entities/cycle_preview.dart';
import '../../domain/entities/payment_due_entry.dart';
import '../../domain/entities/upcoming_forecast.dart';
import '../../domain/services/cycle_insights_builder.dart';
import '../../domain/services/cycle_preview_builder.dart';
import '../../domain/services/house_cashflow_builder.dart';
import '../../domain/services/payment_calendar_builder.dart';
import '../../domain/services/upcoming_cycles_builder.dart';

enum ReportsStatus { initial, loading, loaded, failure }

class ReportsState extends Equatable {
  final ReportsStatus status;
  final CyclePreview? preview;

  /// Calendário de pagamentos do ciclo (fatura, conta, parcela, fechamento).
  final PaymentCalendar? calendar;

  /// Resumo do Hub de onde a prévia saiu (abre a memória de cálculo).
  final SettlementSummary? summary;
  final String? errorMessage;

  /// Próximos ciclos: carregados só quando a seção é aberta.
  final UpcomingForecast? upcoming;
  final bool upcomingLoading;
  final String? upcomingError;

  /// Comparação com o ciclo anterior, quem paga o quê e empréstimos.
  final CycleInsights? insights;

  /// Saldo do Caixa dia a dia até o fechamento (só no ciclo em andamento).
  final HouseCashflow? cashflow;

  /// Evolução dos últimos ciclos: carregada só quando a seção é aberta.
  final List<CycleTotal>? evolution;
  final bool evolutionLoading;
  final String? evolutionError;

  const ReportsState({
    this.status = ReportsStatus.initial,
    this.preview,
    this.calendar,
    this.summary,
    this.errorMessage,
    this.upcoming,
    this.upcomingLoading = false,
    this.upcomingError,
    this.insights,
    this.cashflow,
    this.evolution,
    this.evolutionLoading = false,
    this.evolutionError,
  });

  ReportsState copyWith({
    ReportsStatus? status,
    CyclePreview? preview,
    PaymentCalendar? calendar,
    SettlementSummary? summary,
    String? errorMessage,
    UpcomingForecast? upcoming,
    bool? upcomingLoading,
    String? upcomingError,
    CycleInsights? insights,
    HouseCashflow? cashflow,
    bool clearCashflow = false,
    List<CycleTotal>? evolution,
    bool? evolutionLoading,
    String? evolutionError,
    bool clearCycleData = false,
    bool clearErrors = false,
  }) {
    return ReportsState(
      status: status ?? this.status,
      preview: preview ?? (clearCycleData ? null : this.preview),
      calendar: calendar ?? (clearCycleData ? null : this.calendar),
      summary: summary ?? (clearCycleData ? null : this.summary),
      errorMessage: errorMessage ?? (clearErrors ? null : this.errorMessage),
      upcoming: upcoming ?? this.upcoming,
      upcomingLoading: upcomingLoading ?? this.upcomingLoading,
      upcomingError: upcomingError ?? (clearErrors ? null : this.upcomingError),
      insights: insights ?? (clearCycleData ? null : this.insights),
      cashflow:
          cashflow ?? (clearCycleData || clearCashflow ? null : this.cashflow),
      evolution: evolution ?? (clearCycleData ? null : this.evolution),
      evolutionLoading: evolutionLoading ?? this.evolutionLoading,
      evolutionError:
          evolutionError ?? (clearErrors ? null : this.evolutionError),
    );
  }

  @override
  List<Object?> get props => [
    status,
    preview,
    calendar,
    summary,
    errorMessage,
    upcoming,
    upcomingLoading,
    upcomingError,
    insights,
    cashflow,
    evolution,
    evolutionLoading,
    evolutionError,
  ];
}

/// Prévia do fechamento da aba Relatórios: lê o mesmo resumo do Hub de
/// Liquidação (sem gravar nada) e junta os dados do ciclo do painel.
class ReportsCubit extends Cubit<ReportsState> {
  final SettlementRepository _settlementRepository;
  final P2PRepository? _p2pRepository;
  final FinanceRepository? _financeRepository;
  final ImportRepository? _importRepository;
  final CyclePreviewBuilder _builder = const CyclePreviewBuilder();
  final PaymentCalendarBuilder _calendarBuilder =
      const PaymentCalendarBuilder();
  final UpcomingCyclesBuilder _upcomingBuilder = const UpcomingCyclesBuilder();
  final CycleInsightsBuilder _insightsBuilder = const CycleInsightsBuilder();
  final DateTime Function() _now;

  ReportsCubit(
    this._settlementRepository, {
    P2PRepository? p2pRepository,
    FinanceRepository? financeRepository,
    ImportRepository? importRepository,
    DateTime Function()? now,
  }) : _p2pRepository = p2pRepository,
       _financeRepository = financeRepository,
       _importRepository = importRepository,
       _now = now ?? DateTime.now,
       super(const ReportsState());

  /// Número da carga mais recente: resposta de uma carga antiga é descartada.
  int _sequence = 0;
  int _upcomingSequence = 0;
  int _evolutionSequence = 0;

  /// A evolução dos últimos ciclos foi aberta: recarrega junto com o resto.
  bool get evolutionRequested => _evolutionRequested;
  bool _evolutionRequested = false;

  /// A seção dos próximos ciclos foi aberta: recarrega junto com o resto.
  bool get upcomingRequested => _upcomingRequested;
  bool _upcomingRequested = false;

  Future<List<P2PLoan>> _loans() => Future<List<P2PLoan>>.sync(
    () => _p2pRepository?.getLoans() ?? Future.value(const <P2PLoan>[]),
  ).catchError((_) => const <P2PLoan>[]);

  /// Compras parceladas em curso; sem elas os próximos ciclos saem sem projeção.
  Future<List<InstallmentPlan>> _installmentPlans() =>
      Future<List<InstallmentPlan>>.sync(
        () =>
            _importRepository?.houseInstallmentPlans() ??
            Future.value(const <InstallmentPlan>[]),
      ).catchError((_) => const <InstallmentPlan>[]);

  /// Monta a prévia do ciclo que o painel financeiro carregou. Com
  /// [schedule], lê também o ciclo anterior para a comparação.
  Future<void> loadPreview(
    FinanceState finance, {
    CycleSchedule? schedule,
  }) async {
    final sequence = ++_sequence;
    // Troca de ciclo: a prévia anterior não vale para o novo
    final sameCycle = state.preview?.cycle == finance.currentCycle;
    emit(
      state.copyWith(
        status: ReportsStatus.loading,
        clearCycleData: !sameCycle,
        clearErrors: true,
      ),
    );
    try {
      final summaryFuture = _settlementRepository.getSettlementSummary(
        finance.currentCycle,
      );
      // Sem os empréstimos o calendário sai só com faturas, contas e fechamento
      final loansFuture = _loans();
      // Sem o ciclo anterior a leitura sai sem comparação
      final finances = _financeRepository;
      final previousFuture = finances == null || schedule == null
          ? Future<List<HouseExpense>?>.value(null)
          : Future<List<HouseExpense>?>.sync(
              () => finances.getExpensesForCycle(
                schedule.previous(finance.currentCycle),
              ),
            ).catchError((_) => null);
      final summary = await summaryFuture;
      final loans = await loansFuture;
      final previousExpenses = await previousFuture;
      if (sequence != _sequence || isClosed) return;

      final today = _now();
      final preview = _builder.build(
        summary: summary,
        members: finance.members,
        expenses: finance.expenses,
        paymentMethods: finance.paymentMethods,
        estimate: finance.fundingEstimate?.cycle == finance.currentCycle
            ? finance.fundingEstimate
            : null,
        invoiceCodes: finance.cardInvoiceCodes,
        today: today,
      );
      final calendar = _calendarBuilder.build(
        preview: preview,
        loans: loans,
        members: finance.members,
        today: today,
        cashLabel: finance.houseSettings.cashName,
      );
      // Saldo do Caixa: só no ciclo em andamento, que ainda não foi fechado
      final day = DateTime(today.year, today.month, today.day);
      final cycleSummary = finance.summary;
      final cashflow =
          !preview.isSettled &&
              cycleSummary != null &&
              finance.currentCycle.contains(day)
          ? const HouseCashflowBuilder().build(
              calendar: calendar,
              startingBalance: HouseCashflowBuilder.startingBalance(
                openingBalance: cycleSummary.openingBalance,
                contributions: cycleSummary.totalContributions,
                expenses: finance.expenses,
                houseLoansFunded: cycleSummary.houseLoansFunded,
              ),
            )
          : null;
      final insights = _insightsBuilder.build(
        expenses: finance.expenses,
        previousExpenses: previousExpenses,
        members: finance.members,
        paymentMethods: finance.paymentMethods,
        loans: loans,
        today: today,
      );
      emit(
        state.copyWith(
          status: ReportsStatus.loaded,
          preview: preview,
          calendar: calendar,
          summary: summary,
          insights: insights,
          cashflow: cashflow,
          clearCashflow: cashflow == null,
        ),
      );
    } catch (e) {
      if (sequence != _sequence || isClosed) return;
      emit(
        state.copyWith(
          status: ReportsStatus.failure,
          errorMessage: 'Não foi possível montar a prévia do fechamento: $e',
        ),
      );
    }
  }

  /// Monta o que já está contratado para os próximos ciclos (uma leitura de
  /// despesas por ciclo).
  Future<void> loadUpcoming(
    FinanceState finance,
    CycleSchedule schedule,
  ) async {
    _upcomingRequested = true;
    final finances = _financeRepository;
    if (finances == null) return;
    final sequence = ++_upcomingSequence;
    emit(state.copyWith(upcomingLoading: true, clearErrors: true));
    try {
      final today = _now();
      final cycles = UpcomingCyclesBuilder.upcomingCycles(schedule, today);
      final expensesFutures = {
        for (final c in cycles) c: finances.getExpensesForCycle(c),
      };
      final plansFuture = _installmentPlans();
      final loans = await _loans();
      final plans = await plansFuture;
      final expensesByCycle = <FinancialCycle, List<HouseExpense>>{
        for (final entry in expensesFutures.entries)
          entry.key: await entry.value,
      };
      if (sequence != _upcomingSequence || isClosed) return;
      final upcoming = _upcomingBuilder.build(
        schedule: schedule,
        expensesByCycle: expensesByCycle,
        loans: loans,
        members: finance.members,
        paymentMethods: finance.paymentMethods,
        invoiceCodes: finance.cardInvoiceCodes,
        today: today,
        cashLabel: finance.houseSettings.cashName,
        installmentPlans: plans,
        importLoansNeedAcceptance: finance.houseSettings.loanAcceptance.import,
      );
      emit(state.copyWith(upcoming: upcoming, upcomingLoading: false));
    } catch (e) {
      if (sequence != _upcomingSequence || isClosed) return;
      emit(
        state.copyWith(
          upcomingLoading: false,
          upcomingError: 'Não foi possível carregar os próximos ciclos: $e',
        ),
      );
    }
  }

  /// O devedor aceita o parcelamento de uma compra no cartão; os próximos
  /// ciclos são lidos de novo. Devolve se deu certo.
  Future<bool> acceptInstallmentPlan(
    String planId,
    FinanceState finance,
    CycleSchedule schedule,
  ) async {
    final imports = _importRepository;
    if (imports == null) return false;
    try {
      await imports.acceptInstallmentPlan(planId);
    } catch (_) {
      return false;
    }
    await loadUpcoming(finance, schedule);
    return true;
  }

  /// Total dos últimos [count] ciclos até o que o painel mostra (uma leitura
  /// de despesas por ciclo; o ciclo mostrado reaproveita o que já foi lido).
  Future<void> loadEvolution(
    FinanceState finance,
    CycleSchedule schedule, {
    int count = 6,
  }) async {
    _evolutionRequested = true;
    final finances = _financeRepository;
    if (finances == null) return;
    final sequence = ++_evolutionSequence;
    emit(state.copyWith(evolutionLoading: true, clearErrors: true));
    try {
      final cycles = <FinancialCycle>[finance.currentCycle];
      while (cycles.length < count) {
        cycles.insert(0, schedule.previous(cycles.first));
      }
      final reads = [
        for (final c in cycles)
          c == finance.currentCycle
              ? Future.value(finance.expenses)
              : finances.getExpensesForCycle(c),
      ];
      final totals = <CycleTotal>[
        for (var i = 0; i < cycles.length; i++)
          CycleInsightsBuilder.totalOf(cycles[i], await reads[i]),
      ];
      if (sequence != _evolutionSequence || isClosed) return;
      emit(state.copyWith(evolution: totals, evolutionLoading: false));
    } catch (e) {
      if (sequence != _evolutionSequence || isClosed) return;
      emit(
        state.copyWith(
          evolutionLoading: false,
          evolutionError: 'Não foi possível carregar a evolução dos ciclos: $e',
        ),
      );
    }
  }
}
