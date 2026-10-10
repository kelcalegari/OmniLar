import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/features/capture/domain/entities/capture_proposal.dart';
import 'package:omni_lar/features/capture/domain/services/boleto_parser.dart';

void main() {
  group('Smart Capture & Scanner Engine (RN01, RN03, RN09, RN10)', () {
    test('RN10: BoletoParser extrai valor e vencimento corretamente da linha digitavel', () {
      // Linha digitável com fator de vencimento 9876 e valor 21540 (R$ 215,40)
      const line = '34191.79001 01043.510047 91020.150008 4 98760000021540';
      final proposal = BoletoParser.parseBoletoBancario(rawLine: line);

      expect(proposal, isNotNull);
      expect(proposal!.documentType, DocumentType.boleto);
      expect(proposal.totalAmount.cents, 21540); // R$ 215,40
      expect(proposal.totalAmount, const Money(21540));
      expect(proposal.date.isAfter(DateTime(2020)), isTrue);
    });

    test('RN03 e RN09: Parse de NFC-e gera itens e calcula divisão entre Casa e Pessoal', () {
      final proposal = BoletoParser.parseNfceQrCodeUrl('https://sefaz.sp.gov.br/nfce/qrcode?p=123');

      expect(proposal.documentType, DocumentType.nfce);
      expect(proposal.items.length, 4);

      // Total geral: R$ 142,50 (14250 centavos)
      expect(proposal.totalAmount.cents, 14250);

      // Item 3 é shampoo pessoal de R$ 42,00 (4200 centavos)
      expect(proposal.personalItemsAmount.cents, 4200);

      // O restante pertence à Casa: 14250 - 4200 = 10050 (R$ 100,50)
      expect(proposal.houseAmount.cents, 10050);
      expect(proposal.houseAmount + proposal.personalItemsAmount, proposal.totalAmount);
    });
  });
}
