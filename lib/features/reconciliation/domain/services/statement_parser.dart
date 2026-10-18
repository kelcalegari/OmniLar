import 'dart:convert';

import '../../../../core/domain/value_objects/money.dart';
import '../entities/csv_mapping.dart';
import '../entities/imported_statement_line.dart';
import 'statement_text.dart';

/// Linha lida do arquivo, ainda com o sinal original do valor.
class _RawLine {
  final DateTime date;
  final String description;
  final int signedCents;
  final String? externalId;

  const _RawLine(this.date, this.description, this.signedCents, [this.externalId]);
}

class StatementParser {
  StatementParser._();

  static final _paymentWords = RegExp(r'\b(pagamento|pagto|pgto|payment)\b', caseSensitive: false);
  static final _invoiceWords = RegExp(
    r'\b(fatura|cartao de credito|cartão de crédito|pagto cartao|pgto cartao)\b',
    caseSensitive: false,
  );

  /// Texto do arquivo: UTF-8 quando válido, senão Latin-1 (padrão dos OFX de banco).
  static String decodeBytes(List<int> bytes) {
    try {
      return utf8.decode(bytes);
    } on FormatException {
      return latin1.decode(bytes);
    }
  }

  /// Valor em centavos com sinal, aceitando "1.234,56", "1234.56", "R$ 10,00",
  /// "-10,00", "10,00-" e "(10,00)". Null quando o texto não é um valor.
  static int? parseSignedCents(String text) {
    var value = text.replaceAll('R\$', '').replaceAll(RegExp(r'[\s "]'), '');
    if (value.isEmpty) return null;

    var negative = false;
    if (value.startsWith('(') && value.endsWith(')')) {
      negative = true;
      value = value.substring(1, value.length - 1);
    }
    if (value.startsWith('-') || value.endsWith('-')) {
      negative = true;
      value = value.replaceAll('-', '');
    }
    value = value.replaceAll('+', '');
    if (!RegExp(r'^\d[\d.,]*$').hasMatch(value)) return null;

    final lastDot = value.lastIndexOf('.');
    final lastComma = value.lastIndexOf(',');
    var decimalAt = -1;
    if (lastDot >= 0 && lastComma >= 0) {
      decimalAt = lastDot > lastComma ? lastDot : lastComma;
    } else {
      final at = lastDot >= 0 ? lastDot : lastComma;
      if (at >= 0) {
        final separator = value[at];
        final single = value.indexOf(separator) == at;
        final digitsAfter = value.length - at - 1;
        // "1.234" é milhar; "12.5" e "12,50" são decimais
        if (single && digitsAfter != 3) decimalAt = at;
      }
    }

    final integerPart = (decimalAt >= 0 ? value.substring(0, decimalAt) : value)
        .replaceAll(RegExp(r'[.,]'), '');
    var fraction = decimalAt >= 0 ? value.substring(decimalAt + 1) : '';
    if (fraction.length > 2) fraction = fraction.substring(0, 2);
    fraction = fraction.padRight(2, '0');

    final cents = (int.tryParse(integerPart.isEmpty ? '0' : integerPart) ?? 0) * 100 +
        (int.tryParse(fraction) ?? 0);
    return negative ? -cents : cents;
  }

  /// Data em "2026-10-05", "05/10/2026", "05/10/26" ou "05/10" (sem ano vale o
  /// ano corrente, ou o anterior se cairia no futuro).
  static DateTime? parseDate(String text, {DateTime? now}) {
    final value = text.replaceAll('"', '').trim();

    final iso = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(value);
    if (iso != null) {
      return _validDate(int.parse(iso.group(1)!), int.parse(iso.group(2)!), int.parse(iso.group(3)!));
    }

    final br = RegExp(r'^(\d{1,2})[/.\-](\d{1,2})(?:[/.\-](\d{2}|\d{4}))?$').firstMatch(value);
    if (br == null) return null;
    final day = int.parse(br.group(1)!);
    final month = int.parse(br.group(2)!);
    final yearText = br.group(3);
    if (yearText != null) {
      final year = int.parse(yearText);
      return _validDate(year < 100 ? 2000 + year : year, month, day);
    }

    final today = now ?? DateTime.now();
    final sameYear = _validDate(today.year, month, day);
    if (sameYear == null) return null;
    return sameYear.isAfter(today.add(const Duration(days: 31)))
        ? _validDate(today.year - 1, month, day)
        : sameYear;
  }

  static DateTime? _validDate(int year, int month, int day) {
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    final date = DateTime(year, month, day);
    return date.month == month ? date : null;
  }

  /// Parser para faturas e extratos em CSV. Aceita `,`, `;` ou tabulação como
  /// separador, datas e valores no formato brasileiro e cabeçalho opcional.
  static List<ImportedStatementLine> parseCsv(
    String csvContent, {
    StatementSourceType source = StatementSourceType.creditCard,
  }) {
    final rows = const LineSplitter()
        .convert(csvContent.replaceFirst('﻿', ''))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    if (rows.isEmpty) return const [];

    final delimiter = _detectDelimiter(rows);
    int? dateColumn;
    int? descriptionColumn;
    int? amountColumn;
    int? headerLength;
    final raw = <_RawLine>[];

    for (final row in rows) {
      var cells = _splitCsvRow(row, delimiter);

      // Cabeçalho: diz em que coluna está cada campo
      if (raw.isEmpty && headerLength == null && _looksLikeHeader(cells)) {
        headerLength = cells.length;
        for (var i = 0; i < cells.length; i++) {
          final name = StatementText.normalize(cells[i]);
          if (dateColumn == null && (name.startsWith('data') || name.startsWith('date'))) {
            dateColumn = i;
          } else if (amountColumn == null &&
              (name.startsWith('valor') || name.startsWith('amount') || name.startsWith('quantia'))) {
            amountColumn = i;
          } else if (descriptionColumn == null &&
              RegExp(r'^(descri|histor|lancamento|title|estabelecimento|memo|nome)').hasMatch(name)) {
            descriptionColumn = i;
          }
        }
        continue;
      }

      // "05/10/2026,Mercado,485,60": a vírgula do valor partiu a última coluna
      if (delimiter == ',' && cells.length >= 4 && cells.length != headerLength) {
        final last = cells[cells.length - 1].trim();
        final beforeLast = cells[cells.length - 2].trim();
        if (RegExp(r'^\d{2}$').hasMatch(last) && RegExp(r'^-?\d[\d.]*$').hasMatch(beforeLast)) {
          cells = [...cells.sublist(0, cells.length - 2), '$beforeLast,$last'];
        }
      }

      final dateAt = dateColumn ?? cells.indexWhere((c) => parseDate(c) != null);
      if (dateAt < 0 || dateAt >= cells.length) continue;
      final date = parseDate(cells[dateAt]);
      if (date == null) continue;

      var amountAt = amountColumn ?? -1;
      if (amountAt < 0 || amountAt >= cells.length) {
        amountAt = -1;
        for (var i = cells.length - 1; i > dateAt; i--) {
          if (parseSignedCents(cells[i]) != null) {
            amountAt = i;
            break;
          }
        }
      }
      if (amountAt < 0) continue;
      final cents = parseSignedCents(cells[amountAt]);
      if (cents == null || cents == 0) continue;

      var descriptionAt = descriptionColumn ?? -1;
      if (descriptionAt < 0 || descriptionAt >= cells.length) {
        descriptionAt = -1;
        for (var i = 0; i < cells.length; i++) {
          if (i == dateAt || i == amountAt || cells[i].trim().isEmpty) continue;
          if (descriptionAt < 0 || cells[i].trim().length > cells[descriptionAt].trim().length) {
            descriptionAt = i;
          }
        }
      }
      final description = descriptionAt >= 0 ? cells[descriptionAt].trim() : '';

      raw.add(_RawLine(date, description.isEmpty ? 'Lançamento' : description, cents));
    }

    return _classify(raw, source, positiveIsOutflowOnTie: true);
  }

  static List<String> _csvRows(String csvContent) => const LineSplitter()
      .convert(csvContent.replaceFirst('\uFEFF', ''))
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();

  /// Primeiras linhas do CSV já separadas em colunas, para o usuário dizer o
  /// que é cada uma. Todas as linhas ficam com o mesmo número de colunas.
  static List<List<String>> csvPreview(String csvContent, {String? delimiter, int rows = 8}) {
    final all = _csvRows(csvContent);
    if (all.isEmpty) return const [];
    final separator = delimiter ?? _detectDelimiter(all);
    final split = [for (final row in all.take(rows)) _splitCsvRow(row, separator).map((c) => c.trim()).toList()];
    final width = split.fold<int>(0, (max, row) => row.length > max ? row.length : max);
    return [
      for (final row in split) [...row, for (var i = row.length; i < width; i++) ''],
    ];
  }

  /// Palpite de mapeamento para o CSV: pelo cabeçalho, quando há, senão pelo
  /// conteúdo da primeira linha de dados. Serve de ponto de partida na tela.
  static CsvMapping guessCsvMapping(String csvContent) {
    final all = _csvRows(csvContent);
    final delimiter = all.isEmpty ? ',' : _detectDelimiter(all);
    final preview = csvPreview(csvContent, delimiter: delimiter);
    if (preview.isEmpty) return CsvMapping(delimiter: delimiter, hasHeader: false, roles: const []);

    final width = preview.first.length;
    final roles = List<CsvColumnRole>.filled(width, CsvColumnRole.ignore);
    final hasHeader = _looksLikeHeader(preview.first);

    if (hasHeader) {
      for (var i = 0; i < width; i++) {
        final name = StatementText.normalize(preview.first[i]);
        if (!roles.contains(CsvColumnRole.date) && (name.startsWith('data') || name.startsWith('date'))) {
          roles[i] = CsvColumnRole.date;
        } else if (RegExp(r'^(debito|saida|saidas)').hasMatch(name)) {
          roles[i] = CsvColumnRole.debit;
        } else if (RegExp(r'^(credito|entrada|entradas)').hasMatch(name)) {
          roles[i] = CsvColumnRole.credit;
        } else if (!roles.contains(CsvColumnRole.amount) &&
            (name.startsWith('valor') || name.startsWith('amount') || name.startsWith('quantia'))) {
          roles[i] = CsvColumnRole.amount;
        } else if (!roles.contains(CsvColumnRole.description) &&
            RegExp(r'^(descri|histor|lancamento|title|estabelecimento|memo|nome)').hasMatch(name)) {
          roles[i] = CsvColumnRole.description;
        }
      }
    }

    // O que o cabeçalho não disse, a primeira linha de dados sugere
    final sample = preview.length > (hasHeader ? 1 : 0) ? preview[hasHeader ? 1 : 0] : preview.first;
    if (!roles.contains(CsvColumnRole.date)) {
      final at = sample.indexWhere((c) => parseDate(c) != null);
      if (at >= 0) roles[at] = CsvColumnRole.date;
    }
    final hasValue = roles.any((r) =>
        r == CsvColumnRole.amount || r == CsvColumnRole.debit || r == CsvColumnRole.credit);
    if (!hasValue) {
      for (var i = width - 1; i >= 0; i--) {
        if (roles[i] == CsvColumnRole.ignore && parseSignedCents(sample[i]) != null) {
          roles[i] = CsvColumnRole.amount;
          break;
        }
      }
    }
    if (!roles.contains(CsvColumnRole.description)) {
      var best = -1;
      for (var i = 0; i < width; i++) {
        if (roles[i] != CsvColumnRole.ignore || sample[i].isEmpty) continue;
        if (parseSignedCents(sample[i]) != null) continue;
        if (best < 0 || sample[i].length > sample[best].length) best = i;
      }
      if (best >= 0) roles[best] = CsvColumnRole.description;
    }
    return CsvMapping(delimiter: delimiter, hasHeader: hasHeader, roles: roles);
  }

  /// Lê o CSV como o usuário disse: cada coluna com o seu papel. Linha sem
  /// data ou sem valor é pulada. Com débito e crédito em colunas separadas, o
  /// débito é saída (negativo) e o crédito, entrada.
  static List<ImportedStatementLine> parseCsvWithMapping(
    String csvContent,
    CsvMapping mapping, {
    StatementSourceType source = StatementSourceType.creditCard,
  }) {
    if (!mapping.isComplete) return const [];
    final rows = _csvRows(csvContent);
    final dateAt = mapping.indexOf(CsvColumnRole.date)!;
    final descriptionAt = mapping.indexOf(CsvColumnRole.description)!;
    final amountAt = mapping.indexOf(CsvColumnRole.amount);
    final debitAt = mapping.indexOf(CsvColumnRole.debit);
    final creditAt = mapping.indexOf(CsvColumnRole.credit);

    String cell(List<String> cells, int? index) =>
        index == null || index >= cells.length ? '' : cells[index].trim();

    final raw = <_RawLine>[];
    for (var r = mapping.hasHeader ? 1 : 0; r < rows.length; r++) {
      final cells = _splitCsvRow(rows[r], mapping.delimiter);
      final date = parseDate(cell(cells, dateAt));
      if (date == null) continue;

      int? cents;
      if (amountAt != null) {
        cents = parseSignedCents(cell(cells, amountAt));
      } else {
        final debit = parseSignedCents(cell(cells, debitAt))?.abs() ?? 0;
        final credit = parseSignedCents(cell(cells, creditAt))?.abs() ?? 0;
        cents = credit - debit;
      }
      if (cents == null || cents == 0) continue;

      final description = cell(cells, descriptionAt);
      raw.add(_RawLine(date, description.isEmpty ? 'Lançamento' : description, cents));
    }
    return _classify(raw, source, positiveIsOutflowOnTie: true);
  }

  static bool _looksLikeHeader(List<String> cells) =>
      cells.every((c) => parseDate(c) == null) &&
      cells.any((c) {
        final name = StatementText.normalize(c);
        return name.startsWith('data') || name.startsWith('date');
      });

  static String _detectDelimiter(List<String> rows) {
    final sample = rows.take(5);
    for (final candidate in const [';', '\t', '|']) {
      if (sample.where((row) => row.contains(candidate)).length * 2 > sample.length) {
        return candidate;
      }
    }
    return ',';
  }

  static List<String> _splitCsvRow(String row, String delimiter) {
    final cells = <String>[];
    final current = StringBuffer();
    var quoted = false;
    for (var i = 0; i < row.length; i++) {
      final char = row[i];
      if (char == '"') {
        if (quoted && i + 1 < row.length && row[i + 1] == '"') {
          current.write('"');
          i++;
        } else {
          quoted = !quoted;
        }
      } else if (char == delimiter && !quoted) {
        cells.add(current.toString());
        current.clear();
      } else {
        current.write(char);
      }
    }
    cells.add(current.toString());
    return cells;
  }

  /// O arquivo OFX é de cartão de crédito? (senão, de conta)
  static bool isCreditCardOfx(String content) =>
      RegExp(r'<(CREDITCARDMSGSRSV1|CCSTMTRS|CCACCTFROM)>', caseSensitive: false).hasMatch(content);

  /// Parser para arquivos OFX (Open Financial Exchange) padrão de bancos e cartões brasileiros
  static List<ImportedStatementLine> parseOfx(String ofxContent, {StatementSourceType? source}) {
    final raw = <_RawLine>[];

    // Localiza blocos <STMTTRN>...</STMTTRN>
    final trnMatches = RegExp(r'<STMTTRN>([\s\S]*?)<\/STMTTRN>', caseSensitive: false).allMatches(ofxContent);

    for (final match in trnMatches) {
      final block = match.group(1) ?? '';

      // Extrai DTPOSTED (ex: 20261010120000 ou 20261010)
      final dtMatch = RegExp(r'<DTPOSTED>(\d{4})(\d{2})(\d{2})', caseSensitive: false).firstMatch(block);
      final date = dtMatch == null
          ? null
          : _validDate(
              int.parse(dtMatch.group(1)!),
              int.parse(dtMatch.group(2)!),
              int.parse(dtMatch.group(3)!),
            );

      // Extrai TRNAMT (ex: -180.50 ou 180.50)
      final amtMatch = RegExp(r'<TRNAMT>\s*([-+\d.,]+)', caseSensitive: false).firstMatch(block);
      final cents = amtMatch == null ? null : parseSignedCents(amtMatch.group(1)!);
      if (date == null || cents == null || cents == 0) continue;

      String? tag(String name) => RegExp('<$name>([^\\r\\n<]+)', caseSensitive: false)
          .firstMatch(block)
          ?.group(1)
          ?.trim();
      final description = [tag('MEMO'), tag('NAME')]
          .where((text) => text != null && text.isNotEmpty)
          .firstOrNull;

      raw.add(_RawLine(date, description ?? 'Lançamento Fatura', cents, tag('FITID')));
    }

    final resolvedSource = source ??
        (isCreditCardOfx(ofxContent) ? StatementSourceType.creditCard : StatementSourceType.bankAccount);
    return _classify(raw, resolvedSource, positiveIsOutflowOnTie: false);
  }

  /// Detecta automaticamente se o arquivo é OFX ou CSV e processa as linhas
  static List<ImportedStatementLine> parseFile(
    String content, {
    String? filename,
    StatementSourceType? source,
  }) {
    final lowerName = filename?.toLowerCase() ?? '';
    if (lowerName.endsWith('.ofx') || content.contains('<OFX>') || content.contains('<STMTTRN>')) {
      return parseOfx(content, source: source);
    }
    return parseCsv(content, source: source ?? StatementSourceType.creditCard);
  }

  /// Decide o que cada linha é a partir do sinal do valor.
  ///
  /// Na conta, valor negativo é saída. No cartão o sinal muda de banco para
  /// banco, então vale o da maioria das linhas: compra é o que mais aparece.
  static List<ImportedStatementLine> _classify(
    List<_RawLine> raw,
    StatementSourceType source, {
    required bool positiveIsOutflowOnTie,
  }) {
    final positives = raw.where((l) => l.signedCents > 0).length;
    final negatives = raw.length - positives;

    final bool positiveIsOutflow;
    if (source == StatementSourceType.bankAccount) {
      // Arquivo sem sinal nenhum: tudo é saída
      positiveIsOutflow = negatives == 0;
    } else if (positives == negatives) {
      positiveIsOutflow = positiveIsOutflowOnTie;
    } else {
      positiveIsOutflow = positives > negatives;
    }

    final lines = <ImportedStatementLine>[];
    final seen = <String, int>{};
    for (var i = 0; i < raw.length; i++) {
      final line = raw[i];
      final isOutflow = (line.signedCents > 0) == positiveIsOutflow;
      final content = signatureContent(line.date, line.signedCents.abs(), line.description);
      final occurrence = seen[content] = (seen[content] ?? 0) + 1;

      final StatementLineKind kind;
      if (source == StatementSourceType.creditCard) {
        kind = isOutflow
            ? StatementLineKind.purchase
            : (_paymentWords.hasMatch(line.description)
                ? StatementLineKind.payment
                : StatementLineKind.refund);
      } else if (!isOutflow) {
        kind = StatementLineKind.income;
      } else {
        kind = _invoiceWords.hasMatch(line.description)
            ? StatementLineKind.payment
            : StatementLineKind.purchase;
      }

      final installment =
          kind == StatementLineKind.purchase ? StatementText.installmentOf(line.description) : null;

      lines.add(
        ImportedStatementLine(
          id: 'line_$i',
          date: line.date,
          description: line.description,
          amount: Money(line.signedCents.abs()),
          kind: kind,
          externalId: line.externalId,
          signature: '$content#$occurrence',
          installmentNumber: installment?.number,
          installmentsTotal: installment?.total,
          // Só compra vira lançamento; o resto fica de fora até alguém decidir
          destination: kind == StatementLineKind.purchase
              ? LineDestination.house
              : LineDestination.ignored,
        ),
      );
    }
    return lines;
  }

  /// Parte da assinatura que vem do conteúdo da linha. Duas linhas iguais no
  /// mesmo arquivo se distinguem pela ordem ("#1", "#2").
  static String signatureContent(DateTime date, int cents, String description) {
    final day = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    return '$day|$cents|${StatementText.normalize(description)}';
  }

  /// Calcula o fechamento da fatura com divisão matemática por destino (RN09)
  static InvoiceSplitResult calculateSplit(List<ImportedStatementLine> lines) {
    int totalCents = 0;
    int houseCents = 0;
    int personalOwnerCents = 0;
    final p2pMap = <String, int>{};

    for (final line in lines) {
      if (line.destination == LineDestination.ignored) continue;

      totalCents += line.amount.cents;

      switch (line.destination) {
        case LineDestination.house:
          houseCents += line.amount.cents;
          break;
        case LineDestination.cardOwnerPersonal:
          personalOwnerCents += line.amount.cents;
          break;
        case LineDestination.splitP2P:
          // Sem devedor escolhido a linha fica na chave vazia, à espera de um
          final debtor = line.assignedMemberId ?? '';
          p2pMap[debtor] = (p2pMap[debtor] ?? 0) + line.amount.cents;
          break;
        case LineDestination.ignored:
        case LineDestination.thirdParty:
          // Pago por terceiros: está na fatura, mas não é da casa nem de um morador
          break;
      }
    }

    final p2pMoneyMap = <String, Money>{};
    p2pMap.forEach((member, cents) {
      p2pMoneyMap[member] = Money(cents);
    });

    return InvoiceSplitResult(
      totalAmount: Money(totalCents),
      houseAmount: Money(houseCents),
      personalOwnerAmount: Money(personalOwnerCents),
      p2pDebtsByMember: p2pMoneyMap,
    );
  }
}
