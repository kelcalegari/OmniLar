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

  PaymentMethod copyWith({
    String? id,
    String? name,
    PaymentMethodType? type,
    String? ownerMemberId,
    bool clearOwner = false,
    int? closingDay,
    bool clearClosingDay = false,
    int? dueDay,
    bool clearDueDay = false,
    String? colorHex,
    bool clearColorHex = false,
  }) {
    return PaymentMethod(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      ownerMemberId: clearOwner ? null : (ownerMemberId ?? this.ownerMemberId),
      closingDay: clearClosingDay ? null : (closingDay ?? this.closingDay),
      dueDay: clearDueDay ? null : (dueDay ?? this.dueDay),
      colorHex: clearColorHex ? null : (colorHex ?? this.colorHex),
    );
  }

  @override
  List<Object?> get props => [id, name, type, ownerMemberId, closingDay, dueDay, colorHex];
}
