import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../../core/domain/value_objects/financial_cycle.dart';
import '../../../../core/domain/value_objects/money.dart';
import '../../../finance/domain/entities/category.dart';
import '../../../finance/domain/entities/contribution.dart';
import '../../../finance/domain/entities/financial_cycle_summary.dart';
import '../../../finance/domain/entities/house_expense.dart';
import '../../../finance/domain/entities/house_member.dart';
import '../entities/cycle_insights.dart';
import '../entities/cycle_preview.dart';

/// Prestação de contas do ciclo em PDF: resumo, gastos por categoria,
/// aportes, fechamento por morador, quem pagou, empréstimos e a lista de
/// despesas.
///
/// Usa as fontes que todo leitor de PDF tem (Helvetica), que só cobrem o
/// alfabeto latino: o texto passa por [_latin] antes de ir para a página.
class CycleReportPdf {
  const CycleReportPdf();

  static String fileNameFor(FinancialCycle cycle) {
    final s = cycle.startDate;
    return 'omnilar_prestacao_de_contas_${s.year}-${s.month.toString().padLeft(2, '0')}-${s.day.toString().padLeft(2, '0')}.pdf';
  }

  static String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  /// Troca o que a Helvetica não desenha por equivalentes simples.
  static String _latin(String text) {
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

  static String _money(Money m) => _latin(m.formatted);

  /// Em ordem de data, mantendo a ordem da lista entre as do mesmo dia (o
  /// `sort` do Dart não garante isso).
  static List<HouseExpense> _byDate(List<HouseExpense> expenses) {
    final indexed = expenses.indexed.toList()
      ..sort((a, b) {
        final byDate = a.$2.date.compareTo(b.$2.date);
        return byDate != 0 ? byDate : a.$1.compareTo(b.$1);
      });
    return [for (final (_, e) in indexed) e];
  }

  Future<Uint8List> build({
    required String houseName,
    required FinancialCycle cycle,
    required List<HouseExpense> expenses,
    required List<ExpenseCategory> categories,
    required List<HouseMember> members,
    required List<Contribution> contributions,
    FinancialCycleSummary? summary,
    CyclePreview? preview,
    CycleInsights? insights,
    required DateTime generatedAt,
  }) {
    final doc = pw.Document(
      title: _latin('Prestação de contas - $houseName'),
      author: 'Omni Lar',
    );
    final categoryNames = {for (final c in categories) c.id: c.name};
    final memberNames = {for (final m in members) m.id: m.name};
    final house = expenses.where((e) => !e.isProjectExpense).toList();

    final paidCents = house
        .where((e) => !e.isPending)
        .fold<int>(0, (a, e) => a + e.amount.cents);
    final pendingCents = house
        .where((e) => e.isPending)
        .fold<int>(0, (a, e) => a + e.amount.cents);
    final totalCents = paidCents + pendingCents;

    final byCategory = <String, int>{};
    for (final e in house) {
      byCategory[e.categoryId] =
          (byCategory[e.categoryId] ?? 0) + e.amount.cents;
    }
    final categoryIds = byCategory.keys.toList()
      ..sort((a, b) => byCategory[b]!.compareTo(byCategory[a]!));

    final byMember = <String, int>{};
    for (final c in contributions) {
      byMember[c.memberId] = (byMember[c.memberId] ?? 0) + c.amount.cents;
    }

    const accent = PdfColor.fromInt(0xFF0F766E);
    final small = pw.TextStyle(fontSize: 8, color: PdfColors.grey700);

    pw.Widget heading(String text) => pw.Padding(
      padding: const pw.EdgeInsets.only(top: 14, bottom: 6),
      child: pw.Text(
        _latin(text),
        style: pw.TextStyle(
          fontSize: 13,
          fontWeight: pw.FontWeight.bold,
          color: accent,
        ),
      ),
    );

    pw.Widget table(
      List<String> headers,
      List<List<String>> rows, {
      Set<int> right = const {},
    }) => pw.TableHelper.fromTextArray(
      headers: [for (final h in headers) _latin(h)],
      data: [
        for (final r in rows) [for (final c in r) _latin(c)],
      ],
      headerStyle: pw.TextStyle(
        fontSize: 8.5,
        fontWeight: pw.FontWeight.bold,
        color: PdfColors.white,
      ),
      headerDecoration: const pw.BoxDecoration(color: accent),
      cellStyle: const pw.TextStyle(fontSize: 8.5),
      cellAlignments: {
        for (var i = 0; i < headers.length; i++)
          i: right.contains(i)
              ? pw.Alignment.centerRight
              : pw.Alignment.centerLeft,
      },
      oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
      border: null,
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
    );

    pw.Widget tile(String label, String value) => pw.Expanded(
      child: pw.Container(
        margin: const pw.EdgeInsets.only(right: 6),
        padding: const pw.EdgeInsets.all(8),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey300),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(_latin(label), style: small),
            pw.SizedBox(height: 2),
            pw.Text(
              value,
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
            ),
          ],
        ),
      ),
    );

    String payerOf(HouseExpense e) => e.isPending
        ? 'Em aberto'
        : (e.paidOutOfPocket && e.paymentMethodId != 'pm_caixa'
              ? '${memberNames[e.paidByMemberId] ?? 'Membro'} (do bolso)'
              : 'Caixa da Casa');

    final content = <pw.Widget>[
      pw.Text(
        _latin('Prestação de contas'),
        style: pw.TextStyle(
          fontSize: 20,
          fontWeight: pw.FontWeight.bold,
          color: accent,
        ),
      ),
      pw.Text(_latin(houseName), style: const pw.TextStyle(fontSize: 13)),
      pw.SizedBox(height: 2),
      pw.Text(
        _latin(
          'Ciclo de ${_date(cycle.startDate)} a ${_date(cycle.endDate)}'
          '${preview?.isSettled == true ? ' · fechado${preview!.settledAt != null ? ' em ${_date(preview.settledAt!)}' : ''}' : ' · em aberto'}',
        ),
        style: small,
      ),
      heading('Resumo'),
      pw.Row(
        children: [
          tile('Pago', _money(Money(paidCents))),
          tile('A vencer', _money(Money(pendingCents))),
          tile('Total do ciclo', _money(Money(totalCents))),
        ],
      ),
      pw.SizedBox(height: 6),
      pw.Row(
        children: [
          tile(
            'Aportes',
            _money(
              summary?.totalContributions ??
                  Money(byMember.values.fold<int>(0, (a, c) => a + c)),
            ),
          ),
          tile(
            'Sobra anterior e caixinhas',
            _money(summary?.openingBalance ?? const Money.zero()),
          ),
          tile('Fôlego', _money(summary?.folego ?? const Money.zero())),
        ],
      ),
      heading('Gastos por categoria'),
      if (categoryIds.isEmpty)
        pw.Text(_latin('Nenhuma despesa no ciclo.'), style: small)
      else
        table(
          [
            'Categoria',
            'Valor',
            '% do ciclo',
            if (insights != null && insights.previousTotal.isPositive)
              'Ciclo anterior',
          ],
          [
            for (final id in categoryIds)
              [
                categoryNames[id] ?? 'Outros',
                _money(Money(byCategory[id]!)),
                '${(byCategory[id]! * 100 / (totalCents > 0 ? totalCents : 1)).toStringAsFixed(1)}%',
                if (insights != null && insights.previousTotal.isPositive)
                  _money(Money(insights.previousByCategory[id] ?? 0)),
              ],
          ],
          right: {1, 2, 3},
        ),
      heading('Aportes por morador'),
      table(
        ['Morador', 'Aportado'],
        [
          for (final m in members) [m.name, _money(Money(byMember[m.id] ?? 0))],
        ],
        right: {1},
      ),
      if (preview != null && preview.members.isNotEmpty) ...[
        heading(
          preview.isSettled
              ? 'Fechamento por morador'
              : 'Prévia do fechamento por morador',
        ),
        if (!preview.isSettled)
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 4),
            child: pw.Text(
              _latin(
                'Mesmo cálculo do Hub de Liquidação, considerando as faturas e contas em aberto pagas por quem o fechamento escolheria por padrão.',
              ),
              style: small,
            ),
          ),
        table(
          [
            'Morador',
            'Aporte do ciclo',
            'Aportado',
            'Do bolso',
            'Parcelas a pagar',
            'A receber',
            'Saldo',
          ],
          [
            for (final m in preview.members)
              [
                m.memberName,
                _money(m.contributionDue),
                _money(m.contributionPaid),
                _money(m.outOfPocket),
                _money(m.p2pToPay),
                _money(m.p2pToReceive),
                m.net.isNegative
                    ? 'paga ${_money(Money(-m.net.cents))}'
                    : (m.net.isPositive ? 'recebe ${_money(m.net)}' : '-'),
              ],
          ],
          right: {1, 2, 3, 4, 5, 6},
        ),
        ...() {
          final transfers = {
            for (final m in preview.members) ...{
              for (final t in m.transfersOut) t.id: t,
            },
          }.values.toList();
          if (transfers.isEmpty) return <pw.Widget>[];
          return [
            pw.SizedBox(height: 6),
            table(
              ['De', 'Para', 'Valor'],
              [
                for (final t in transfers)
                  [t.fromMemberName, t.toMemberName, _money(t.amount)],
              ],
              right: {2},
            ),
          ];
        }(),
      ],
      if (insights != null && insights.byPayer.isNotEmpty) ...[
        heading('Quem pagou as despesas'),
        table(
          ['Quem', 'Valor', '%'],
          [
            for (final p in insights.byPayer)
              [
                p.memberId == null ? p.name : '${p.name} (do bolso)',
                _money(p.amount),
                '${(p.amount.cents * 100 / (totalCents > 0 ? totalCents : 1)).toStringAsFixed(1)}%',
              ],
          ],
          right: {1, 2},
        ),
      ],
      if (insights != null && insights.loanPositions.isNotEmpty) ...[
        heading('Empréstimos em aberto'),
        table(
          ['Morador', 'A receber', 'A pagar', 'Já pagou', 'Parcelas vencidas'],
          [
            for (final p in insights.loanPositions)
              [
                p.name,
                _money(p.toReceive),
                _money(p.toPay),
                _money(p.alreadyPaid),
                '${p.overdueInstallments}',
              ],
          ],
          right: {1, 2, 3, 4},
        ),
      ],
      heading('Despesas do ciclo'),
      if (house.isEmpty)
        pw.Text(_latin('Nenhuma despesa no ciclo.'), style: small)
      else
        table(
          ['Data', 'Descrição', 'Categoria', 'Quem pagou', 'Situação', 'Valor'],
          [
            for (final e in _byDate(house))
              [
                _date(e.date),
                e.title,
                categoryNames[e.categoryId] ?? 'Geral',
                payerOf(e),
                e.isPending ? 'Pendente' : 'Paga',
                _money(e.amount),
              ],
          ],
          right: {5},
        ),
    ];

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        footer: (context) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              _latin('Gerado pelo Omni Lar em ${_date(generatedAt)}'),
              style: small,
            ),
            pw.Text(
              _latin('Página ${context.pageNumber} de ${context.pagesCount}'),
              style: small,
            ),
          ],
        ),
        build: (_) => content,
      ),
    );
    return doc.save();
  }
}
