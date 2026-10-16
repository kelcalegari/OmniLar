import '../../../../core/domain/value_objects/money.dart';
import '../entities/capture_proposal.dart';

class BoletoParser {
  BoletoParser._();

  /// Limpa caracteres não numéricos
  static String sanitize(String input) {
    return input.replaceAll(RegExp(r'[^0-9]'), '');
  }

  /// Valida se a linha digitável tem 47 ou 48 dígitos
  static bool isValidLength(String digits) {
    final clean = sanitize(digits);
    return clean.length == 47 || clean.length == 48;
  }

  /// Busca um padrão de linha digitável de boleto dentro de um texto bruto ou documento
  static String? findBoletoLineInText(String text) {
    // 1. Linha digitável com pontos e espaços (ex: 74891.12628 02607.826068 22628.201067 6 15950000048921)
    final formattedRegex = RegExp(
      r'(\d{5}\.\d{5}\s+\d{5}\.\d{6}\s+\d{5}\.\d{6}\s+\d\s+\d{14})',
    );
    final match = formattedRegex.firstMatch(text);
    if (match != null) return match.group(1);

    // 2. Linha digitável contínua de 47 dígitos
    final continuousRegex = RegExp(r'\b(\d{47})\b');
    final matchCont = continuousRegex.firstMatch(text);
    if (matchCont != null) return matchCont.group(1);

    return null;
  }

  /// Distribui centavos proporcionalmente entre os itens (Algoritmo do Maior Resto do Omni Lar)
  static List<int> distributeCentsProportionally(int newTotalCents, List<int> originalWeights) {
    final sum = originalWeights.fold<int>(0, (a, b) => a + b);
    if (sum == 0 || originalWeights.isEmpty) {
      if (originalWeights.isEmpty) return [];
      final part = newTotalCents ~/ originalWeights.length;
      var rest = newTotalCents - (part * originalWeights.length);
      return List.generate(originalWeights.length, (i) => part + (rest-- > 0 ? 1 : 0));
    }

    final base = [for (final w in originalWeights) (newTotalCents * w) ~/ sum];
    var rest = newTotalCents - base.fold<int>(0, (a, b) => a + b);

    final order = List.generate(originalWeights.length, (i) => i)
      ..sort((a, b) {
        final ra = (newTotalCents * originalWeights[a]) % sum;
        final rb = (newTotalCents * originalWeights[b]) % sum;
        return rb != ra ? rb.compareTo(ra) : a.compareTo(b);
      });

    for (final i in order) {
      if (rest <= 0) break;
      base[i]++;
      rest--;
    }
    return base;
  }

  /// Calcula a data de vencimento a partir do fator de vencimento FEBRABAN/BACEN.
  /// Trata o rollover de 22/02/2025, onde o fator de 4 dígitos reiniciou em 1000.
  static DateTime calculateDueDateFromFactor(int factor, {DateTime? referenceDate}) {
    final now = referenceDate ?? DateTime.now();
    if (factor <= 0) {
      return now.add(const Duration(days: 5));
    }

    final rolloverDate = DateTime(2025, 2, 22);
    final dateCycle1 = DateTime(1997, 10, 7).add(Duration(days: factor));

    if (now.isAfter(rolloverDate) || now.isAtSameMomentAs(rolloverDate)) {
      if (dateCycle1.isBefore(rolloverDate)) {
        // Ciclo 2 FEBRABAN: fator 1000 corresponde a 22/02/2025
        return DateTime(2025, 2, 22).add(Duration(days: factor - 1000));
      }
    }

    return dateCycle1;
  }

  /// Extrai valor e vencimento de uma linha digitável de boleto bancário (47 dígitos)
  /// Exemplo de boleto bancário:
  /// Campo 5 (últimos 14 dígitos): 4 dígitos fator de vencimento + 10 dígitos valor em centavos
  static CaptureProposal? parseBoletoBancario({
    required String rawLine,
    String? title,
  }) {
    final clean = sanitize(rawLine);
    if (clean.length != 47) return null;

    try {
      // Fator de vencimento (posições 33 a 37 - 4 dígitos)
      final factorStr = clean.substring(33, 37);
      final factor = int.tryParse(factorStr) ?? 0;

      // Data base do Banco Central / FEBRABAN com tratamento do rollover de 2025
      final dueDate = calculateDueDateFromFactor(factor);

      // Valor (últimos 10 dígitos da linha digitável em centavos)
      final valueStr = clean.substring(37, 47);
      final cents = int.tryParse(valueStr) ?? 0;
      final amount = Money(cents);

      return CaptureProposal(
        id: 'prop_${DateTime.now().millisecondsSinceEpoch}',
        documentType: DocumentType.boleto,
        title: title ?? 'Boleto Bancário',
        totalAmount: amount,
        date: dueDate,
        dueDate: dueDate,
        rawCode: rawLine,
        capturedAt: DateTime.now(),
      );
    } catch (_) {
      return null;
    }
  }

  /// Parser para URLs de QR Code de NFC-e (SEFAZ). O QR não traz loja nem
  /// itens; só o QR de contingência (offline) traz o valor total. O resto o
  /// usuário completa na revisão.
  static CaptureProposal parseNfceQrCodeUrl(String url) {
    return CaptureProposal(
      id: 'prop_nfce_${DateTime.now().millisecondsSinceEpoch}',
      documentType: DocumentType.nfce,
      title: 'Nota Fiscal (NFC-e)',
      totalAmount: Money(nfceTotalCentsFromUrl(url) ?? 0),
      date: DateTime.now(),
      rawCode: url,
      capturedAt: DateTime.now(),
    );
  }

  /// Valor total do QR de NFC-e emitida em contingência
  /// (p=chave|versão|ambiente|dia|valor|...). O QR online não traz valor.
  static int? nfceTotalCentsFromUrl(String url) {
    final p = Uri.tryParse(url)?.queryParameters['p'];
    if (p == null) return null;
    final parts = p.split('|');
    if (parts.length < 8) return null;
    final value = double.tryParse(parts[4].replaceAll(',', '.'));
    if (value == null || value <= 0) return null;
    return (value * 100).round();
  }

  /// Cupom de mercado fictício, só para o botão de simulação do modo demo.
  static CaptureProposal demoNfceProposal() {
    return CaptureProposal(
      id: 'prop_nfce_${DateTime.now().millisecondsSinceEpoch}',
      documentType: DocumentType.nfce,
      title: 'Nota Fiscal (NFC-e)',
      totalAmount: const Money(14250),
      date: DateTime.now(),
      merchantOrBeneficiary: 'Supermercado Pão de Açúcar',
      rawCode: 'https://sefaz.sp.gov.br/nfce/qrcode?p=3526101234567890',
      capturedAt: DateTime.now(),
      items: [
        const InvoiceItemDraft(
          id: 'item_1',
          name: 'Arroz Integral 1kg',
          quantity: 2,
          unitPrice: Money(850),
          totalPrice: Money(1700),
          isPersonal: false,
        ),
        const InvoiceItemDraft(
          id: 'item_2',
          name: 'Azeite Extra Virgem 500ml',
          quantity: 1,
          unitPrice: Money(3890),
          totalPrice: Money(3890),
          isPersonal: false,
        ),
        const InvoiceItemDraft(
          id: 'item_3',
          name: 'Shampoo Especial Anticaspa',
          quantity: 1,
          unitPrice: Money(4200),
          totalPrice: Money(4200),
          isPersonal: true,
          assignedMemberId: 'member_carlos',
        ),
        const InvoiceItemDraft(
          id: 'item_4',
          name: 'Café Especial Torrado 250g',
          quantity: 1,
          unitPrice: Money(4460),
          totalPrice: Money(4460),
          isPersonal: false,
        ),
      ],
    );
  }
}
