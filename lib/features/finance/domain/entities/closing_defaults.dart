import 'package:equatable/equatable.dart';

import '../../../settlement/domain/entities/settlement_options.dart';
import '../../../settlement/domain/entities/transfer_settlement_resolution.dart';
import 'savings_vault.dart';

/// Escolhas que o fechamento já abre marcadas (coluna `houses.closing_defaults`,
/// 0094). Quem fecha ainda pode mudar cada uma naquele ciclo. O que não tiver
/// escolha vale como antes: sobra guardada na primeira caixinha, excedente
/// rateado na proporção do aporte sem caixinha e diferença de quem pagou menos
/// virando empréstimo.
class ClosingDefaults extends Equatable {
  /// Destino da sobra.
  final SurplusAction? surplusAction;

  /// Caixinha que recebe a sobra, quando ela vai para uma caixinha.
  final String? surplusVaultId;

  /// Como ratear o que passou do balde.
  final DeficitSplit? deficitSplit;

  /// Caixinha que cobre o excedente antes do rateio.
  final String? deficitVaultId;

  /// O que fazer com a diferença de quem pagou menos.
  final ShortfallAction? shortfallAction;

  const ClosingDefaults({
    this.surplusAction,
    this.surplusVaultId,
    this.deficitSplit,
    this.deficitVaultId,
    this.shortfallAction,
  });

  static String surplusActionToDb(SurplusAction action) => switch (action) {
        SurplusAction.toVault => 'to_vault',
        SurplusAction.rollover => 'rollover',
        SurplusAction.refund => 'refund',
      };

  static SurplusAction? surplusActionFromDb(Object? value) => switch (value) {
        'to_vault' => SurplusAction.toVault,
        'rollover' => SurplusAction.rollover,
        'refund' => SurplusAction.refund,
        _ => null,
      };

  static String deficitSplitToDb(DeficitSplit split) => switch (split) {
        DeficitSplit.proportional => 'proportional',
        DeficitSplit.equal => 'equal',
      };

  static DeficitSplit? deficitSplitFromDb(Object? value) => switch (value) {
        'proportional' => DeficitSplit.proportional,
        'equal' => DeficitSplit.equal,
        _ => null,
      };

  static String shortfallActionToDb(ShortfallAction action) => switch (action) {
        ShortfallAction.createP2PLoan => 'create_p2p_loan',
        ShortfallAction.deductFromVault => 'deduct_from_vault',
        ShortfallAction.rolloverPending => 'rollover_pending',
        ShortfallAction.forgiveRemainder => 'forgive_remainder',
      };

  static ShortfallAction? shortfallActionFromDb(Object? value) => switch (value) {
        'create_p2p_loan' => ShortfallAction.createP2PLoan,
        'deduct_from_vault' => ShortfallAction.deductFromVault,
        'rollover_pending' => ShortfallAction.rolloverPending,
        'forgive_remainder' => ShortfallAction.forgiveRemainder,
        _ => null,
      };

  factory ClosingDefaults.fromJson(Object? json) {
    if (json is! Map) return const ClosingDefaults();
    String? id(Object? value) => value is String && value.isNotEmpty ? value : null;
    return ClosingDefaults(
      surplusAction: surplusActionFromDb(json['surplus_action']),
      surplusVaultId: id(json['surplus_vault_id']),
      deficitSplit: deficitSplitFromDb(json['deficit_split']),
      deficitVaultId: id(json['deficit_vault_id']),
      shortfallAction: shortfallActionFromDb(json['shortfall_action']),
    );
  }

  Map<String, dynamic> toJson() => {
        'surplus_action': ?(surplusAction == null ? null : surplusActionToDb(surplusAction!)),
        'surplus_vault_id': ?surplusVaultId,
        'deficit_split': ?(deficitSplit == null ? null : deficitSplitToDb(deficitSplit!)),
        'deficit_vault_id': ?deficitVaultId,
        'shortfall_action': ?(shortfallAction == null ? null : shortfallActionToDb(shortfallAction!)),
      };

  bool get isEmpty =>
      surplusAction == null &&
      surplusVaultId == null &&
      deficitSplit == null &&
      deficitVaultId == null &&
      shortfallAction == null;

  /// Opções do fechamento com os padrões da casa por cima de [options]. Caixinha
  /// que não existe mais (ou, para cobrir o excedente, sem saldo) é ignorada.
  SettlementOptions applyTo(SettlementOptions options, List<SavingsVault> vaults) {
    final surplusVault = vaults.any((v) => v.id == surplusVaultId) ? surplusVaultId : null;
    final deficitVault =
        vaults.any((v) => v.id == deficitVaultId && v.currentBalance.cents > 0) ? deficitVaultId : null;
    return options.copyWith(
      surplusAction: surplusAction,
      targetVaultId: surplusVault,
      deficitSplit: deficitSplit,
      deficitVaultId: deficitVault,
    );
  }

  /// Caixinha da sobra guardada como padrão, se ainda existe.
  String? surplusVaultIn(List<SavingsVault> vaults) =>
      vaults.any((v) => v.id == surplusVaultId) ? surplusVaultId : null;

  /// Caixinha do excedente guardada como padrão, se ainda existe.
  String? deficitVaultIn(List<SavingsVault> vaults) =>
      vaults.any((v) => v.id == deficitVaultId) ? deficitVaultId : null;

  @override
  List<Object?> get props => [surplusAction, surplusVaultId, deficitSplit, deficitVaultId, shortfallAction];
}
