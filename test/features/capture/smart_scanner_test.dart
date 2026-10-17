import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/core/services/ai_config_service.dart';
import 'package:omni_lar/features/capture/domain/entities/capture_proposal.dart';
import 'package:omni_lar/features/capture/domain/services/boleto_parser.dart';
import 'package:omni_lar/features/capture/domain/services/capture_service.dart';

void main() {
  group('BoletoParser Tests', () {
    test('Valida tamanho da linha digitável de boleto bancário (47 dígitos)', () {
      const validLine = '34191.79001 01043.510047 91020.150008 4 98760000021540';
      expect(BoletoParser.isValidLength(validLine), isTrue);

      const invalidLine = '123456';
      expect(BoletoParser.isValidLength(invalidLine), isFalse);
    });

    test('Extrai valor e vencimento de boleto bancário válido', () {
      const validLine = '34191790010104351004791020150008498760000021540';
      final proposal = BoletoParser.parseBoletoBancario(rawLine: validLine);

      expect(proposal, isNotNull);
      expect(proposal!.documentType, equals(DocumentType.boleto));
      expect(proposal.totalAmount, equals(const Money(21540))); // R$ 215,40
    });

    test('QR de NFC-e online não inventa loja, valor nem itens', () {
      const nfcUrl = 'https://sefaz.sp.gov.br/nfce/qrcode?p=35261012345678901234567890123456789012345678|2|1|1|ABCDEF';
      final proposal = BoletoParser.parseNfceQrCodeUrl(nfcUrl);

      expect(proposal.documentType, equals(DocumentType.nfce));
      expect(proposal.items, isEmpty);
      expect(proposal.merchantOrBeneficiary, isNull);
      expect(proposal.totalAmount.cents, 0);
    });

    test('QR de NFC-e em contingência traz o valor total', () {
      const nfcUrl = 'https://sefaz.sp.gov.br/nfce/qrcode?p=35261012345678901234567890123456789012345678|2|1|16|142.50|6a6b|1|ABCDEF';
      final proposal = BoletoParser.parseNfceQrCodeUrl(nfcUrl);

      expect(proposal.totalAmount.cents, 14250);
      expect(proposal.items, isEmpty);
    });
  });

  group('CaptureProposal Domain Tests', () {
    test('Calcula houseAmount deduzindo itens pessoais corretamente (RN09)', () {
      final proposal = CaptureProposal(
        id: 'prop_test',
        documentType: DocumentType.nfce,
        title: 'Supermercado',
        totalAmount: const Money(10000), // R$ 100,00
        date: DateTime.now(),
        capturedAt: DateTime.now(),
        items: const [
          InvoiceItemDraft(
            id: '1',
            name: 'Leite',
            unitPrice: Money(4000),
            totalPrice: Money(4000),
            isPersonal: false,
          ),
          InvoiceItemDraft(
            id: '2',
            name: 'Vinho Pessoal',
            unitPrice: Money(6000),
            totalPrice: Money(6000),
            isPersonal: true,
          ),
        ],
      );

      expect(proposal.personalItemsAmount, equals(const Money(6000)));
      expect(proposal.houseAmount, equals(const Money(4000)));
    });
  });

  group('CaptureService Tests', () {
    test('Gera proposta em fallback gracioso quando offline ou sem Edge Function', () async {
      final service = CaptureService(aiConfigService: AiConfigService(null));
      final fakeBytes = Uint8List.fromList([1, 2, 3]);

      final proposal = await service.processDocumentFile(
        bytes: fakeBytes,
        fileName: 'conta_energia_outubro.pdf',
        mimeType: 'application/pdf',
      );

      expect(proposal.documentType, equals(DocumentType.boleto));
      expect(proposal.title, contains('conta_energia_outubro'));
    });

    test('Nota consultada na Sefaz vira proposta com loja, data, total e itens', () {
      const url = 'https://www.nfce.fazenda.sp.gov.br/qrcode?p=3526|2|1|1|ABC';
      final proposal = CaptureService.nfceProposalFromAnalysis({
        'total_cents': 2390,
        'issue_date': '2026-10-15',
        'merchant_name': 'MERCADO BOM PRECO',
        'items': [
          {'title': 'ARROZ 1KG', 'quantity': 2, 'unit_cents': 850, 'amount_cents': 1700},
          {'title': 'BANANA KG', 'quantity': 0.532, 'unit_cents': 599, 'amount_cents': 319},
          {'title': 'BRINDE', 'quantity': 1, 'unit_cents': 0, 'amount_cents': 0},
          {'title': 'PAO', 'quantity': 1, 'amount_cents': 371},
        ],
      }, qrUrl: url);

      expect(proposal.documentType, DocumentType.nfce);
      expect(proposal.title, 'MERCADO BOM PRECO');
      expect(proposal.merchantOrBeneficiary, 'MERCADO BOM PRECO');
      expect(proposal.totalAmount.cents, 2390);
      expect(proposal.date, DateTime(2026, 10, 15, 12));
      expect(proposal.rawCode, url);
      expect(proposal.items.map((i) => i.name), ['ARROZ 1KG', 'BANANA KG', 'PAO']);
      expect(proposal.items[0].quantity, 2);
      expect(proposal.items[0].unitPrice.cents, 850);
      // Peso vira 1 unidade pelo valor do item
      expect(proposal.items[1].quantity, 1);
      expect(proposal.items[1].unitPrice.cents, 319);
      expect(proposal.items.every((i) => !i.isPersonal), isTrue);
    });

    test('Nota da Sefaz sem total usa a soma dos itens', () {
      final proposal = CaptureService.nfceProposalFromAnalysis({
        'items': [
          {'title': 'A', 'quantity': 1, 'unit_cents': 500, 'amount_cents': 500},
          {'title': 'B', 'quantity': 1, 'unit_cents': 250, 'amount_cents': 250},
        ],
      }, qrUrl: 'https://x.gov.br');

      expect(proposal.totalAmount.cents, 750);
      expect(proposal.title, 'Nota Fiscal (NFC-e)');
    });

    test('Consulta da nota sem servidor avisa em vez de inventar dados', () async {
      final service = CaptureService(aiConfigService: AiConfigService(null));
      expect(() => service.lookupNfce('https://x.gov.br'), throwsA(isA<NfceLookupError>()));
    });
  });

  group('Proportional Discount Distribution Tests', () {
    test('Distribui desconto proporcionalmente nos itens de condomínio mantendo soma exata ao centavo', () {
      // Valores originais do boleto do The Empire Residence:
      // Taxa: 425,55 | Fundo: 42,56 | Fixa: 30,24 | Agua: 13,12 | Lazer: 62,85 -> Total: 574,32
      final originalItemsCents = [42555, 4256, 3024, 1312, 6285];
      const discountedTotalCents = 48921; // R$ 489,21

      final distributed = BoletoParser.distributeCentsProportionally(
        discountedTotalCents,
        originalItemsCents,
      );

      // 1. A soma dos itens com desconto DEVE bater exatamente com o total pago
      final sumDistributed = distributed.fold<int>(0, (a, b) => a + b);
      expect(sumDistributed, equals(discountedTotalCents));

      // 2. Cada item deve ter recebido o desconto pro-rata (~14,82%)
      expect(distributed[0], equals(36249)); // R$ 362,49 (era 425,55)
      expect(distributed[1], equals(3625));  // R$ 36,25 (era 42,56)
      expect(distributed[2], equals(2576));  // R$ 25,76 (era 30,24)
      expect(distributed[3], equals(1117));  // R$ 11,17 (era 13,12)
      expect(distributed[4], equals(5354));  // R$ 53,54 (era 62,85)
    });
  });
}
