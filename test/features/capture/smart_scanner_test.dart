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

    test('Parser de URL de QR Code NFC-e retorna itens da nota', () {
      const nfcUrl = 'https://sefaz.sp.gov.br/nfce/qrcode?p=3526101234567890';
      final proposal = BoletoParser.parseNfceQrCodeUrl(nfcUrl);

      expect(proposal.documentType, equals(DocumentType.nfce));
      expect(proposal.items.isNotEmpty, isTrue);
      expect(proposal.houseAmount.cents, greaterThan(0));
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
