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

  const SavingsVault({
    required this.id,
    required this.name,
    required this.targetAmount,
    this.currentBalance = const Money.zero(),
    this.icon = 'savings',
    this.colorHex = '#10B981',
    required this.createdAt,
  });

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
  }) {
    return SavingsVault(
      id: id ?? this.id,
      name: name ?? this.name,
      targetAmount: targetAmount ?? this.targetAmount,
      currentBalance: currentBalance ?? this.currentBalance,
      icon: icon ?? this.icon,
      colorHex: colorHex ?? this.colorHex,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  List<Object?> get props => [id, name, targetAmount, currentBalance, icon, colorHex, createdAt];
}

class SavingsTransaction extends Equatable {
  final String id;
  final String vaultId;
  final String memberId;
  final Money amount;
  final String type; // 'deposit' ou 'withdraw'
  final String description;
  final DateTime date;

  /// Ciclo cujo Caixa recebeu o resgate (nulo: o valor só saiu da caixinha).
  final DateTime? cycleStartDate;

  const SavingsTransaction({
    required this.id,
    required this.vaultId,
    required this.memberId,
    required this.amount,
    required this.type,
    required this.description,
    required this.date,
    this.cycleStartDate,
  });

  bool get isDeposit => type == 'deposit';
  bool get isWithdraw => type == 'withdraw';
  bool get returnedToCycle => isWithdraw && cycleStartDate != null;

  @override
  List<Object?> get props => [id, vaultId, memberId, amount, type, description, date, cycleStartDate];
}
