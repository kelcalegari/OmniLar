import 'package:equatable/equatable.dart';
import '../../../../core/domain/value_objects/money.dart';

class SavingsVault extends Equatable {
  final String id;
  final String name;
  final Money targetAmount;
  final Money currentBalance;
  final String icon;
  final String colorHex;
  final DateTime createdAt;

  /// Prazo da meta (opcional).
  final DateTime? targetDate;

  /// Meta mensal de aporte (0102). Nula: vale o quanto guardar por mês até o prazo.
  final Money? monthlyGoal;

  /// Soma a meta mensal à cota do Planejamento de Aportes (0102). Falso mantém
  /// o comportamento de antes: a caixinha não entra na cota.
  final bool countsInQuota;

  const SavingsVault({
    required this.id,
    required this.name,
    required this.targetAmount,
    this.currentBalance = const Money.zero(),
    this.icon = 'savings',
    this.colorHex = '#10B981',
    required this.createdAt,
    this.targetDate,
    this.monthlyGoal,
    this.countsInQuota = false,
  });

  bool get hasGoal => targetAmount.cents > 0;

  /// Quanto falta para a meta (zero quando atingida ou sem meta).
  Money get remainingToGoal {
    final cents = targetAmount.cents - currentBalance.cents;
    return Money(hasGoal && cents > 0 ? cents : 0);
  }

  /// Meses até o prazo, contando o mês atual (mínimo 1). Nulo sem prazo.
  int? monthsLeft(DateTime today) {
    final date = targetDate;
    if (date == null) return null;
    final months = (date.year - today.year) * 12 + date.month - today.month + 1;
    return months < 1 ? 1 : months;
  }

  /// Quanto guardar por mês para chegar à meta no prazo. Nulo sem meta ou sem prazo.
  Money? monthlyNeeded(DateTime today) {
    final months = monthsLeft(today);
    if (!hasGoal || months == null) return null;
    return Money((remainingToGoal.cents / months).ceil());
  }

  /// Quanto esta caixinha soma à cota do mês no Planejamento de Aportes: zero
  /// se não está marcada, se a meta foi atingida ou se não há meta mensal nem
  /// prazo. A meta mensal própria vale sobre o cálculo pelo prazo.
  Money quotaContribution(DateTime today) {
    if (!countsInQuota || isGoalReached) return const Money.zero();
    final goal = monthlyGoal;
    if (goal != null && goal.cents > 0) {
      // Nunca soma mais do que falta para a meta, quando há meta de valor
      if (hasGoal && goal.cents > remainingToGoal.cents) return remainingToGoal;
      return goal;
    }
    return monthlyNeeded(today) ?? const Money.zero();
  }

  /// Prazo vencido sem a meta atingida.
  bool isOverdue(DateTime today) {
    final date = targetDate;
    if (date == null || !hasGoal || isGoalReached) return false;
    return DateTime(today.year, today.month, today.day).isAfter(date);
  }

  /// Ritmo abaixo do necessário: o saldo está atrás da linha reta entre a
  /// criação da caixinha e o prazo.
  bool isBehindPace(DateTime today) {
    final date = targetDate;
    if (date == null || !hasGoal || isGoalReached) return false;
    if (isOverdue(today)) return true;
    final start = DateTime(createdAt.year, createdAt.month, createdAt.day);
    final totalDays = date.difference(start).inDays;
    if (totalDays <= 0) return false;
    final elapsed = DateTime(today.year, today.month, today.day).difference(start).inDays;
    final expected = targetAmount.cents * elapsed / totalDays;
    return currentBalance.cents < expected;
  }

  double get progressPercent {
    if (targetAmount.cents <= 0) return 1.0;
    return (currentBalance.cents / targetAmount.cents).clamp(0.0, 1.0);
  }

  bool get isGoalReached => currentBalance >= targetAmount;

  SavingsVault copyWith({
    String? id,
    String? name,
    Money? targetAmount,
    Money? currentBalance,
    String? icon,
    String? colorHex,
    DateTime? createdAt,
    DateTime? targetDate,
    bool clearTargetDate = false,
    Money? monthlyGoal,
    bool clearMonthlyGoal = false,
    bool? countsInQuota,
  }) {
    return SavingsVault(
      id: id ?? this.id,
      name: name ?? this.name,
      targetAmount: targetAmount ?? this.targetAmount,
      currentBalance: currentBalance ?? this.currentBalance,
      icon: icon ?? this.icon,
      colorHex: colorHex ?? this.colorHex,
      createdAt: createdAt ?? this.createdAt,
      targetDate: clearTargetDate ? null : (targetDate ?? this.targetDate),
      monthlyGoal: clearMonthlyGoal ? null : (monthlyGoal ?? this.monthlyGoal),
      countsInQuota: countsInQuota ?? this.countsInQuota,
    );
  }

  @override
  List<Object?> get props => [id, name, targetAmount, currentBalance, icon, colorHex, createdAt, targetDate, monthlyGoal, countsInQuota];
}

class SavingsTransaction extends Equatable {
  final String id;
  final String vaultId;
  final String memberId;
  final Money amount;
  final String type; // 'deposit' ou 'withdraw'
  final String description;
  final DateTime date;

  /// Ciclo cujo Caixa trocou dinheiro com a caixinha: recebeu o resgate ou
  /// pagou o depósito (nulo: o dinheiro veio de fora ou só saiu da caixinha).
  final DateTime? cycleStartDate;

  /// Outra caixinha da transferência (nulo: não é transferência).
  final String? counterpartVaultId;

  const SavingsTransaction({
    required this.id,
    required this.vaultId,
    required this.memberId,
    required this.amount,
    required this.type,
    required this.description,
    required this.date,
    this.cycleStartDate,
    this.counterpartVaultId,
  });

  bool get isDeposit => type == 'deposit';
  bool get isWithdraw => type == 'withdraw';
  bool get returnedToCycle => isWithdraw && cycleStartDate != null;
  bool get takenFromCycle => isDeposit && cycleStartDate != null;
  bool get isTransfer => counterpartVaultId != null;

  @override
  List<Object?> get props => [id, vaultId, memberId, amount, type, description, date, cycleStartDate, counterpartVaultId];
}

/// Filtro do histórico da caixinha.
enum VaultHistoryFilter {
  all('Tudo'),
  deposits('Entradas'),
  withdrawals('Saídas'),
  cycle('Caixa do ciclo'),
  transfers('Transferências');

  final String label;
  const VaultHistoryFilter(this.label);

  bool matches(SavingsTransaction t) => switch (this) {
        VaultHistoryFilter.all => true,
        VaultHistoryFilter.deposits => t.isDeposit,
        VaultHistoryFilter.withdrawals => t.isWithdraw,
        VaultHistoryFilter.cycle => t.cycleStartDate != null,
        VaultHistoryFilter.transfers => t.isTransfer,
      };
}
