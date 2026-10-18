import 'package:equatable/equatable.dart';

import '../../../../core/domain/value_objects/financial_cycle.dart';
import '../../../../core/domain/value_objects/money.dart';

/// Dinheiro que a casa já tinha quando começou a usar o app (colunas de
/// `houses`, 0093).
class HouseInitialBalance extends Equatable {
  /// Reserva guardada: entrou na Reserva da Casa como saldo inicial, sem
  /// passar pelo Caixa do ciclo.
  final Money reserve;

  /// Saldo na conta da casa: vale como a sobra do primeiro ciclo.
  final Money cash;

  /// Início do ciclo em que [cash] entra (o primeiro da casa).
  final DateTime? cashCycleStart;

  const HouseInitialBalance({
    this.reserve = const Money.zero(),
    this.cash = const Money.zero(),
    this.cashCycleStart,
  });

  /// Colunas lidas de `houses`.
  static const String columns = 'initial_reserve_cents, initial_cash_cents, initial_cash_cycle_start';

  factory HouseInitialBalance.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const HouseInitialBalance();
    final reserve = (json['initial_reserve_cents'] as num?)?.toInt() ?? 0;
    final cash = (json['initial_cash_cents'] as num?)?.toInt() ?? 0;
    final rawStart = json['initial_cash_cycle_start'];
    final start = rawStart is String ? DateTime.tryParse(rawStart) : null;
    return HouseInitialBalance(
      reserve: Money(reserve > 0 ? reserve : 0),
      cash: Money(cash > 0 ? cash : 0),
      cashCycleStart: start == null ? null : DateTime(start.year, start.month, start.day),
    );
  }

  bool get isEmpty => reserve.isZero && cash.isZero;

  /// Sobra que o saldo na conta deixa no Caixa de [cycle]: só no ciclo em que
  /// a casa começou e só sem fechamento anterior (com ele, vale a sobra do
  /// fechamento).
  Money rolledSurplusFor(FinancialCycle cycle, {required bool hasPreviousSettlement}) {
    final start = cashCycleStart;
    if (hasPreviousSettlement || start == null || cash.isZero) return const Money.zero();
    final cycleStart = cycle.startDate;
    final sameDay =
        start.year == cycleStart.year && start.month == cycleStart.month && start.day == cycleStart.day;
    return sameDay ? cash : const Money.zero();
  }

  @override
  List<Object?> get props => [reserve, cash, cashCycleStart];
}
