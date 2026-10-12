import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/domain/value_objects/financial_cycle.dart';
import '../../../finance/domain/repositories/finance_repository.dart';
import '../../domain/entities/settlement_options.dart';
import '../../domain/entities/settlement_summary.dart';
import '../../domain/entities/transfer_settlement_resolution.dart';
import '../../domain/repositories/settlement_repository.dart';
import 'settlement_state.dart';

class SettlementCubit extends BlocBase<SettlementState> {
  final SettlementRepository _repository;
  final FinanceRepository? _financeRepository;

  SettlementCubit(this._repository, [this._financeRepository])
    : super(const SettlementState());

  Future<void> loadSettlement(FinancialCycle cycle) async {
    emit(
      state.copyWith(
        status: SettlementCubitStatus.loading,
        currentCycle: cycle,
      ),
    );
    try {
      final summary = await _repository.getSettlementSummary(cycle);

      // Carrega as Caixinhas da Casa para permitir seleção no fechamento
      var vaults = state.vaults;
      if (_financeRepository != null && vaults.isEmpty) {
        try {
          vaults = await _financeRepository.getSavingsVaults();
        } catch (_) {}
      }

      final defaultVaultId =
          state.options.targetVaultId ?? vaults.firstOrNull?.id;
      final options = state.options.copyWith(targetVaultId: defaultVaultId);

      emit(
        state.copyWith(
          status: SettlementCubitStatus.loaded,
          currentCycle: cycle,
          summary: summary,
          vaults: vaults,
          options: options,
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(
          status: SettlementCubitStatus.error,
          errorMessage: 'Erro ao carregar o fechamento do ciclo: $e',
        ),
      );
    }
  }

  void previousCycle(int cycleStartDay) {
    final cycle = state.currentCycle ?? state.summary?.cycle;
    if (cycle != null) {
      loadSettlement(cycle.previous(cycleStartDay));
    }
  }

  void nextCycle(int cycleStartDay) {
    final cycle = state.currentCycle ?? state.summary?.cycle;
    if (cycle != null) {
      loadSettlement(cycle.next(cycleStartDay));
    }
  }

  void updateSurplusAction(SurplusAction action) {
    emit(
      state.copyWith(options: state.options.copyWith(surplusAction: action)),
    );
  }

  void updateTargetVaultId(String vaultId) {
    emit(
      state.copyWith(options: state.options.copyWith(targetVaultId: vaultId)),
    );
  }

  void updateCreditAction(MemberCreditAction action) {
    emit(state.copyWith(options: state.options.copyWith(creditAction: action)));
  }

  void updateTransferResolution(TransferSettlementResolution resolution) {
    final updatedMap = Map<String, TransferSettlementResolution>.from(
      state.options.transferResolutions,
    );
    updatedMap[resolution.transferId] = resolution;
    emit(
      state.copyWith(
        options: state.options.copyWith(transferResolutions: updatedMap),
      ),
    );
  }

  void removeTransferResolution(String transferId) {
    final updatedMap = Map<String, TransferSettlementResolution>.from(
      state.options.transferResolutions,
    );
    updatedMap.remove(transferId);
    emit(
      state.copyWith(
        options: state.options.copyWith(transferResolutions: updatedMap),
      ),
    );
  }

  Future<void> confirmSettlement() async {
    final currentSummary = state.summary;
    if (currentSummary == null) return;

    emit(state.copyWith(status: SettlementCubitStatus.confirming));
    try {
      // Recalcula antes de gravar: se alguém pagou ou lançou algo com a tela
      // aberta (ex: antecipou uma parcela P2P), o Super Pix exibido está defasado.
      final freshSummary = await _repository.getSettlementSummary(
        currentSummary.cycle,
      );
      if (_fingerprint(freshSummary) != _fingerprint(currentSummary)) {
        emit(
          state.copyWith(
            status: SettlementCubitStatus.error,
            errorMessage:
                'Os valores mudaram desde que você abriu o fechamento. Revise as transferências e confirme de novo.',
          ),
        );
        emit(
          state.copyWith(
            status: SettlementCubitStatus.loaded,
            summary: freshSummary,
            // As resoluções foram decididas sobre transferências que não valem mais.
            options: state.options.copyWith(transferResolutions: const {}),
          ),
        );
        return;
      }

      await _repository.confirmSettlement(
        currentSummary,
        options: state.options,
      );
      final updatedSummary = await _repository.getSettlementSummary(
        currentSummary.cycle,
      );
      emit(
        state.copyWith(
          status: SettlementCubitStatus.settled,
          summary: updatedSummary,
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(
          status: SettlementCubitStatus.error,
          errorMessage: 'Erro ao confirmar liquidação: $e',
        ),
      );
    }
  }

  /// Resumo dos valores que o usuário revisou: totais e transferências do Super Pix.
  String _fingerprint(SettlementSummary summary) {
    final transfers = summary.transfers
        .map((t) => '${t.fromMemberId}>${t.toMemberId}:${t.amount.cents}')
        .toList()
      ..sort();
    return [
      summary.status.name,
      summary.totalHouseExpenses.cents,
      summary.totalContributions.cents,
      summary.totalP2PCleared.cents,
      ...transfers,
    ].join('|');
  }

  Future<void> reopenSettlement() async {
    final cycle = state.currentCycle ?? state.summary?.cycle;
    if (cycle == null) return;

    emit(state.copyWith(status: SettlementCubitStatus.loading));
    try {
      await _repository.reopenSettlement(cycle);
      final refreshed = await _repository.getSettlementSummary(cycle);
      emit(
        state.copyWith(
          status: SettlementCubitStatus.loaded,
          summary: refreshed,
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(
          status: SettlementCubitStatus.error,
          errorMessage: 'Erro ao reabrir ciclo: $e',
        ),
      );
    }
  }
}
