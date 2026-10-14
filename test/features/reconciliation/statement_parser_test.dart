import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/features/reconciliation/domain/services/statement_parser.dart';
import 'package:omni_lar/features/reconciliation/domain/entities/imported_statement_line.dart';

void main() {
  group('StatementParser - OFX e CSV Suporte Bancário', () {
    test('parseOfx extrai transações corretamente a partir de arquivo padrão bancário OFX', () {
      const sampleOfx = '''
OFXHEADER:100
DATA:OFXSGML
<OFX>
  <BANKMSGSRSV1>
    <STMTTRNRS>
      <STMTRS>
        <BANKTRANLIST>
          <STMTTRN>
            <TRNTYPE>DEBIT</TRNTYPE>
            <DTPOSTED>20261005120000</DTPOSTED>
            <TRNAMT>-320.50</TRNAMT>
            <MEMO>Supermercado Pao de Acucar</MEMO>
          </STMTTRN>
          <STMTTRN>
            <TRNTYPE>DEBIT</TRNTYPE>
            <DTPOSTED>20261008120000</DTPOSTED>
            <TRNAMT>-180.00</TRNAMT>
            <MEMO>Zara Shopping</MEMO>
          </STMTTRN>
          <STMTTRN>
            <TRNTYPE>DEBIT</TRNTYPE>
            <DTPOSTED>20261009120000</DTPOSTED>
            <TRNAMT>-150.00</TRNAMT>
            <NAME>Steam Games</NAME>
          </STMTTRN>
        </BANKTRANLIST>
      </STMTRS>
    </STMTTRNRS>
  </BANKMSGSRSV1>
</OFX>
''';

      final lines = StatementParser.parseOfx(sampleOfx);

      expect(lines.length, equals(3));

      // 1. Mercado -> Casa
      expect(lines[0].description, equals('Supermercado Pao de Acucar'));
      expect(lines[0].amount.cents, equals(32050));
      expect(lines[0].destination, equals(LineDestination.house));
      expect(lines[0].date.year, equals(2026));
      expect(lines[0].date.month, equals(10));
      expect(lines[0].date.day, equals(5));

      // 2 e 3. Toda compra começa na Casa: quem decide o destino é o usuário
      expect(lines[1].description, equals('Zara Shopping'));
      expect(lines[1].amount.cents, equals(18000));
      expect(lines[1].destination, equals(LineDestination.house));
      expect(lines[1].assignedMemberId, isNull);

      expect(lines[2].description, equals('Steam Games'));
      expect(lines[2].amount.cents, equals(15000));
      expect(lines[2].destination, equals(LineDestination.house));
    });

    test('parseFile detecta automaticamente OFX vs CSV', () {
      const sampleCsv = '''
Data,Descricao,Valor
2026-10-01,Enel Energia,210.00
2026-10-02,Farm Vestido,350.00
''';

      final csvLines = StatementParser.parseFile(sampleCsv, filename: 'fatura.csv');
      expect(csvLines.length, equals(2));
      expect(csvLines[0].description, equals('Enel Energia'));
      expect(csvLines[0].destination, equals(LineDestination.house));
      expect(csvLines[1].destination, equals(LineDestination.house));
    });

    test('calculateSplit apura os saldos corretamente por destino e membro devedor (RN09)', () {
      const sampleCsv = '''
2026-10-01,Mercado Casa,500.00
2026-10-02,Roupa Zara,200.00
2026-10-03,Steam Pessoal,100.00
''';

      final parsed = StatementParser.parseCsv(sampleCsv);
      final lines = [
        parsed[0],
        parsed[1].copyWith(destination: LineDestination.splitP2P, assignedMemberId: 'member_marina'),
        parsed[2].copyWith(destination: LineDestination.cardOwnerPersonal),
      ];
      final split = StatementParser.calculateSplit(lines);

      expect(split.totalAmount.cents, equals(80000)); // R$ 800,00
      expect(split.houseAmount.cents, equals(50000)); // R$ 500,00
      expect(split.personalOwnerAmount.cents, equals(10000)); // R$ 100,00
      expect(split.p2pDebtsByMember['member_marina']?.cents, equals(20000)); // R$ 200,00
    });
  });
}
