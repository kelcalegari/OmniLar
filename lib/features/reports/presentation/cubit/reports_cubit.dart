import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../finance/presentation/cubit/finance_state.dart';
import '../../../settlement/domain/entities/settlement_summary.dart';
import '../../../settlement/domain/repositories/settlement_repository.dart';
import '../../domain/entities/cycle_preview.dart';
import '../../domain/services/cycle_preview_builder.dart';

enum ReportsStatus { initial, loading, loaded, failure }

class ReportsState extends Equatable {
  final ReportsStatus status;
  final CyclePreview? preview;

  /// Resumo do Hub de onde a prévia saiu (abre a memória de cálculo).
  final SettlementSummary? summary;
  final String? errorMessage;

  const ReportsState({
    this.status = ReportsStatus.initial,
    this.preview,
    this.summary,
    this.errorMessage,
  });

  @override
  List<Object?> get props => [status, preview, summary, errorMessage];
}

/// Prévia do fechamento da aba Relatórios: lê o mesmo resumo do Hub de
/// Liquidação (sem gravar nada) e junta os dados do ciclo do painel.
class ReportsCubit extends Cubit<ReportsState> {
  final SettlementRepository _settlementRepository;
  final CyclePreviewBuilder _builder = const CyclePreviewBuilder();
  final DateTime Function() _now;

  ReportsCubit(this._settlementRepository, {DateTime Function()? now})
      : _now = now ?? DateTime.now,
        super(const ReportsState());

  /// Número da carga mais recente: resposta de uma carga antiga é descartada.
  int _sequence = 0;

  /// Monta a prévia do ciclo que o painel financeiro carregou.
  Future<void> loadPreview(FinanceState finance) async {
    final sequence = ++_sequence;
    // Troca de ciclo: a prévia anterior não vale para o novo
    final sameCycle = state.preview?.cycle == finance.currentCycle;
    final keep = sameCycle ? state.preview : null;
    final keepSummary = sameCycle ? state.summary : null;
    emit(ReportsState(status: ReportsStatus.loading, preview: keep, summary: keepSummary));
    try {
      final summary = await _settlementRepository.getSettlementSummary(finance.currentCycle);
      if (sequence != _sequence || isClosed) return;
      final preview = _builder.build(
        summary: summary,
        members: finance.members,
        expenses: finance.expenses,
        paymentMethods: finance.paymentMethods,
        estimate: finance.fundingEstimate?.cycle == finance.currentCycle
            ? finance.fundingEstimate
            : null,
        today: _now(),
      );
      emit(ReportsState(status: ReportsStatus.loaded, preview: preview, summary: summary));
    } catch (e) {
      if (sequence != _sequence || isClosed) return;
      emit(ReportsState(
        status: ReportsStatus.failure,
        preview: keep,
        summary: keepSummary,
        errorMessage: 'Não foi possível montar a prévia do fechamento: $e',
      ));
    }
  }
}
