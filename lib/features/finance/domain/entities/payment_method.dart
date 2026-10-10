import 'package:equatable/equatable.dart';

enum PaymentMethodType {
  card,
  vr,
  va,
  pix,
  account,
  cash,
  other,
}

class PaymentMethod extends Equatable {
  final String id;
  final String name;
  final PaymentMethodType type;
  final String? ownerMemberId; // null se for compartilhado da casa
  final int? closingDay;
  final int? dueDay;
  final String? colorHex;

  const PaymentMethod({
    required this.id,
    required this.name,
    required this.type,
    this.ownerMemberId,
    this.closingDay,
    this.dueDay,
    this.colorHex,
  });

  bool get isBenefit => type == PaymentMethodType.vr || type == PaymentMethodType.va;
  bool get isCreditCard => type == PaymentMethodType.card;

  @override
  List<Object?> get props => [id, name, type, ownerMemberId, closingDay, dueDay, colorHex];
}
