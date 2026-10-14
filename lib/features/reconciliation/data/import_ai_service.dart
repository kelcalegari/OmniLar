import 'dart:convert';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/domain/value_objects/money.dart';
import '../../../core/errors/failures.dart';
import '../../../core/services/ai_config_service.dart';
import '../../finance/domain/entities/category.dart';
import '../domain/entities/imported_statement_line.dart';
import '../domain/services/statement_parser.dart';

/// Fatura ou extrato lido por IA a partir de um PDF ou de uma foto.
class AiStatementReading {
  final List<ImportedStatementLine> lines;
  final DateTime? dueDate;

  /// Total impresso no documento (null quando não aparece).
  final Money? printedTotal;

  /// Compras menos estornos das linhas lidas.
  final Money linesSum;
  final String? cardLastDigits;

  const AiStatementReading({
    required this.lines,
    required this.linesSum,
    this.dueDate,
    this.printedTotal,
    this.cardLastDigits,
  });

  /// A soma do que foi lido bate com o total impresso? Null quando o documento
  /// não traz total para conferir.
  bool? get sumMatchesTotal =>
      printedTotal == null ? null : printedTotal!.cents == linesSum.cents;

  /// Monta as linhas a partir da resposta da função `import-read`. Linha sem
  /// data, descrição ou valor válido é descartada.
  factory AiStatementReading.fromJson(Map<String, dynamic> json) {
    final lines = <ImportedStatementLine>[];
    final seen = <String, int>{};
    var sum = 0;

    for (final item in (json['lines'] as List?) ?? const []) {
      if (item is! Map) continue;
      final date = DateTime.tryParse(item['date']?.toString() ?? '');
      final cents = (item['amount_cents'] as num?)?.toInt() ?? 0;
      final description = item['description']?.toString().trim() ?? '';
      if (date == null || cents <= 0 || description.isEmpty) continue;

      final kind = switch (item['type']) {
        'refund' => StatementLineKind.refund,
        'payment' => StatementLineKind.payment,
        'income' => StatementLineKind.income,
        _ => StatementLineKind.purchase,
      };
      if (kind == StatementLineKind.purchase) sum += cents;
      if (kind == StatementLineKind.refund) sum -= cents;

      final day = DateTime(date.year, date.month, date.day);
      final content = StatementParser.signatureContent(day, cents, description);
      final occurrence = seen[content] = (seen[content] ?? 0) + 1;
      final number = (item['installment_number'] as num?)?.toInt();
      final total = (item['installments_total'] as num?)?.toInt();
      final isInstallment = number != null && total != null && total >= 2 && number >= 1 && number <= total;

      lines.add(
        ImportedStatementLine(
          id: 'line_${lines.length}',
          date: day,
          description: description,
          amount: Money(cents),
          kind: kind,
          signature: '$content#$occurrence',
          installmentNumber: isInstallment ? number : null,
          installmentsTotal: isInstallment ? total : null,
          destination: kind == StatementLineKind.purchase
              ? LineDestination.house
              : LineDestination.ignored,
        ),
      );
    }

    final printed = (json['total_cents'] as num?)?.toInt();
    return AiStatementReading(
      lines: lines,
      linesSum: Money(sum),
      dueDate: DateTime.tryParse(json['due_date']?.toString() ?? ''),
      printedTotal: printed != null && printed > 0 ? Money(printed) : null,
      cardLastDigits: json['card_last_digits'] as String?,
    );
  }
}

/// O que a IA sugere para uma linha: nome legível e categoria da casa.
typedef AiLineSuggestion = ({String? title, String? categoryId});

/// Leitura de PDF e foto e sugestão de categoria, pela função `import-read`.
/// A IA só propõe: tudo passa pela revisão antes de ser gravado.
class ImportAiService {
  final SupabaseClient? Function() getClient;
  final AiConfigService aiConfigService;
  final String? Function() getCurrentHouseId;
  final bool Function() isDemoMode;

  ImportAiService({
    required this.getClient,
    required this.aiConfigService,
    required this.getCurrentHouseId,
    required this.isDemoMode,
  });

  static const Map<String, String> mimeTypes = {
    'pdf': 'application/pdf',
    'png': 'image/png',
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'webp': 'image/webp',
  };

  /// Tipo do arquivo pela extensão, ou null se a IA não lê esse formato.
  static String? mimeTypeOf(String fileName) =>
      mimeTypes[fileName.toLowerCase().split('.').last];

  Future<Map<String, dynamic>> _invoke(Map<String, dynamic> body) async {
    final client = getClient();
    if (client == null || isDemoMode()) {
      throw const ServerFailure(
        'A leitura por IA não funciona no modo demo. Entre com sua conta ou use um arquivo OFX ou CSV.',
      );
    }

    final userApiKey = await aiConfigService.getUserApiKey();
    final userModel = await aiConfigService.getSelectedModel();
    try {
      final response = await client.functions.invoke(
        'import-read',
        body: {
          ...body,
          'houseId': ?getCurrentHouseId(),
          if (userApiKey != null && userApiKey.isNotEmpty) 'userApiKey': userApiKey,
          'userModel': userModel,
        },
      );
      final data = response.data;
      if (data is Map<String, dynamic> && data['success'] == true) return data;
      throw ServerFailure(
        (data is Map ? data['error'] as String? : null) ?? 'A IA não conseguiu ler o arquivo.',
      );
    } on FunctionException catch (e) {
      final details = e.details;
      throw ServerFailure(
        (details is Map ? details['error'] as String? : null) ??
            'A leitura por IA falhou (${e.status}). Tente de novo ou use um arquivo OFX ou CSV.',
      );
    }
  }

  Future<AiStatementReading> readFile({
    required Uint8List bytes,
    required String mimeType,
    required StatementSourceType source,
  }) async {
    final data = await _invoke({
      'mode': 'read',
      'fileBase64': base64Encode(bytes),
      'mimeType': mimeType,
      'sourceType': source == StatementSourceType.creditCard ? 'credit_card' : 'bank_statement',
    });
    final reading = AiStatementReading.fromJson(
      (data['reading'] as Map?)?.cast<String, dynamic>() ?? const {},
    );
    if (reading.lines.isEmpty) {
      throw const ServerFailure('Nenhum lançamento encontrado no arquivo.');
    }
    return reading;
  }

  /// Sugestões por id da linha. Linha sem sugestão não aparece no resultado.
  Future<Map<String, AiLineSuggestion>> classify({
    required List<ImportedStatementLine> lines,
    required List<ExpenseCategory> categories,
  }) async {
    if (lines.isEmpty) return const {};
    final data = await _invoke({
      'mode': 'classify',
      'lines': [
        for (final line in lines) {'id': line.id, 'description': line.description},
      ],
      'categories': [
        for (final category in categories) {'id': category.id, 'name': category.name},
      ],
    });
    return parseSuggestions(data['items'], {for (final c in categories) c.id});
  }

  /// Lê a resposta da classificação, descartando categoria que não é da casa.
  static Map<String, AiLineSuggestion> parseSuggestions(Object? items, Set<String> categoryIds) {
    final result = <String, AiLineSuggestion>{};
    for (final item in items is List ? items : const []) {
      if (item is! Map || item['id'] is! String) continue;
      final title = (item['title'] as String?)?.trim();
      final categoryId = item['category_id'] as String?;
      final suggestion = (
        title: title == null || title.isEmpty ? null : title,
        categoryId: categoryIds.contains(categoryId) ? categoryId : null,
      );
      if (suggestion.title == null && suggestion.categoryId == null) continue;
      result[item['id'] as String] = suggestion;
    }
    return result;
  }
}
