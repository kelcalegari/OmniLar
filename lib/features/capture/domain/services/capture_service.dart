import 'dart:convert';
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart' show FunctionException;
import '../../../../core/network/supabase_config.dart';
import '../../../../core/domain/value_objects/money.dart';
import '../../../../core/services/ai_config_service.dart';
import '../entities/capture_proposal.dart';
import 'boleto_code.dart';
import 'boleto_parser.dart';
import '../../../../core/ai/ai_consent.dart';

class CaptureService {
  final AiConfigService aiConfigService;
  final String? Function()? getCurrentHouseId;

  CaptureService({required this.aiConfigService, this.getCurrentHouseId});

  /// Estados cuja Sefaz pede verificação de pessoa antes de mostrar a nota:
  /// nem adianta consultar, a nota vai direto para a foto.
  static const _statesWithoutLookup = {'42': 'Santa Catarina'};

  /// Código do estado (cUF) da nota, os 2 primeiros dígitos da chave de acesso.
  static String? nfceStateCode(String qrUrl) {
    final params = Uri.tryParse(qrUrl.trim())?.queryParameters ?? const {};
    final key = (params['p'] ?? params['chNFe'] ?? '').split('|').first.replaceAll(RegExp(r'\D'), '');
    return key.length == 44 ? key.substring(0, 2) : null;
  }

  /// Nome do estado da nota quando a Sefaz dele não libera a consulta (SC):
  /// essa nota vai direto para a foto.
  static String? photoOnlyState(String qrUrl) => _statesWithoutLookup[nfceStateCode(qrUrl)];

  /// Consulta a NFC-e na Sefaz pelo link do QR (Edge Function nfce-read).
  /// Lança [NfceLookupError] com o motivo e uma mensagem simples para o usuário.
  Future<CaptureProposal> lookupNfce(String qrUrl) async {
    final host = Uri.tryParse(qrUrl.trim())?.host.toLowerCase() ?? '';
    if (!host.endsWith('.gov.br')) throw NfceLookupError.of(NfceLookupReason.invalidQr);
    final state = photoOnlyState(qrUrl);
    if (state != null) {
      throw NfceLookupError(NfceLookupReason.stateWithoutLookup, 'Em $state a Sefaz não libera a consulta automática da nota.');
    }

    final client = SupabaseConfig.client;
    if (client == null) throw NfceLookupError.of(NfceLookupReason.unavailable);
    // Layout desconhecido da Sefaz vai para a IA: precisa da permissão
    if (!await AiConsent.request()) {
      throw NfceLookupError.fromServer('unavailable', 'Para consultar a nota, permita a leitura por IA.');
    }

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
      throw NfceLookupError.fromServer(
        details is Map ? details['reason'] as String? : null,
        details is Map ? details['error'] as String? : null,
      );
    } catch (_) {
      throw NfceLookupError.of(NfceLookupReason.unavailable);
    }

    final analysis = data is Map<String, dynamic> ? data['analysis'] : null;
    if (analysis is! Map<String, dynamic>) throw NfceLookupError.of(NfceLookupReason.unavailable);
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

  /// Itens (título, centavos) prontos para gravar: o banco só aceita valor
  /// maior que zero. Descontos (valores negativos) são abatidos
  /// proporcionalmente dos itens positivos, mantendo a soma; itens zerados
  /// saem. Se o desconto engolir os itens, volta vazio (sem detalhamento).
  static List<(String, int)> absorbDiscounts(List<(String, int)> lines) {
    final positives = lines.where((l) => l.$2 > 0).toList();
    final discount = lines.where((l) => l.$2 < 0).fold<int>(0, (sum, l) => sum - l.$2);
    if (discount == 0) return positives;

    final positiveSum = positives.fold<int>(0, (sum, l) => sum + l.$2);
    if (positiveSum - discount < positives.length) return const [];

    final shares = [for (final l in positives) l.$2 * discount / positiveSum];
    final cuts = [for (final s in shares) s.floor()];
    var remainder = discount - cuts.fold<int>(0, (a, b) => a + b);
    final order = List<int>.generate(positives.length, (i) => i)
      ..sort((a, b) => (shares[b] - cuts[b]).compareTo(shares[a] - cuts[a]));
    for (var k = 0; remainder > 0; k = (k + 1) % order.length) {
      final i = order[k];
      if (positives[i].$2 - cuts[i] > 1) {
        cuts[i]++;
        remainder--;
      }
    }
    return [for (var i = 0; i < positives.length; i++) (positives[i].$1, positives[i].$2 - cuts[i])];
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
      if (client != null && await AiConsent.request()) {
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

          // Desconto do boleto (linha negativa) é abatido dos demais itens:
          // o banco só aceita itens com valor maior que zero
          final lines = absorbDiscounts([
            for (final (i, raw) in rawItems.indexed)
              if (raw is Map)
                (
                  (raw['title'] as String?) ?? 'Item ${i + 1}',
                  (raw['amount_cents'] as num?)?.round() ?? 0,
                ),
          ]);

          for (int i = 0; i < lines.length; i++) {
            final (itemTitle, itemAmountCents) = lines[i];

            items.add(
              InvoiceItemDraft(
                id: 'item_$i',
                name: itemTitle,
                quantity: 1,
                unitPrice: Money(itemAmountCents),
                totalPrice: Money(itemAmountCents),
                // Todo item entra como da casa (fundo de reserva inclusive);
                // quem quiser marca um como pessoal na revisão
                isPersonal: false,
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

enum NfceLookupReason { unavailable, captcha, stateWithoutLookup, notFound, invalidQr, quota, other }

/// Falha ao consultar a NFC-e na Sefaz: o motivo e o que aconteceu, em
/// palavras simples (o que fazer em seguida fica com a tela).
class NfceLookupError implements Exception {
  final NfceLookupReason reason;
  final String message;
  const NfceLookupError(this.reason, this.message);

  static const _messages = {
    NfceLookupReason.unavailable: 'A Sefaz não respondeu agora.',
    NfceLookupReason.captcha: 'A Sefaz deste estado não libera a consulta automática da nota.',
    NfceLookupReason.notFound: 'A nota ainda não aparece na Sefaz; pode levar alguns minutos depois da compra.',
    NfceLookupReason.invalidQr: 'Esse QR não parece ser de uma nota fiscal.',
  };

  factory NfceLookupError.of(NfceLookupReason reason) =>
      NfceLookupError(reason, _messages[reason] ?? _messages[NfceLookupReason.unavailable]!);

  /// Resposta de erro do nfce-read. Motivo conhecido usa a mensagem do app;
  /// cota e sessão usam a do servidor, que já diz o que fazer.
  factory NfceLookupError.fromServer(String? reason, String? serverMessage) {
    final known = switch (reason) {
      'unavailable' => NfceLookupReason.unavailable,
      'captcha' => NfceLookupReason.captcha,
      'not_found' => NfceLookupReason.notFound,
      'invalid_qr' => NfceLookupReason.invalidQr,
      'quota' => NfceLookupReason.quota,
      _ => null,
    };
    if (known != null && _messages.containsKey(known)) return NfceLookupError.of(known);
    final message = serverMessage?.trim();
    return NfceLookupError(
      known ?? NfceLookupReason.other,
      message != null && message.isNotEmpty ? message : _messages[NfceLookupReason.unavailable]!,
    );
  }

  @override
  String toString() => message;
}
