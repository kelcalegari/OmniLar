import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/domain/value_objects/financial_cycle.dart';
import '../../domain/repositories/settlement_repository.dart';
import 'settlement_state.dart';

class SettlementCubit extends BlocBase<SettlementState> {
  final SettlementRepository _repository;

  SettlementCubit(this._repository) : super(const SettlementState());

  Future<void> loadSettlement(FinancialCycle cycle) async {
    emit(state.copyWith(status: SettlementCubitStatus.loading));
    try {
      final summary = await _repository.getSettlementSummary(cycle);
      emit(state.copyWith(
        status: SettlementCubitStatus.loaded,
        summary: summary,
      ));
    } catch (e) {
      emit(state.copyWith(
        status: SettlementCubitStatus.error,
        errorMessage: 'Erro ao carregar o fechamento do ciclo: $e',
      ));
    }
  }

  Future<void> confirmSettlement() async {
    final currentSummary = state.summary;
    if (currentSummary == null) return;

    emit(state.copyWith(status: SettlementCubitStatus.confirming));
    try {
      await _repository.confirmSettlement(currentSummary);
      final updatedSummary = await _repository.getSettlementSummary(currentSummary.cycle);
      emit(state.copyWith(
        status: SettlementCubitStatus.settled,
        summary: updatedSummary,
      ));
    } catch (e) {
      emit(state.copyWith(
        status: SettlementCubitStatus.error,
        errorMessage: 'Erro ao confirmar liquidação: $e',
      ));
    }
  }
}
