import 'dart:convert';
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart' show FunctionException;
import '../../../../core/network/supabase_config.dart';
import '../../../../core/domain/value_objects/money.dart';
import '../../../../core/services/ai_config_service.dart';
import '../entities/capture_proposal.dart';
import 'boleto_code.dart';
import 'boleto_parser.dart';

class CaptureService {
  final AiConfigService aiConfigService;
  final String? Function()? getCurrentHouseId;

  CaptureService({required this.aiConfigService, this.getCurrentHouseId});

  /// Consulta a NFC-e na Sefaz pelo link do QR (Edge Function nfce-read).
  /// Lança [NfceLookupError] com a mensagem para o usuário quando não consegue.
  Future<CaptureProposal> lookupNfce(String qrUrl) async {
    final client = SupabaseConfig.client;
    if (client == null) throw const NfceLookupError('Consulta da nota indisponível sem conexão com o servidor.');

    final userApiKey = await aiConfigService.getUserApiKey();
    final userModel = await aiConfigService.getSelectedModel();

    Object? data;
    try {
      final response = await client.functions.invoke(
        'nfce-read',
        body: {
          'url': qrUrl,
          'houseId': ?getCurrentHouseId?.call(),
          if (userApiKey != null && userApiKey.isNotEmpty) 'userApiKey': userApiKey,
          'userModel': userModel,
        },
      );
      data = response.data;
    } on FunctionException catch (e) {
      final details = e.details;
      final message = details is Map ? details['error'] as String? : null;
      throw NfceLookupError(message ?? 'Não foi possível consultar a nota na Sefaz.');
    } catch (_) {
      throw const NfceLookupError('Não foi possível consultar a nota na Sefaz.');
    }

    final analysis = data is Map<String, dynamic> ? data['analysis'] : null;
    if (analysis is! Map<String, dynamic>) {
      throw const NfceLookupError('A Sefaz não devolveu os dados da nota.');
    }
    return nfceProposalFromAnalysis(analysis, qrUrl: qrUrl);
  }

  /// Resposta do nfce-read vira proposta de nota já paga, com os itens.
  static CaptureProposal nfceProposalFromAnalysis(Map<String, dynamic> analysis, {required String qrUrl}) {
    final rawItems = analysis['items'] as List<dynamic>? ?? const [];
    final items = <InvoiceItemDraft>[];
    for (var i = 0; i < rawItems.length; i++) {
      final item = rawItems[i];
      if (item is! Map) continue;
      final amount = (item['amount_cents'] as num?)?.toInt() ?? 0;
      if (amount <= 0) continue;
      final rawQuantity = (item['quantity'] as num?)?.toDouble() ?? 1;
      // Peso (0,532 kg) não cabe em quantidade inteira: vira 1 pelo valor total
      final wholeUnits = rawQuantity >= 1 && rawQuantity == rawQuantity.roundToDouble();
      final quantity = wholeUnits ? rawQuantity.toInt() : 1;
      final unit = (item['unit_cents'] as num?)?.toInt() ?? 0;
      items.add(InvoiceItemDraft(
        id: 'item_$i',
        name: (item['title'] as String?)?.trim().isNotEmpty == true ? (item['title'] as String).trim() : 'Item ${i + 1}',
        quantity: quantity,
        unitPrice: Money(wholeUnits && unit > 0 ? unit : amount),
        totalPrice: Money(amount),
        isPersonal: false,
      ));
    }

    final total = (analysis['total_cents'] as num?)?.toInt() ?? 0;
    final itemsSum = items.fold<int>(0, (sum, i) => sum + i.totalPrice.cents);
    final merchant = (analysis['merchant_name'] as String?)?.trim();
    final issued = DateTime.tryParse(analysis['issue_date'] as String? ?? '');

    return CaptureProposal(
      id: 'prop_nfce_${DateTime.now().millisecondsSinceEpoch}',
      documentType: DocumentType.nfce,
      title: merchant != null && merchant.isNotEmpty ? merchant : 'Nota Fiscal (NFC-e)',
      totalAmount: Money(total > 0 ? total : itemsSum),
      date: issued != null ? DateTime(issued.year, issued.month, issued.day, 12) : DateTime.now(),
      merchantOrBeneficiary: merchant,
      rawCode: qrUrl,
      items: items,
      capturedAt: DateTime.now(),
    );
  }

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
          final rawBarcode = analysis['barcode'] as String? ?? codeProposal?.rawCode;
          // Código conferido vira a linha digitável formatada, pronta para copiar
          String? barcode = rawBarcode;
          if (rawBarcode != null) {
            try {
              barcode = BoletoCodeReader.read(rawBarcode).digitableLine;
            } catch (_) {}
          }
          final isItemized = analysis['is_itemized'] as bool? ?? false;

          DateTime date = DateTime.now();
          DateTime? dueDate;
          final dueDateStr = analysis['due_date'] as String?;
          if (dueDateStr != null && dueDateStr.isNotEmpty) {
            dueDate = DateTime.tryParse(dueDateStr);
            if (dueDate != null) date = dueDate;
          } else if (codeProposal != null) {
            date = codeProposal.date;
            dueDate = codeProposal.dueDate;
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
            dueDate: dueDate,
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

/// Falha ao consultar a NFC-e na Sefaz, com a mensagem para o usuário.
class NfceLookupError implements Exception {
  final String message;
  const NfceLookupError(this.message);

  @override
  String toString() => message;
}
