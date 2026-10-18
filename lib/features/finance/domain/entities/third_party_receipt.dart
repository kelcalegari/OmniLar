import 'package:equatable/equatable.dart';
import '../../../../core/domain/value_objects/money.dart';

/// Como uma entrada de terceiros foi usada.
enum ThirdPartyReceiptUse {
  /// A Casa pagou a fatura: o valor saiu da caixinha pelo banco.
  housePaid('house_paid'),

  /// Quem pagou a fatura foi o titular: o valor foi repassado a ele.
  passedToOwner('passed_to_owner');

  final String dbValue;
  const ThirdPartyReceiptUse(this.dbValue);

  static ThirdPartyReceiptUse? fromDb(String? value) =>
      values.where((u) => u.dbValue == value).firstOrNull;
}

/// Dinheiro de quem não mora na casa que entrou na conta da Casa para pagar
/// uma compra (ex.: o Pix das marmitas compradas no cartão de um morador).
/// Fica guardado numa caixinha, fora do Caixa do ciclo e sem virar aporte de
/// ninguém, até a fatura ser paga.
class ThirdPartyReceipt extends Equatable {
  final String id;
  final String payerName;
  final String? description;
  final Money amount;
  final DateTime receivedOn;

  /// Caixinha onde o valor fica guardado.
  final String vaultId;

  /// Cartão cuja fatura a entrada ajuda a pagar (null: ainda não se sabe).
  final String? paymentMethodId;

  /// Como foi usada (null: ainda guardada).
  final ThirdPartyReceiptUse? use;

  /// Fatura em que foi usada.
  final String? usedPaymentMethodId;
  final DateTime? usedDueDate;
  final DateTime? usedAt;

  const ThirdPartyReceipt({
    required this.id,
    required this.payerName,
    this.description,
    required this.amount,
    required this.receivedOn,
    required this.vaultId,
    this.paymentMethodId,
    this.use,
    this.usedPaymentMethodId,
    this.usedDueDate,
    this.usedAt,
  });

  bool get isHeld => use == null;
  bool get isUsed => use != null;

  /// Guardada para o cartão [cardId], ou sem cartão definido.
  bool fitsCard(String cardId) => paymentMethodId == null || paymentMethodId == cardId;

  ThirdPartyReceipt markUsed({
    required ThirdPartyReceiptUse use,
    String? paymentMethodId,
    DateTime? dueDate,
    required DateTime at,
  }) =>
      ThirdPartyReceipt(
        id: id,
        payerName: payerName,
        description: description,
        amount: amount,
        receivedOn: receivedOn,
        vaultId: vaultId,
        paymentMethodId: this.paymentMethodId,
        use: use,
        usedPaymentMethodId: paymentMethodId,
        usedDueDate: dueDate,
        usedAt: at,
      );

  ThirdPartyReceipt reopened() => ThirdPartyReceipt(
        id: id,
        payerName: payerName,
        description: description,
        amount: amount,
        receivedOn: receivedOn,
        vaultId: vaultId,
        paymentMethodId: paymentMethodId,
      );

  /// Soma das entradas.
  static Money total(Iterable<ThirdPartyReceipt> receipts) =>
      Money(receipts.fold<int>(0, (acc, r) => acc + r.amount.cents));

  @override
  List<Object?> get props => [
        id,
        payerName,
        description,
        amount,
        receivedOn,
        vaultId,
        paymentMethodId,
        use,
        usedPaymentMethodId,
        usedDueDate,
        usedAt,
      ];
}
