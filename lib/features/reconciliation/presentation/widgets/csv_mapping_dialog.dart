import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/entities/csv_mapping.dart';
import '../../domain/entities/imported_statement_line.dart';
import '../../domain/services/statement_parser.dart';

/// Mostra as primeiras linhas de um CSV para o usuário dizer o que é cada
/// coluna. Devolve o mapeamento escolhido, ou null se cancelar.
class CsvMappingDialog extends StatefulWidget {
  final String content;
  final String fileName;
  final CsvMapping initial;
  final StatementSourceType source;

  const CsvMappingDialog({
    super.key,
    required this.content,
    required this.fileName,
    required this.initial,
    required this.source,
  });

  static Future<CsvMapping?> show(
    BuildContext context, {
    required String content,
    required String fileName,
    required CsvMapping initial,
    required StatementSourceType source,
  }) =>
      showDialog<CsvMapping>(
        context: context,
        builder: (_) => CsvMappingDialog(
          content: content,
          fileName: fileName,
          initial: initial,
          source: source,
        ),
      );

  @override
  State<CsvMappingDialog> createState() => _CsvMappingDialogState();
}

class _CsvMappingDialogState extends State<CsvMappingDialog> {
  late CsvMapping _mapping = _fitted(widget.initial);

  static const _labels = {
    CsvColumnRole.ignore: 'Ignorar',
    CsvColumnRole.date: 'Data',
    CsvColumnRole.description: 'Descrição',
    CsvColumnRole.amount: 'Valor',
    CsvColumnRole.debit: 'Débito (saída)',
    CsvColumnRole.credit: 'Crédito (entrada)',
  };

  static const _delimiters = {',': 'Vírgula', ';': 'Ponto e vírgula', '\t': 'Tabulação', '|': 'Barra vertical'};

  List<List<String>> get _preview =>
      StatementParser.csvPreview(widget.content, delimiter: _mapping.delimiter, rows: 7);

  /// Um papel por coluna do arquivo, mesmo que o mapeamento salvo seja de
  /// um arquivo com outro número de colunas.
  CsvMapping _fitted(CsvMapping mapping) {
    final preview =
        StatementParser.csvPreview(widget.content, delimiter: mapping.delimiter, rows: 7);
    final width = preview.isEmpty ? 0 : preview.first.length;
    return mapping.copyWith(
      roles: [
        for (var i = 0; i < width; i++) i < mapping.roles.length ? mapping.roles[i] : CsvColumnRole.ignore,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preview = _preview;
    final width = preview.isEmpty ? 0 : preview.first.length;
    final found = _mapping.isComplete
        ? StatementParser.parseCsvWithMapping(widget.content, _mapping, source: widget.source).length
        : 0;
    final missing = _mapping.missing;

    return AlertDialog(
      title: const Text('Colunas do arquivo', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
      content: SizedBox(
        width: 720,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Diga o que é cada coluna de "${widget.fileName}". O app guarda essa escolha '
                'neste aparelho e lê assim os próximos arquivos deste cartão ou conta.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 16,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Separador: ', style: TextStyle(fontSize: 13)),
                      DropdownButton<String>(
                        value: _mapping.delimiter,
                        isDense: true,
                        underline: const SizedBox.shrink(),
                        onChanged: (delimiter) {
                          if (delimiter == null) return;
                          setState(() => _mapping = _fitted(
                                CsvMapping(delimiter: delimiter, hasHeader: _mapping.hasHeader, roles: const []),
                              ));
                        },
                        items: [
                          // Separador guardado que não está na lista continua escolhível
                          if (!_delimiters.containsKey(_mapping.delimiter))
                            DropdownMenuItem(
                              value: _mapping.delimiter,
                              child: Text('"${_mapping.delimiter}"', style: const TextStyle(fontSize: 13)),
                            ),
                          for (final entry in _delimiters.entries)
                            DropdownMenuItem(
                              value: entry.key,
                              child: Text(entry.value, style: const TextStyle(fontSize: 13)),
                            ),
                        ],
                      ),
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Switch(
                        value: _mapping.hasHeader,
                        onChanged: (value) => setState(() => _mapping = _mapping.copyWith(hasHeader: value)),
                      ),
                      const Text('A primeira linha é o cabeçalho', style: TextStyle(fontSize: 13)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Table(
                  defaultColumnWidth: const IntrinsicColumnWidth(),
                  border: TableBorder.all(color: theme.dividerColor),
                  children: [
                    TableRow(
                      decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.08)),
                      children: [
                        for (var column = 0; column < width; column++)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            child: DropdownButton<CsvColumnRole>(
                              key: Key('csv_column_$column'),
                              value: _mapping.roles[column],
                              isDense: true,
                              underline: const SizedBox.shrink(),
                              onChanged: (role) {
                                if (role != null) setState(() => _mapping = _mapping.withRole(column, role));
                              },
                              items: [
                                for (final role in CsvColumnRole.values)
                                  DropdownMenuItem(
                                    value: role,
                                    child: Text(
                                      _labels[role]!,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: role == CsvColumnRole.ignore ? null : FontWeight.bold,
                                        color: role == CsvColumnRole.ignore ? Colors.grey : AppColors.primary,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    for (var row = 0; row < preview.length; row++)
                      TableRow(
                        children: [
                          for (var column = 0; column < width; column++)
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              child: Text(
                                preview[row][column],
                                style: TextStyle(
                                  fontSize: 12,
                                  color: (row == 0 && _mapping.hasHeader) ||
                                          _mapping.roles[column] == CsvColumnRole.ignore
                                      ? Colors.grey
                                      : null,
                                  fontWeight: row == 0 && _mapping.hasHeader ? FontWeight.bold : null,
                                ),
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                missing ??
                    (found == 0
                        ? 'Nenhuma linha com data e valor nessas colunas.'
                        : '$found ${found == 1 ? 'lançamento encontrado' : 'lançamentos encontrados'}.'),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: missing == null && found > 0 ? AppColors.creditGreen : AppColors.debtRed,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          key: const Key('csv_mapping_confirm'),
          onPressed: missing == null && found > 0 ? () => Navigator.pop(context, _mapping) : null,
          child: const Text('Usar estas colunas'),
        ),
      ],
    );
  }
}
