import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/features/reconciliation/domain/entities/imported_statement_line.dart';
import 'package:omni_lar/features/reconciliation/domain/services/statement_parser.dart';

void main() {
  group('Importação & Conciliação (Fase 6 - RN01, RN07, RN09)', () {
    test('RN09: Rachar a Fatura divide total entre Casa, Pessoal e Dívida P2P com consistência exata', () {
      final lines = [
        ImportedStatementLine(
          id: '1',
          date: DateTime(2026, 10, 5),
          description: 'Pão de Açúcar Mercado',
          amount: const Money(48560), // R$ 485,60 -> Casa
          destination: LineDestination.house,
        ),
        ImportedStatementLine(
          id: '2',
          date: DateTime(2026, 10, 7),
          description: 'Camisa Zara (Marina)',
          amount: const Money(18000), // R$ 180,00 -> P2P Marina
          destination: LineDestination.splitP2P,
          assignedMemberId: 'member_marina',
        ),
        ImportedStatementLine(
          id: '3',
          date: DateTime(2026, 10, 8),
          description: 'Steam Game (Carlos)',
          amount: const Money(15000), // R$ 150,00 -> Pessoal Carlos
          destination: LineDestination.cardOwnerPersonal,
        ),
      ];

      final split = StatementParser.calculateSplit(lines);

      // Total = 485,60 + 180,00 + 150,00 = 815,60 (81560 cents)
      expect(split.totalAmount.cents, 81560);
      expect(split.houseAmount.cents, 48560);
      expect(split.personalOwnerAmount.cents, 15000);
      expect(split.p2pDebtsByMember['member_marina']?.cents, 18000);

      // Soma de todas as parcelas deve igualar exatamente o total da fatura
      final calculatedSum = split.houseAmount.cents +
          split.personalOwnerAmount.cents +
          split.p2pDebtsByMember.values.fold<int>(0, (acc, m) => acc + m.cents);
      expect(calculatedSum, split.totalAmount.cents);
    });

    test('CSV Parser extrai linhas de fatura com detecção preliminar de destino', () {
      const csv = '''
Data,Descrição,Valor
2026-10-01,Supermercado Pão de Açúcar,350.00
2026-10-02,Loja Zara Vestuário,120.00
2026-10-03,Steam Jogos Online,80.00
''';

      final lines = StatementParser.parseCsv(csv);
      expect(lines.length, 3);
      expect(lines[0].amount.cents, 35000);
      expect(lines[0].destination, LineDestination.house);
      expect(lines[1].destination, LineDestination.splitP2P);
      expect(lines[2].destination, LineDestination.cardOwnerPersonal);
    });
  });
}
