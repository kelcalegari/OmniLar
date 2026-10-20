import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../finance/domain/entities/house_expense.dart';
import '../../../finance/domain/entities/savings_vault.dart';
import '../entities/project_settlement_summary.dart';
import '../entities/shared_project.dart';

class ProjectReportExport {
  const ProjectReportExport();

  static String fileNamePdf(SharedProject project) {
    final clean = project.title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    return 'omnilar_projeto_${clean}_relatorio.pdf';
  }

  static String fileNameCsv(SharedProject project) {
    final clean = project.title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    return 'omnilar_projeto_${clean}_planilha.csv';
  }

  /// Gera a prestação de contas do projeto em PDF profissional.
  Future<Uint8List> buildPdf({
    required SharedProject project,
    required ProjectSettlementSummary summary,
    required List<HouseExpense> expenses,
    SavingsVault? linkedVault,
    String Function(String id)? resolvePayerName,
  }) async {
    final doc = pw.Document();
    final now = DateTime.now();
    final dateFormat = DateFormat('dd/MM/yyyy');

    String sanitize(String text) {
      const replacements = {
        '—': '-',
        '–': '-',
        '−': '-',
        '•': '-',
        '▲': '+',
        '▼': '-',
        '“': '"',
        '”': '"',
        '‘': "'",
        '’': "'",
        '…': '...',
        ' ': ' ',
        '➔': '->',
        '✈️': '',
        '🏖️': '',
        '🛠️': '',
        '🎉': '',
        '🔑': 'Pix: ',
        '📱': 'Tel: ',
      };
      final b = StringBuffer();
      for (final rune in text.runes) {
        final char = String.fromCharCode(rune);
        final replacement = replacements[char];
        if (replacement != null) {
          b.write(replacement);
        } else if (rune <= 0xFF) {
          b.write(char);
        }
      }
      return b.toString();
    }

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (context) => pw.Container(
          padding: const pw.EdgeInsets.only(bottom: 8),
          decoration: const pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey400, width: 0.5)),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Omni Lar - Relatorio de Projeto Compartilhado',
                style: pw.TextStyle(color: PdfColors.grey700, fontSize: 9, fontWeight: pw.FontWeight.bold),
              ),
              pw.Text(
                dateFormat.format(now),
                style: const pw.TextStyle(color: PdfColors.grey600, fontSize: 9),
              ),
            ],
          ),
        ),
        footer: (context) => pw.Container(
          padding: const pw.EdgeInsets.only(top: 8),
          decoration: const pw.BoxDecoration(
            border: pw.Border(top: pw.BorderSide(color: PdfColors.grey400, width: 0.5)),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Fechamento independente isolado do Caixa da Casa',
                style: const pw.TextStyle(color: PdfColors.grey600, fontSize: 8),
              ),
              pw.Text(
                'Pagina ${context.pageNumber} de ${context.pagesCount}',
                style: const pw.TextStyle(color: PdfColors.grey600, fontSize: 8),
              ),
            ],
          ),
        ),
        build: (context) => [
          // Título e Período
          pw.SizedBox(height: 12),
          pw.Text(
            sanitize(project.title),
            style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: PdfColors.indigo900),
          ),
          if (project.description != null && project.description!.trim().isNotEmpty) ...[
            pw.SizedBox(height: 4),
            pw.Text(
              sanitize(project.description!),
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
            ),
          ],
          pw.SizedBox(height: 4),
          pw.Text(
            'Periodo: ${project.startDate != null ? dateFormat.format(project.startDate!) : "N/D"} ate ${project.endDate != null ? dateFormat.format(project.endDate!) : "N/D"}',
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
          ),
          pw.SizedBox(height: 16),

          // Resumo Financeiro
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: PdfColors.grey100,
              borderRadius: pw.BorderRadius.circular(6),
              border: pw.Border.all(color: PdfColors.grey300),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Total Gasto', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
                    pw.Text(
                      summary.totalExpenses.formatted,
                      style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.indigo900),
                    ),
                  ],
                ),
                if (project.targetBudget != null && project.targetBudget!.cents > 0)
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('Teto Orcado', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
                      pw.Text(
                        project.targetBudget!.formatted,
                        style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.grey800),
                      ),
                    ],
                  ),
                if (linkedVault != null)
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('Fundo Caixinha (${sanitize(linkedVault.name)})', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
                      pw.Text(
                        linkedVault.currentBalance.formatted,
                        style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.teal800),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          pw.SizedBox(height: 20),

          // 1. Balanço por Participante
          pw.Text('1. Balanco por Participante', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          pw.TableHelper.fromTextArray(
            headers: ['Participante', 'Total Pago', 'Cota Devida', 'Saldo Liquido'],
            data: summary.participantBalances.map((bal) {
              final isCreditor = bal.isCreditor;
              final prefix = isCreditor ? '+' : '';
              return [
                sanitize(bal.participantName),
                bal.totalPaid.formatted,
                bal.totalShareDue.formatted,
                '$prefix${bal.netBalance.formatted}',
              ];
            }).toList(),
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9, color: PdfColors.white),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.indigo800),
            rowDecoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5))),
            cellStyle: const pw.TextStyle(fontSize: 9),
            cellAlignment: pw.Alignment.centerLeft,
            cellAlignments: {
              1: pw.Alignment.centerRight,
              2: pw.Alignment.centerRight,
              3: pw.Alignment.centerRight,
            },
          ),
          pw.SizedBox(height: 20),

          // 2. Transferências Mínimas (Super Pix)
          pw.Text('2. Compensacao Minima (Super Pix do Projeto)', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          if (summary.transfers.isEmpty)
            pw.Text('Todas as contas estao 100% quitadas. Nenhuma transferencia pendente.', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700))
          else
            pw.TableHelper.fromTextArray(
              headers: ['Quem Paga', 'Quem Recebe', 'Valor', 'Chave Pix'],
              data: summary.transfers.map((t) {
                return [
                  sanitize(t.fromMemberName),
                  sanitize(t.toMemberName),
                  t.amount.formatted,
                  t.pixKey != null && t.pixKey!.isNotEmpty ? sanitize(t.pixKey!) : '-',
                ];
              }).toList(),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9, color: PdfColors.white),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.teal800),
              rowDecoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5))),
              cellStyle: const pw.TextStyle(fontSize: 9),
              cellAlignment: pw.Alignment.centerLeft,
              cellAlignments: {
                2: pw.Alignment.centerRight,
              },
            ),
          pw.SizedBox(height: 20),

          // 3. Despesas Detalhadas
          pw.Text('3. Despesas Detalhadas do Projeto (${expenses.length})', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          if (expenses.isEmpty)
            pw.Text('Nenhuma despesa lancada ainda neste projeto.', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700))
          else
            pw.TableHelper.fromTextArray(
              headers: ['Data', 'Descricao', 'Quem Pagou', 'Valor'],
              data: expenses.map((e) {
                final payer = resolvePayerName != null ? resolvePayerName(e.paidByMemberId) : e.paidByMemberId;
                var desc = e.title;
                if (e.notes != null && e.notes!.contains('[Câmbio:')) {
                  final start = e.notes!.indexOf('[Câmbio:');
                  final end = e.notes!.indexOf(']', start);
                  if (end != -1) {
                    desc += ' ${e.notes!.substring(start, end + 1)}';
                  }
                }
                return [
                  dateFormat.format(e.date),
                  sanitize(desc),
                  sanitize(payer),
                  e.amount.formatted,
                ];
              }).toList(),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9, color: PdfColors.white),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey800),
              rowDecoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5))),
              cellStyle: const pw.TextStyle(fontSize: 8),
              cellAlignment: pw.Alignment.centerLeft,
              cellAlignments: {
                3: pw.Alignment.centerRight,
              },
            ),
        ],
      ),
    );

    return doc.save();
  }

  /// Gera a planilha CSV (padrão Brasil: ponto e vírgula e UTF-8 BOM).
  String buildCsv({
    required SharedProject project,
    required ProjectSettlementSummary summary,
    required List<HouseExpense> expenses,
    SavingsVault? linkedVault,
    String Function(String id)? resolvePayerName,
  }) {
    final b = StringBuffer();
    final dateFormat = DateFormat('dd/MM/yyyy');

    // UTF-8 BOM para abrir acentos perfeitamente no Excel
    b.write('\uFEFF');

    // Cabeçalho
    b.writeln('PROJETO;${project.title}');
    b.writeln('TIPO;${project.type.name}');
    b.writeln('STATUS;${project.status.name}');
    b.writeln('TOTAL GASTO;${(summary.totalExpenses.cents / 100.0).toStringAsFixed(2)}');
    if (project.targetBudget != null) {
      b.writeln('TETO ORCADO;${(project.targetBudget!.cents / 100.0).toStringAsFixed(2)}');
    }
    if (linkedVault != null) {
      b.writeln('CAIXINHA VINCULADA;${linkedVault.name};SALDO;${(linkedVault.currentBalance.cents / 100.0).toStringAsFixed(2)}');
    }
    b.writeln('');

    // Balanço
    b.writeln('--- BALANÇO POR PARTICIPANTE ---');
    b.writeln('Participante;Total Pago (R\$);Cota Devida (R\$);Saldo Liquido (R\$)');
    for (final bal in summary.participantBalances) {
      b.writeln('${bal.participantName};${(bal.totalPaid.cents / 100.0).toStringAsFixed(2)};${(bal.totalShareDue.cents / 100.0).toStringAsFixed(2)};${(bal.netBalance.cents / 100.0).toStringAsFixed(2)}');
    }
    b.writeln('');

    // Super Pix
    b.writeln('--- TRANSFERÊNCIAS MÍNIMAS (SUPER PIX) ---');
    b.writeln('De (Quem Paga);Para (Quem Recebe);Valor (R\$);Chave Pix');
    for (final t in summary.transfers) {
      b.writeln('${t.fromMemberName};${t.toMemberName};${(t.amount.cents / 100.0).toStringAsFixed(2)};${t.pixKey ?? ""}');
    }
    b.writeln('');

    // Despesas
    b.writeln('--- DESPESAS DO PROJETO ---');
    b.writeln('Data;Titulo;Quem Pagou;Valor (R\$);Notas / Cambio');
    for (final e in expenses) {
      final payer = resolvePayerName != null ? resolvePayerName(e.paidByMemberId) : e.paidByMemberId;
      final notes = (e.notes ?? '').replaceAll(';', ',');
      b.writeln('${dateFormat.format(e.date)};${e.title};$payer;${(e.amount.cents / 100.0).toStringAsFixed(2)};$notes');
    }

    return b.toString();
  }
}
