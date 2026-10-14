import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../finance/presentation/cubit/finance_state.dart';
import '../../../p2p/domain/entities/p2p_loan.dart';
import '../../../p2p/domain/repositories/p2p_repository.dart';
import '../../../settlement/domain/entities/settlement_summary.dart';
import '../../../settlement/domain/repositories/settlement_repository.dart';
import '../../domain/entities/cycle_preview.dart';
import '../../domain/entities/payment_due_entry.dart';
import '../../domain/services/cycle_preview_builder.dart';
import '../../domain/services/payment_calendar_builder.dart';

enum ReportsStatus { initial, loading, loaded, failure }

class ReportsState extends Equatable {
  final ReportsStatus status;
  final CyclePreview? preview;

  /// Calendário de pagamentos do ciclo (fatura, conta, parcela, fechamento).
  final PaymentCalendar? calendar;

  /// Resumo do Hub de onde a prévia saiu (abre a memória de cálculo).
  final SettlementSummary? summary;
  final String? errorMessage;

  const ReportsState({
    this.status = ReportsStatus.initial,
    this.preview,
    this.calendar,
    this.summary,
    this.errorMessage,
  });

  @override
  List<Object?> get props => [status, preview, calendar, summary, errorMessage];
}

/// Prévia do fechamento da aba Relatórios: lê o mesmo resumo do Hub de
/// Liquidação (sem gravar nada) e junta os dados do ciclo do painel.
class ReportsCubit extends Cubit<ReportsState> {
  final SettlementRepository _settlementRepository;
  final P2PRepository? _p2pRepository;
  final CyclePreviewBuilder _builder = const CyclePreviewBuilder();
  final PaymentCalendarBuilder _calendarBuilder =
      const PaymentCalendarBuilder();
  final DateTime Function() _now;

  ReportsCubit(
    this._settlementRepository, [
    this._p2pRepository,
    DateTime Function()? now,
  ]) : _now = now ?? DateTime.now,
       super(const ReportsState());

  /// Número da carga mais recente: resposta de uma carga antiga é descartada.
  int _sequence = 0;

  /// Monta a prévia do ciclo que o painel financeiro carregou.
  Future<void> loadPreview(FinanceState finance) async {
    final sequence = ++_sequence;
    // Troca de ciclo: a prévia anterior não vale para o novo
    final sameCycle = state.preview?.cycle == finance.currentCycle;
    final kept = sameCycle ? state : const ReportsState();
    emit(
      ReportsState(
        status: ReportsStatus.loading,
        preview: kept.preview,
        calendar: kept.calendar,
        summary: kept.summary,
      ),
    );
    try {
      final summaryFuture = _settlementRepository.getSettlementSummary(
        finance.currentCycle,
      );
      // Sem os empréstimos o calendário sai só com faturas, contas e fechamento
      final loansFuture = Future<List<P2PLoan>>.sync(
        () => _p2pRepository?.getLoans() ?? Future.value(const <P2PLoan>[]),
      ).catchError((_) => const <P2PLoan>[]);
      final summary = await summaryFuture;
      final loans = await loansFuture;
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
      );
      emit(
        ReportsState(
          status: ReportsStatus.loaded,
          preview: preview,
          calendar: calendar,
          summary: summary,
        ),
      );
    } catch (e) {
      if (sequence != _sequence || isClosed) return;
      emit(
        ReportsState(
          status: ReportsStatus.failure,
          preview: kept.preview,
          calendar: kept.calendar,
          summary: kept.summary,
          errorMessage: 'Não foi possível montar a prévia do fechamento: $e',
        ),
      );
    }
  }
}
