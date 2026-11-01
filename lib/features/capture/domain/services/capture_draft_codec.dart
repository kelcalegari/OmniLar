import 'dart:convert';
import 'dart:typed_data';

import '../../../../core/domain/value_objects/money.dart';
import '../../../finance/domain/services/receipt_attachment_service.dart';
import '../entities/capture_proposal.dart';

/// Rascunho da revisão da captura inteligente: proposta lida + o que a pessoa
/// já preencheu ou editou (título, valor, itens, vencimento, já pago, categoria,
/// meio de pagamento e anexo). O que vem do banco (conta prevista, fatura em
/// aberto) não é guardado: é buscado de novo ao retomar.
class CaptureDraft {
  final DateTime savedAt;
  final CaptureProposal proposal;
  final String titleText;
  final String amountText;
  final int originalAmountCents;
  final List<InvoiceItemDraft> originalItems;
  final String? selectedCategoryId;
  final String? selectedPaymentMethodId;
  final DateTime? dueDate;
  final bool alreadyPaid;

  /// Boleto: cadastrar como conta recorrente (e se o valor varia todo mês).
  final bool markRecurring;
  final bool recurringVariable;
  final DateTime documentDate;
  final DateTime paidOn;
  final ReceiptAttachmentFile? attachmentFile;

  const CaptureDraft({
    required this.savedAt,
    required this.proposal,
    required this.titleText,
    required this.amountText,
    required this.originalAmountCents,
    required this.originalItems,
    this.selectedCategoryId,
    this.selectedPaymentMethodId,
    this.dueDate,
    required this.alreadyPaid,
    this.markRecurring = false,
    this.recurringVariable = true,
    required this.documentDate,
    required this.paidOn,
    this.attachmentFile,
  });

  /// Rótulo exibido no aviso "Revisão em andamento".
  String get displayTitle {
    final trimmed = titleText.trim();
    if (trimmed.isNotEmpty) return trimmed;
    if (proposal.title.trim().isNotEmpty) return proposal.title.trim();
    return 'Captura';
  }
}

class CaptureDraftCodec {
  const CaptureDraftCodec._();

  static const int version = 1;

  /// Limite máximo para guardar os bytes do anexo no armazenamento seguro local
  /// (acima disso o rascunho guarda todos os campos, sem embutir o binário).
  static const int maxAttachmentPersistBytes = 2 * 1024 * 1024;

  static T? _enum<T extends Enum>(List<T> values, Object? name) =>
      values.where((v) => v.name == name).firstOrNull;

  static Map<String, dynamic> itemToJson(InvoiceItemDraft item) => {
        'id': item.id,
        'name': item.name,
        'quantity': item.quantity,
        'unitPrice': item.unitPrice.cents,
        'totalPrice': item.totalPrice.cents,
        'isPersonal': item.isPersonal,
        if (item.assignedMemberId != null) 'assignedMemberId': item.assignedMemberId,
      };

  static InvoiceItemDraft itemFromJson(Map<String, dynamic> json) => InvoiceItemDraft(
        id: json['id'] as String,
        name: json['name'] as String,
        quantity: (json['quantity'] as num?)?.toInt() ?? 1,
        unitPrice: Money((json['unitPrice'] as num).toInt()),
        totalPrice: Money((json['totalPrice'] as num).toInt()),
        isPersonal: json['isPersonal'] as bool? ?? false,
        assignedMemberId: json['assignedMemberId'] as String?,
      );

  static Map<String, dynamic> proposalToJson(CaptureProposal proposal) => {
        'id': proposal.id,
        'documentType': proposal.documentType.name,
        'title': proposal.title,
        'totalAmount': proposal.totalAmount.cents,
        'date': proposal.date.toIso8601String(),
        if (proposal.dueDate != null) 'dueDate': proposal.dueDate!.toIso8601String(),
        if (proposal.merchantOrBeneficiary != null) 'merchantOrBeneficiary': proposal.merchantOrBeneficiary,
        if (proposal.rawCode != null) 'rawCode': proposal.rawCode,
        'items': [for (final item in proposal.items) itemToJson(item)],
        if (proposal.imageUrl != null) 'imageUrl': proposal.imageUrl,
        'capturedAt': proposal.capturedAt.toIso8601String(),
      };

  static CaptureProposal proposalFromJson(Map<String, dynamic> json) => CaptureProposal(
        id: json['id'] as String,
        documentType: _enum(DocumentType.values, json['documentType']) ?? DocumentType.generic,
        title: json['title'] as String,
        totalAmount: Money((json['totalAmount'] as num).toInt()),
        date: DateTime.parse(json['date'] as String),
        dueDate: DateTime.tryParse(json['dueDate'] as String? ?? ''),
        merchantOrBeneficiary: json['merchantOrBeneficiary'] as String?,
        rawCode: json['rawCode'] as String?,
        items: [
          for (final item in (json['items'] as List? ?? const []))
            itemFromJson((item as Map).cast<String, dynamic>()),
        ],
        imageUrl: json['imageUrl'] as String?,
        capturedAt: DateTime.tryParse(json['capturedAt'] as String? ?? '') ?? DateTime.now(),
      );

  static Map<String, dynamic> toJson(CaptureDraft draft, {bool includeAttachmentBytes = true}) {
    final attachment = draft.attachmentFile;
    final canPersistBytes = includeAttachmentBytes &&
        attachment != null &&
        attachment.bytes.length <= maxAttachmentPersistBytes;

    return {
      'version': version,
      'savedAt': draft.savedAt.toIso8601String(),
      'proposal': proposalToJson(draft.proposal),
      'titleText': draft.titleText,
      'amountText': draft.amountText,
      'originalAmountCents': draft.originalAmountCents,
      'originalItems': [for (final item in draft.originalItems) itemToJson(item)],
      if (draft.selectedCategoryId != null) 'selectedCategoryId': draft.selectedCategoryId,
      if (draft.selectedPaymentMethodId != null) 'selectedPaymentMethodId': draft.selectedPaymentMethodId,
      if (draft.dueDate != null) 'dueDate': draft.dueDate!.toIso8601String(),
      'alreadyPaid': draft.alreadyPaid,
      if (draft.markRecurring) 'markRecurring': true,
      if (!draft.recurringVariable) 'recurringVariable': false,
      'documentDate': draft.documentDate.toIso8601String(),
      'paidOn': draft.paidOn.toIso8601String(),
      if (canPersistBytes)
        'attachment': {
          'name': attachment.name,
          'contentType': attachment.contentType,
          'sizeBytes': attachment.sizeBytes,
          'bytesBase64': base64Encode(attachment.bytes),
        },
    };
  }

  static CaptureDraft? fromJson(Map<String, dynamic> json) {
    try {
      if (json['version'] != version) return null;
      final proposalMap = (json['proposal'] as Map).cast<String, dynamic>();
      final proposal = proposalFromJson(proposalMap);

      ReceiptAttachmentFile? attachment;
      final rawAtt = json['attachment'];
      if (rawAtt is Map) {
        final b64 = rawAtt['bytesBase64'] as String?;
        if (b64 != null && b64.isNotEmpty) {
          final bytes = Uint8List.fromList(base64Decode(b64));
          attachment = ReceiptAttachmentFile(
            name: (rawAtt['name'] as String?) ?? 'anexo.jpg',
            bytes: bytes,
            sizeBytes: (rawAtt['sizeBytes'] as num?)?.toInt() ?? bytes.length,
            contentType: (rawAtt['contentType'] as String?) ?? 'image/jpeg',
          );
        }
      }

      return CaptureDraft(
        savedAt: DateTime.parse(json['savedAt'] as String),
        proposal: proposal,
        titleText: (json['titleText'] as String?) ?? proposal.title,
        amountText: (json['amountText'] as String?) ?? '',
        originalAmountCents: (json['originalAmountCents'] as num?)?.toInt() ?? proposal.totalAmount.cents,
        originalItems: [
          for (final item in (json['originalItems'] as List? ?? const []))
            itemFromJson((item as Map).cast<String, dynamic>()),
        ],
        selectedCategoryId: json['selectedCategoryId'] as String?,
        selectedPaymentMethodId: json['selectedPaymentMethodId'] as String?,
        dueDate: DateTime.tryParse(json['dueDate'] as String? ?? ''),
        alreadyPaid: json['alreadyPaid'] as bool? ?? (proposal.documentType != DocumentType.boleto),
        markRecurring: json['markRecurring'] as bool? ?? false,
        recurringVariable: json['recurringVariable'] as bool? ?? true,
        documentDate: DateTime.tryParse(json['documentDate'] as String? ?? '') ?? proposal.date,
        paidOn: DateTime.tryParse(json['paidOn'] as String? ?? '') ?? DateTime.now(),
        attachmentFile: attachment,
      );
    } catch (_) {
      return null;
    }
  }
}
