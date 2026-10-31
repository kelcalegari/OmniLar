import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../../../core/domain/value_objects/money.dart';
import '../entities/house_transaction.dart';
import 'transaction_aggregator.dart';

class TransactionsExportService {
  const TransactionsExportService();

  static final _dateFormat = DateFormat('dd/MM/yyyy');

  static String _formatDate(DateTime d) => _dateFormat.format(d);

  static String _formatMoney(Money m) =>
      (m.cents / 100.0).toStringAsFixed(2).replaceAll('.', ',');

  static String _escapeText(String value) => '"${value.replaceAll('"', '""')}"';

  /// Gera conteúdo CSV formatado para Excel/Planilhas (com ponto-e-vírgula e UTF-8 BOM).
  String buildCsv({
    required String houseName,
    required String periodDescription,
    required List<HouseTransaction> transactions,
    required TransactionAggregatorMetrics metrics,
  }) {
    final b = StringBuffer();
    b.write('\uFEFF'); // UTF-8 BOM
    b.writeln('EXTRATO DE TRANSAÇÕES — OMNI LAR');
    b.writeln('Residência;${_escapeText(houseName)}');
    b.writeln('Período;${_escapeText(periodDescription)}');
    b.writeln('Total de Entradas;R\$ ${_formatMoney(metrics.totalInflows)}');
    b.writeln('Total de Saídas;R\$ ${_formatMoney(metrics.totalExpenses)}');
    b.writeln('Saldo Líquido;R\$ ${_formatMoney(metrics.netBalance)}');
    b.writeln('');

    b.writeln('Data;Tipo;Título;Categoria;Valor (R\$);Quem Pagou/Aportou;Forma de Pagamento;Status;Descrição;Observações');
    for (final t in transactions) {
      final typeLabel = t.isExpense ? 'Saída' : 'Entrada';
      final statusLabel = t.isPending ? 'Pendente' : 'Concluído';
      b.writeln([
        _formatDate(t.date),
        typeLabel,
        _escapeText(t.title),
        _escapeText(t.categoryName ?? (t.isExpense ? 'Sem categoria' : 'Entrada / Aporte')),
        (t.isExpense ? '-' : '') + _formatMoney(t.amount),
        _escapeText(t.memberName ?? '-'),
        _escapeText(t.paymentMethodName ?? '-'),
        statusLabel,
        _escapeText(t.description ?? ''),
        _escapeText(t.notes ?? ''),
      ].join(';'));
    }

    return b.toString();
  }

  /// Gera arquivo binário PDF elegante e pronto para impressão/compartilhamento.
  Future<Uint8List> buildPdf({
    required String houseName,
    required String periodDescription,
    required List<HouseTransaction> transactions,
    required TransactionAggregatorMetrics metrics,
  }) async {
    final pdf = pw.Document();

    const primaryColor = PdfColor.fromInt(0xFF10B981);
    const dangerColor = PdfColor.fromInt(0xFFEF4444);
    const greyColor = PdfColor.fromInt(0xFF6B7280);
    const lightGrey = PdfColor.fromInt(0xFFF3F4F6);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Omni Lar - Extrato de Transações',
                        style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: primaryColor)),
                    pw.SizedBox(height: 2),
                    pw.Text(houseName, style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
                    pw.Text(periodDescription, style: const pw.TextStyle(fontSize: 11, color: greyColor)),
                  ],
                ),
                pw.Text(
                  'Gerado em ${_formatDate(DateTime.now())}',
                  style: const pw.TextStyle(fontSize: 10, color: greyColor),
                ),
              ],
            ),
            pw.SizedBox(height: 12),
            // Cartão de Resumo Financeiro
            pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                color: lightGrey,
                borderRadius: pw.BorderRadius.circular(8),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                children: [
                  pw.Column(
                    children: [
                      pw.Text('Entradas', style: const pw.TextStyle(fontSize: 10, color: greyColor)),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        '+ R\$ ${_formatMoney(metrics.totalInflows)}',
                        style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: primaryColor),
                      ),
                    ],
                  ),
                  pw.Column(
                    children: [
                      pw.Text('Saídas', style: const pw.TextStyle(fontSize: 10, color: greyColor)),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        '- R\$ ${_formatMoney(metrics.totalExpenses)}',
                        style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: dangerColor),
                      ),
                    ],
                  ),
                  pw.Column(
                    children: [
                      pw.Text('Saldo Líquido', style: const pw.TextStyle(fontSize: 10, color: greyColor)),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        'R\$ ${_formatMoney(metrics.netBalance)}',
                        style: pw.TextStyle(
                          fontSize: 12,
                          fontWeight: pw.FontWeight.bold,
                          color: metrics.netBalance.cents >= 0 ? primaryColor : dangerColor,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            pw.Divider(thickness: 0.5, color: greyColor),
            pw.SizedBox(height: 8),
          ],
        ),
        build: (context) => [
          pw.TableHelper.fromTextArray(
            headers: ['Data', 'Tipo', 'Título', 'Categoria', 'Quem', 'Valor'],
            data: transactions.map((t) {
              return [
                _formatDate(t.date),
                t.isExpense ? 'Saída' : 'Entrada',
                t.title,
                t.categoryName ?? (t.isExpense ? '-' : 'Aporte/Entrada'),
                t.memberName?.split(' ').first ?? '-',
                '${t.isExpense ? "- " : "+ "}R\$ ${_formatMoney(t.amount)}',
              ];
            }).toList(),
            headerStyle: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
            headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF1F2937)),
            cellStyle: const pw.TextStyle(fontSize: 9),
            cellAlignment: pw.Alignment.centerLeft,
            cellAlignments: {5: pw.Alignment.centerRight},
            rowDecoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: lightGrey))),
          ),
        ],
        footer: (context) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('Omni Lar - Gestão Financeira Transparente para Moradias Compartilhadas',
                style: const pw.TextStyle(fontSize: 8, color: greyColor)),
            pw.Text('Página ${context.pageNumber} de ${context.pagesCount}',
                style: const pw.TextStyle(fontSize: 8, color: greyColor)),
          ],
        ),
      ),
    );

    return pdf.save();
  }
}
