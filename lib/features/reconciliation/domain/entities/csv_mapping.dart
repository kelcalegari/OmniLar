import 'dart:convert';

/// O que cada coluna de um CSV significa. Cada banco exporta de um jeito; o
/// usuário diz uma vez e o app guarda para aquele cartão ou conta.
enum CsvColumnRole { ignore, date, description, amount, debit, credit }

class CsvMapping {
  final String delimiter;

  /// A primeira linha com conteúdo é cabeçalho (nomes das colunas).
  final bool hasHeader;

  /// Papel de cada coluna, na ordem do arquivo.
  final List<CsvColumnRole> roles;

  const CsvMapping({
    required this.delimiter,
    required this.hasHeader,
    required this.roles,
  });

  int? indexOf(CsvColumnRole role) {
    final index = roles.indexOf(role);
    return index < 0 ? null : index;
  }

  /// Dá para ler o arquivo: data, descrição e o valor (numa coluna, ou em
  /// colunas de débito e crédito).
  bool get isComplete =>
      indexOf(CsvColumnRole.date) != null &&
      indexOf(CsvColumnRole.description) != null &&
      (indexOf(CsvColumnRole.amount) != null ||
          indexOf(CsvColumnRole.debit) != null ||
          indexOf(CsvColumnRole.credit) != null);

  /// O que falta escolher, para a tela dizer.
  String? get missing {
    if (indexOf(CsvColumnRole.date) == null) return 'Escolha a coluna da data.';
    if (indexOf(CsvColumnRole.description) == null) return 'Escolha a coluna da descrição.';
    if (!isComplete) return 'Escolha a coluna do valor (ou as de débito e crédito).';
    return null;
  }

  CsvMapping copyWith({String? delimiter, bool? hasHeader, List<CsvColumnRole>? roles}) => CsvMapping(
        delimiter: delimiter ?? this.delimiter,
        hasHeader: hasHeader ?? this.hasHeader,
        roles: roles ?? this.roles,
      );

  /// Troca o papel de uma coluna. Data, descrição e valor são únicos: a coluna
  /// que tinha o papel antes passa a ser ignorada.
  CsvMapping withRole(int column, CsvColumnRole role) {
    final updated = [
      for (var i = 0; i < roles.length; i++)
        role != CsvColumnRole.ignore && roles[i] == role && i != column ? CsvColumnRole.ignore : roles[i],
    ];
    updated[column] = role;
    // Valor numa coluna só não convive com débito e crédito separados
    if (role == CsvColumnRole.amount) {
      for (var i = 0; i < updated.length; i++) {
        if (updated[i] == CsvColumnRole.debit || updated[i] == CsvColumnRole.credit) {
          updated[i] = CsvColumnRole.ignore;
        }
      }
    } else if (role == CsvColumnRole.debit || role == CsvColumnRole.credit) {
      for (var i = 0; i < updated.length; i++) {
        if (updated[i] == CsvColumnRole.amount) updated[i] = CsvColumnRole.ignore;
      }
    }
    return copyWith(roles: updated);
  }

  String toJson() => jsonEncode({
        'delimiter': delimiter,
        'hasHeader': hasHeader,
        'roles': [for (final role in roles) role.name],
      });

  static CsvMapping? fromJson(String? text) {
    if (text == null || text.isEmpty) return null;
    try {
      final json = jsonDecode(text) as Map<String, dynamic>;
      return CsvMapping(
        delimiter: json['delimiter'] as String,
        hasHeader: json['hasHeader'] as bool,
        roles: [
          for (final name in json['roles'] as List)
            CsvColumnRole.values.firstWhere((r) => r.name == name, orElse: () => CsvColumnRole.ignore),
        ],
      );
    } catch (_) {
      return null;
    }
  }
}
