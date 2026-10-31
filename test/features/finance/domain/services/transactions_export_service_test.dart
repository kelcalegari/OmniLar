import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/features/finance/domain/entities/house_transaction.dart';
import 'package:omni_lar/features/finance/domain/services/transaction_aggregator.dart';
import 'package:omni_lar/features/finance/domain/services/transactions_export_service.dart';

void main() {
  group('TransactionsExportService', () {
    const exportService = TransactionsExportService();

    final testTransactions = [
      HouseTransaction(
        id: 'exp_1',
        title: 'Almoço Restaurante',
        amount: const Money(4550), // R$ 45,50
        type: TransactionType.expense,
        origin: TransactionOrigin.houseExpense,
        date: DateTime(2026, 10, 15),
        categoryName: 'Alimentação',
        memberName: 'Kelvyn',
        paymentMethodName: 'Cartão C6',
      ),
      HouseTransaction(
        id: 'inf_1',
        title: 'Reembolso Internet',
        amount: const Money(2000), // R$ 20,00
        type: TransactionType.inflow,
        origin: TransactionOrigin.houseInflow,
        date: DateTime(2026, 10, 16),
        memberName: 'Cris',
      ),
    ];

    final testMetrics = TransactionAggregator.calculateMetrics(testTransactions);

    test('buildCsv generates valid spreadsheet content with BOM, headers, items and totals', () {
      final csv = exportService.buildCsv(
        houseName: 'República Modelo',
        periodDescription: 'Ciclo Outubro/2026',
        transactions: testTransactions,
        metrics: testMetrics,
      );

      // Verify UTF-8 BOM
      expect(csv.startsWith('\uFEFF'), isTrue);

      // Verify Headers & House name
      expect(csv.contains('EXTRATO DE TRANSAÇÕES'), isTrue);
      expect(csv.contains('República Modelo'), isTrue);
      expect(csv.contains('Ciclo Outubro/2026'), isTrue);
      expect(csv.contains('Data;Tipo;Título;Categoria;Valor (R\$);Quem Pagou/Aportou;Forma de Pagamento;Status;Descrição;Observações'), isTrue);

      // Verify Transaction Lines
      expect(csv.contains('Almoço Restaurante'), isTrue);
      expect(csv.contains('Alimentação'), isTrue);
      expect(csv.contains('Reembolso Internet'), isTrue);

      // Verify Totals
      expect(csv.contains('Total de Entradas;R\$'), isTrue);
      expect(csv.contains('Total de Saídas;R\$'), isTrue);
      expect(csv.contains('Saldo Líquido;R\$'), isTrue);
    });

    test('buildPdf generates non-empty PDF document bytes', () async {
      final pdfBytes = await exportService.buildPdf(
        houseName: 'República Modelo',
        periodDescription: 'Ciclo Outubro/2026',
        transactions: testTransactions,
        metrics: testMetrics,
      );

      expect(pdfBytes, isNotEmpty);
      // PDF documents start with %PDF
      final header = String.fromCharCodes(pdfBytes.sublist(0, 4));
      expect(header, '%PDF');
    });
  });
}
