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

/// Em qual ciclo a compra no cartão conta (coluna `payment_methods.cycle_assignment`, 0104).
enum CardCycleAssignment {
  /// Como sempre: no ciclo do vencimento da fatura (ou do pagamento dela).
  invoiceDue('invoice_due'),

  /// No ciclo da data da compra, pague a fatura quando pagar.
  purchaseDate('purchase_date');

  final String dbValue;
  const CardCycleAssignment(this.dbValue);

  /// Valor desconhecido ou ausente vale o de sempre (vencimento da fatura).
  static CardCycleAssignment fromDb(Object? value) {
    for (final a in values) {
      if (a.dbValue == value) return a;
    }
    return invoiceDue;
  }

  String get label => switch (this) {
        CardCycleAssignment.invoiceDue => 'No vencimento da fatura',
        CardCycleAssignment.purchaseDate => 'Na data da compra',
      };

  String get description => switch (this) {
        CardCycleAssignment.invoiceDue =>
          'A compra pesa no ciclo em que a fatura vence (ou é paga).',
        CardCycleAssignment.purchaseDate =>
          'A compra pesa no ciclo em que foi feita, mesmo com a fatura em aberto.',
      };
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

  /// Em qual ciclo as compras deste cartão contam (0104).
  final CardCycleAssignment cycleAssignment;

  /// Falso para saldo próprio, como o vale-alimentação (0122): a despesa paga
  /// com esta forma conta como despesa da casa, mas não entra no rateio, não
  /// gera reembolso, não sai do Caixa e não mexe no Fôlego.
  final bool consumesContributions;

  const PaymentMethod({
    required this.id,
    required this.name,
    required this.type,
    this.ownerMemberId,
    this.closingDay,
    this.dueDay,
    this.colorHex,
    this.usualInvoicePayerId,
    this.cycleAssignment = CardCycleAssignment.invoiceDue,
    this.consumesContributions = true,
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
    CardCycleAssignment? cycleAssignment,
    bool? consumesContributions,
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
      cycleAssignment: cycleAssignment ?? this.cycleAssignment,
      consumesContributions: consumesContributions ?? this.consumesContributions,
    );
  }

  @override
  List<Object?> get props => [id, name, type, ownerMemberId, closingDay, dueDay, colorHex, usualInvoicePayerId, cycleAssignment, consumesContributions];
}
