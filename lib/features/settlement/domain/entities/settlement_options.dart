import '../services/open_invoice_choices.dart';
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

/// Como ratear entre os moradores o que os gastos passaram do balde (aportes fixos).
enum DeficitSplit {
  proportional, // Na proporção do aporte fixo de cada morador
  equal, // Em partes iguais
}

class SettlementOptions extends Equatable {
  final SurplusAction surplusAction;
  final String? targetVaultId;
  final MemberCreditAction creditAction;
  final Map<String, TransferSettlementResolution> transferResolutions;
  final DeficitSplit deficitSplit;
  final String? deficitVaultId; // Caixinha que cobre o excedente antes do rateio

  /// O que fazer com cada fatura de cartão em aberto (pela chave da fatura).
  /// Sem escolha, vale a baixa como um boleto.
  final Map<String, OpenInvoiceChoice> openInvoiceChoices;

  const SettlementOptions({
    this.surplusAction = SurplusAction.toVault,
    this.targetVaultId,
    this.creditAction = MemberCreditAction.rolloverNextCycle,
    this.transferResolutions = const {},
    this.deficitSplit = DeficitSplit.proportional,
    this.deficitVaultId,
    this.openInvoiceChoices = const {},
  });

  SettlementOptions copyWith({
    SurplusAction? surplusAction,
    String? targetVaultId,
    MemberCreditAction? creditAction,
    Map<String, TransferSettlementResolution>? transferResolutions,
    DeficitSplit? deficitSplit,
    String? deficitVaultId,
    bool clearDeficitVault = false,
    Map<String, OpenInvoiceChoice>? openInvoiceChoices,
  }) {
    return SettlementOptions(
      surplusAction: surplusAction ?? this.surplusAction,
      targetVaultId: targetVaultId ?? this.targetVaultId,
      creditAction: creditAction ?? this.creditAction,
      transferResolutions: transferResolutions ?? this.transferResolutions,
      deficitSplit: deficitSplit ?? this.deficitSplit,
      deficitVaultId: clearDeficitVault ? null : (deficitVaultId ?? this.deficitVaultId),
      openInvoiceChoices: openInvoiceChoices ?? this.openInvoiceChoices,
    );
  }

  @override
  List<Object?> get props => [
    surplusAction,
    targetVaultId,
    creditAction,
    openInvoiceChoices,
    transferResolutions,
    deficitSplit,
    deficitVaultId,
  ];
}
