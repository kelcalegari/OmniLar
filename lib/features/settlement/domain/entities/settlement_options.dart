import 'package:equatable/equatable.dart';
import 'transfer_settlement_resolution.dart';

enum SurplusAction {
  toVault, // Guardar em uma Caixinha da Casa
  rollover, // Rolar como saldo inicial do próximo ciclo
  refund, // Devolver aos membros via Pix de estorno
}

enum MemberCreditAction {
  rolloverNextCycle, // Abater do aporte do próximo mês (recomendado)
  settleNow, // Fazer Pix de acerto agora via Super Pix
}

class SettlementOptions extends Equatable {
  final SurplusAction surplusAction;
  final String? targetVaultId;
  final MemberCreditAction creditAction;
  final Map<String, TransferSettlementResolution> transferResolutions;

  const SettlementOptions({
    this.surplusAction = SurplusAction.toVault,
    this.targetVaultId,
    this.creditAction = MemberCreditAction.rolloverNextCycle,
    this.transferResolutions = const {},
  });

  SettlementOptions copyWith({
    SurplusAction? surplusAction,
    String? targetVaultId,
    MemberCreditAction? creditAction,
    Map<String, TransferSettlementResolution>? transferResolutions,
  }) {
    return SettlementOptions(
      surplusAction: surplusAction ?? this.surplusAction,
      targetVaultId: targetVaultId ?? this.targetVaultId,
      creditAction: creditAction ?? this.creditAction,
      transferResolutions: transferResolutions ?? this.transferResolutions,
    );
  }

  @override
  List<Object?> get props => [
    surplusAction,
    targetVaultId,
    creditAction,
    transferResolutions,
  ];
}
