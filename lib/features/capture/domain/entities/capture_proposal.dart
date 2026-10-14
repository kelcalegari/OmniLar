import '../../../../core/domain/value_objects/money.dart';

enum DocumentType {
  nfce, // Cupom fiscal eletrônico / Nota
  boleto, // Boleto bancário ou conta de consumo
  pixReceipt, // Comprovante de transferência Pix
  generic,
}

enum ConfidenceLevel { high, medium, low }

class ExtractedField<T> {
  final T value;
  final ConfidenceLevel confidence;
  final bool isUserModified;

  const ExtractedField({
    required this.value,
    this.confidence = ConfidenceLevel.high,
    this.isUserModified = false,
  });

  ExtractedField<T> copyWith({
    T? value,
    ConfidenceLevel? confidence,
    bool? isUserModified,
  }) {
    return ExtractedField<T>(
      value: value ?? this.value,
      confidence: confidence ?? this.confidence,
      isUserModified: isUserModified ?? this.isUserModified,
    );
  }
}

class InvoiceItemDraft {
  final String id;
  final String name;
  final int quantity;
  final Money unitPrice;
  final Money totalPrice;
  final bool isPersonal;
  final String? assignedMemberId;

  const InvoiceItemDraft({
    required this.id,
    required this.name,
    this.quantity = 1,
    required this.unitPrice,
    required this.totalPrice,
    this.isPersonal = false,
    this.assignedMemberId,
  });

  InvoiceItemDraft copyWith({
    String? name,
    int? quantity,
    Money? unitPrice,
    Money? totalPrice,
    bool? isPersonal,
    String? assignedMemberId,
  }) {
    return InvoiceItemDraft(
      id: id,
      name: name ?? this.name,
      quantity: quantity ?? this.quantity,
      unitPrice: unitPrice ?? this.unitPrice,
      totalPrice: totalPrice ?? this.totalPrice,
      isPersonal: isPersonal ?? this.isPersonal,
      assignedMemberId: assignedMemberId ?? this.assignedMemberId,
    );
  }
}

class CaptureProposal {
  final String id;
  final DocumentType documentType;
  final String title;
  final Money totalAmount;
  final DateTime date;

  /// Vencimento do boleto, quando o código ou a leitura trouxe.
  final DateTime? dueDate;
  final String? merchantOrBeneficiary;
  final String? rawCode; // Linha digitável ou URL da NFC-e
  final List<InvoiceItemDraft> items;
  final String? imageUrl;
  final DateTime capturedAt;

  const CaptureProposal({
    required this.id,
    required this.documentType,
    required this.title,
    required this.totalAmount,
    required this.date,
    this.dueDate,
    this.merchantOrBeneficiary,
    this.rawCode,
    this.items = const [],
    this.imageUrl,
    required this.capturedAt,
  });

  /// Total de itens classificados como pessoais (RN09)
  Money get personalItemsAmount {
    int cents = 0;
    for (final item in items.where((i) => i.isPersonal)) {
      cents += item.totalPrice.cents;
    }
    return Money(cents);
  }

  /// Total que pertence à Casa
  Money get houseAmount => totalAmount - personalItemsAmount;

  CaptureProposal copyWith({
    DocumentType? documentType,
    String? title,
    Money? totalAmount,
    DateTime? date,
    DateTime? dueDate,
    String? merchantOrBeneficiary,
    String? rawCode,
    List<InvoiceItemDraft>? items,
    String? imageUrl,
  }) {
    return CaptureProposal(
      id: id,
      documentType: documentType ?? this.documentType,
      title: title ?? this.title,
      totalAmount: totalAmount ?? this.totalAmount,
      date: date ?? this.date,
      dueDate: dueDate ?? this.dueDate,
      merchantOrBeneficiary: merchantOrBeneficiary ?? this.merchantOrBeneficiary,
      rawCode: rawCode ?? this.rawCode,
      items: items ?? this.items,
      imageUrl: imageUrl ?? this.imageUrl,
      capturedAt: capturedAt,
    );
  }
}
