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

      // Data base do Banco Central: 07/10/1997
      DateTime dueDate;
      if (factor > 0) {
        dueDate = DateTime(1997, 10, 7).add(Duration(days: factor));
      } else {
        dueDate = DateTime.now().add(const Duration(days: 5));
      }

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
        rawCode: rawLine,
        capturedAt: DateTime.now(),
      );
    } catch (_) {
      return null;
    }
  }

  /// Parser para URLs de QR Code de NFC-e (SEFAZ)
  static CaptureProposal parseNfceQrCodeUrl(String url) {
    return CaptureProposal(
      id: 'prop_nfce_${DateTime.now().millisecondsSinceEpoch}',
      documentType: DocumentType.nfce,
      title: 'Nota Fiscal (NFC-e)',
      totalAmount: const Money(14250), // Mock inicial simulado de cupom de mercado
      date: DateTime.now(),
      merchantOrBeneficiary: 'Supermercado Pão de Açúcar',
      rawCode: url,
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
