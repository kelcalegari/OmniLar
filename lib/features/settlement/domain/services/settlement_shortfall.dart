import '../../../../core/domain/value_objects/money.dart';
import '../../../p2p/domain/entities/p2p_loan.dart';
import '../entities/settlement_options.dart';
import '../entities/settlement_summary.dart';
import '../entities/transfer_settlement_resolution.dart';

/// O que o Caixa da Casa deixa de receber neste fechamento: a parte do Super
/// Pix que um morador não pagou e que não foi coberta por uma Caixinha.
/// Esse dinheiro não está no Caixa, então não pode entrar na sobra.
Money unpaidToHouse(SettlementSummary summary, SettlementOptions? options) {
  return Money(
    houseShortfallFinanced(summary, options).cents +
        houseShortfallForgiven(summary, options).cents,
  );
}

/// Parte não paga ao Caixa que virou acordo com o Lar (financiada ou pendente).
Money houseShortfallFinanced(SettlementSummary summary, SettlementOptions? options) =>
    _houseShortfall(summary, options, forgiven: false);

/// Parte não paga ao Caixa que a casa perdoou.
Money houseShortfallForgiven(SettlementSummary summary, SettlementOptions? options) =>
    _houseShortfall(summary, options, forgiven: true);

Money _houseShortfall(
  SettlementSummary summary,
  SettlementOptions? options, {
  required bool forgiven,
}) {
  int cents = 0;
  for (final t in summary.transfers) {
    if (t.toMemberId != P2PLoan.houseLenderId) continue;
    final resolution = options?.transferResolutions[t.id];
    if (resolution == null || !resolution.isPartialPayment) continue;
    final action = resolution.shortfallAction;
    if (action == ShortfallAction.deductFromVault && resolution.vaultId != null) continue;
    if ((action == ShortfallAction.forgiveRemainder) != forgiven) continue;
    cents += resolution.shortfall.cents;
  }
  return Money(cents);
}

/// Sobra que o fechamento pode de fato movimentar (guardar ou deixar no Caixa).
Money availableSurplus(SettlementSummary summary, SettlementOptions? options) {
  final cents =
      summary.houseTreasuryBalance.cents - unpaidToHouse(summary, options).cents;
  return Money(cents > 0 ? cents : 0);
}
