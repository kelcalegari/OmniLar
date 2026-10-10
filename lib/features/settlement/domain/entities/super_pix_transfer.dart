import '../../../../core/domain/value_objects/money.dart';

enum TransferStatus {
  pending,
  paid,
  confirmed,
}

class SuperPixTransfer {
  final String id;
  final String fromMemberId;
  final String fromMemberName;
  final String toMemberId;
  final String toMemberName;
  final Money amount;
  final String description;
  final TransferStatus status;
  final String? pixKey;
  final DateTime? paidAt;

  const SuperPixTransfer({
    required this.id,
    required this.fromMemberId,
    required this.fromMemberName,
    required this.toMemberId,
    required this.toMemberName,
    required this.amount,
    required this.description,
    this.status = TransferStatus.pending,
    this.pixKey,
    this.paidAt,
  });

  SuperPixTransfer copyWith({
    String? id,
    String? fromMemberId,
    String? fromMemberName,
    String? toMemberId,
    String? toMemberName,
    Money? amount,
    String? description,
    TransferStatus? status,
    String? pixKey,
    DateTime? paidAt,
  }) {
    return SuperPixTransfer(
      id: id ?? this.id,
      fromMemberId: fromMemberId ?? this.fromMemberId,
      fromMemberName: fromMemberName ?? this.fromMemberName,
      toMemberId: toMemberId ?? this.toMemberId,
      toMemberName: toMemberName ?? this.toMemberName,
      amount: amount ?? this.amount,
      description: description ?? this.description,
      status: status ?? this.status,
      pixKey: pixKey ?? this.pixKey,
      paidAt: paidAt ?? this.paidAt,
    );
  }
}
