import 'dart:convert';
import 'dart:typed_data';
import '../../../../core/network/supabase_config.dart';
import '../../../../core/domain/value_objects/money.dart';
import '../../../../core/services/ai_config_service.dart';
import '../entities/capture_proposal.dart';
import 'boleto_parser.dart';

class CaptureService {
  final AiConfigService aiConfigService;
  final String? Function()? getCurrentHouseId;

  CaptureService({required this.aiConfigService, this.getCurrentHouseId});

  /// Processa arquivo de imagem ou documento PDF via Edge Function e Gemini Vision OCR.
  /// Aplica a regra "Código Primeiro": tenta identificar linha digitável de boleto antes da IA.
  Future<CaptureProposal> processDocumentFile({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
  }) async {
    // 1. CÓDIGO PRIMEIRO (RN do Omni Lar): Tenta buscar boleto diretamente no texto embutido
    CaptureProposal? codeProposal;
    try {
      final rawText = latin1.decode(bytes, allowInvalid: true);
      final foundLine = BoletoParser.findBoletoLineInText(rawText);
      if (foundLine != null) {
        codeProposal = BoletoParser.parseBoletoBancario(rawLine: foundLine);
      }
    } catch (_) {}

    final client = SupabaseConfig.client;

    try {
      if (client != null) {
        final userApiKey = await aiConfigService.getUserApiKey();
        final userModel = await aiConfigService.getSelectedModel();

        final base64Content = base64Encode(bytes);

        final response = await client.functions.invoke(
          'capture-read',
          body: {
            'imageBase64': base64Content,
            'mimeType': mimeType,
            'fileName': fileName,
            'houseId': ?getCurrentHouseId?.call(),
            if (userApiKey != null && userApiKey.isNotEmpty) 'userApiKey': userApiKey,
            'userModel': userModel,
          },
        );

        final data = response.data;
        if (data is Map<String, dynamic> && data['error'] == null) {
          // Desempacota o payload retornado pela Edge Function ({ success: true, analysis: { ... } })
          final analysis = (data['analysis'] is Map<String, dynamic>)
              ? data['analysis'] as Map<String, dynamic>
              : data;

          final totalCents = (analysis['total_cents'] as num?)?.toInt() ?? 0;
          final title = (analysis['title'] as String?)?.trim().isNotEmpty == true
              ? analysis['title'] as String
              : (fileName.toLowerCase().endsWith('.pdf') ? 'Fatura / Boleto' : 'Recibo / Cupom');
          final merchant = analysis['merchant_name'] as String?;
          final barcode = analysis['barcode'] as String? ?? codeProposal?.rawCode;
          final isItemized = analysis['is_itemized'] as bool? ?? false;

          DateTime date = DateTime.now();
          final dueDateStr = analysis['due_date'] as String?;
          if (dueDateStr != null && dueDateStr.isNotEmpty) {
            try {
              date = DateTime.parse(dueDateStr);
            } catch (_) {}
          } else if (codeProposal != null) {
            date = codeProposal.date;
          }

          final rawItems = analysis['items'] as List<dynamic>? ?? [];
          final items = <InvoiceItemDraft>[];

          for (int i = 0; i < rawItems.length; i++) {
            final itemMap = rawItems[i] as Map<String, dynamic>;
            final itemTitle = itemMap['title'] as String? ?? 'Item ${i + 1}';
            final itemAmountCents = (itemMap['amount_cents'] as num?)?.toInt() ?? 0;
            final isCommon = itemMap['is_common_expense'] as bool? ?? true;

            items.add(
              InvoiceItemDraft(
                id: 'item_$i',
                name: itemTitle,
                quantity: 1,
                unitPrice: Money(itemAmountCents),
                totalPrice: Money(itemAmountCents),
                isPersonal: !isCommon,
              ),
            );
          }

          final finalTotalCents = totalCents > 0 ? totalCents : (codeProposal?.totalAmount.cents ?? 0);

          final isBoleto = barcode != null && barcode.isNotEmpty ||
              fileName.toLowerCase().endsWith('.pdf') ||
              title.toLowerCase().contains('boleto') ||
              title.toLowerCase().contains('condomínio') ||
              title.toLowerCase().contains('fatura');

          return CaptureProposal(
            id: 'prop_${DateTime.now().millisecondsSinceEpoch}',
            documentType: isBoleto ? DocumentType.boleto : (isItemized ? DocumentType.nfce : DocumentType.generic),
            title: title,
            totalAmount: Money(finalTotalCents),
            date: date,
            merchantOrBeneficiary: merchant ?? codeProposal?.merchantOrBeneficiary,
            rawCode: barcode,
            items: items,
            capturedAt: DateTime.now(),
          );
        }
      }
    } catch (_) {
      // Falha ou indisponibilidade da Edge Function -> segue para código/fallback
    }

    // Se a IA não retornou, mas o leitor por código local identificou o boleto:
    if (codeProposal != null && codeProposal.totalAmount.cents > 0) {
      return codeProposal.copyWith(
        title: fileName.toLowerCase().contains('condom') ? 'Taxa de Condomínio' : codeProposal.title,
      );
    }

    // Fallback: Proposta editável
    final cleanName = fileName.replaceAll(RegExp(r'\.[a-zA-Z0-9]+$'), '');
    final isPdf = fileName.toLowerCase().endsWith('.pdf');

    return CaptureProposal(
      id: 'prop_${DateTime.now().millisecondsSinceEpoch}',
      documentType: isPdf ? DocumentType.boleto : DocumentType.generic,
      title: cleanName.isNotEmpty ? cleanName : (isPdf ? 'Boleto / Documento PDF' : 'Cupom / Recibo'),
      totalAmount: const Money(0),
      date: DateTime.now(),
      merchantOrBeneficiary: null,
      rawCode: null,
      items: const [],
      capturedAt: DateTime.now(),
    );
  }
}
