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

  /// Morador que costuma pagar a fatura do cartão (0100): só sugestão, a
  /// escolha manual sempre vence.
  final String? usualInvoicePayerId;

  const PaymentMethod({
    required this.id,
    required this.name,
    required this.type,
    this.ownerMemberId,
    this.closingDay,
    this.dueDay,
    this.colorHex,
    this.usualInvoicePayerId,
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
    String? usualInvoicePayerId,
    bool clearUsualInvoicePayer = false,
  }) {
    return PaymentMethod(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      ownerMemberId: clearOwner ? null : (ownerMemberId ?? this.ownerMemberId),
      closingDay: clearClosingDay ? null : (closingDay ?? this.closingDay),
      dueDay: clearDueDay ? null : (dueDay ?? this.dueDay),
      colorHex: clearColorHex ? null : (colorHex ?? this.colorHex),
      usualInvoicePayerId:
          clearUsualInvoicePayer ? null : (usualInvoicePayerId ?? this.usualInvoicePayerId),
    );
  }

  @override
  List<Object?> get props => [id, name, type, ownerMemberId, closingDay, dueDay, colorHex, usualInvoicePayerId];
}
