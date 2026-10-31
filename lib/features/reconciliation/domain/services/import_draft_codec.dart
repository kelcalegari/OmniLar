import '../../../../core/domain/value_objects/money.dart';
import '../../../finance/domain/entities/payment_method.dart';
import '../entities/imported_statement_line.dart';
import 'import_session.dart';

/// Rascunho da revisão de uma importação: o que o usuário já decidiu, para
/// retomar depois. O que vem do app (despesas parecidas, ciclos fechados,
/// importações anteriores) não é guardado: é buscado de novo ao retomar.
class ImportDraftCodec {
  const ImportDraftCodec._();

  static const int version = 1;

  static T? _enum<T extends Enum>(List<T> values, Object? name) =>
      values.where((v) => v.name == name).firstOrNull;

  static Map<String, dynamic> lineToJson(ImportedStatementLine line) => {
        'id': line.id,
        'date': line.date.toIso8601String(),
        'description': line.description,
        'amount': line.amount.cents,
        'destination': line.destination.name,
        'kind': line.kind.name,
        'externalId': ?line.externalId,
        'signature': ?line.signature,
        'title': ?line.title,
        'note': ?line.note,
        'categoryId': ?line.categoryId,
        'assignedMemberId': ?line.assignedMemberId,
        'installmentNumber': ?line.installmentNumber,
        'installmentsTotal': ?line.installmentsTotal,
        'splitFrom': ?line.splitFrom,
      };

  static ImportedStatementLine lineFromJson(Map<String, dynamic> json) => ImportedStatementLine(
        id: json['id'] as String,
        date: DateTime.parse(json['date'] as String),
        description: json['description'] as String,
        amount: Money((json['amount'] as num).toInt()),
        destination: _enum(LineDestination.values, json['destination']) ?? LineDestination.house,
        kind: _enum(StatementLineKind.values, json['kind']) ?? StatementLineKind.purchase,
        externalId: json['externalId'] as String?,
        signature: json['signature'] as String?,
        title: json['title'] as String?,
        note: json['note'] as String?,
        categoryId: json['categoryId'] as String?,
        assignedMemberId: json['assignedMemberId'] as String?,
        installmentNumber: (json['installmentNumber'] as num?)?.toInt(),
        installmentsTotal: (json['installmentsTotal'] as num?)?.toInt(),
        splitFrom: json['splitFrom'] as String?,
      );

  static Map<String, dynamic> toJson(ImportSession session) => {
        'version': version,
        'sourceId': session.source.id,
        'fileName': session.fileName,
        'payerMemberId': session.payerMemberId,
        'invoiceDueDate': ?session.invoiceDueDate?.toIso8601String(),
        'invoicePaidAt': ?session.invoicePaidAt?.toIso8601String(),
        'invoicePaidByHouse': session.invoicePaidByHouse,
        'lines': [for (final line in session.lines) lineToJson(line)],
        'decisions': {for (final e in session.decisions.entries) e.key: e.value.name},
        'decisionTargets': session.decisionTargets,
        'forcedLineIds': session.forcedLineIds.toList(),
        'extraChoices': session.extraChoices,
        'refundChoices': session.refundChoices,
        'ruledLineIds': session.ruledLineIds.toList(),
        'forecastInstallments': session.forecastInstallments,
        'installmentPrefilledIds': session.installmentPrefilledIds.toList(),
        'prepaymentChoices': session.prepaymentChoices,
      };

  /// Monta a revisão de volta. Null se o rascunho for de outra versão ou de
  /// outro cartão ou conta.
  static ImportSession? fromJson(Map<String, dynamic> json, PaymentMethod source) {
    try {
      if (json['version'] != version || json['sourceId'] != source.id) return null;
      Map<String, String> strings(Object? value) =>
          {for (final e in ((value as Map?) ?? const {}).entries) e.key as String: e.value as String};

      return ImportSession(
        source: source,
        fileName: json['fileName'] as String,
        payerMemberId: json['payerMemberId'] as String,
        invoiceDueDate: DateTime.tryParse(json['invoiceDueDate'] as String? ?? ''),
        invoicePaidAt: DateTime.tryParse(json['invoicePaidAt'] as String? ?? ''),
        invoicePaidByHouse: json['invoicePaidByHouse'] as bool? ?? false,
        lines: [
          for (final line in json['lines'] as List) lineFromJson((line as Map).cast<String, dynamic>()),
        ],
        decisions: {
          for (final e in strings(json['decisions']).entries)
            if (_enum(MatchDecision.values, e.value) != null) e.key: _enum(MatchDecision.values, e.value)!,
        },
        decisionTargets: strings(json['decisionTargets']),
        forcedLineIds: {for (final id in (json['forcedLineIds'] as List? ?? const [])) id as String},
        extraChoices: strings(json['extraChoices']),
        refundChoices: strings(json['refundChoices']),
        ruledLineIds: {for (final id in (json['ruledLineIds'] as List? ?? const [])) id as String},
        forecastInstallments: json['forecastInstallments'] as bool? ?? true,
        prepaymentChoices: strings(json['prepaymentChoices']),
        installmentPrefilledIds: {
          for (final id in (json['installmentPrefilledIds'] as List? ?? const [])) id as String,
        },
      );
    } catch (_) {
      return null;
    }
  }
}
