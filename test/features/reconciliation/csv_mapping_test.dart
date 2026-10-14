import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/features/reconciliation/data/csv_mapping_store.dart';
import 'package:omni_lar/features/reconciliation/domain/entities/csv_mapping.dart';
import 'package:omni_lar/features/reconciliation/domain/entities/imported_statement_line.dart';
import 'package:omni_lar/features/reconciliation/domain/services/statement_parser.dart';
import 'package:omni_lar/features/reconciliation/presentation/widgets/csv_mapping_dialog.dart';

// Extrato com débito e crédito em colunas separadas e data no meio
const _bankCsv = '''
Conta corrente;Agência 1234
Lançamento;Data;Documento;Débito;Crédito;Saldo
PIX ENVIADO PADARIA;03/10/2026;0001;25,00;;1.000,00
PIX RECEBIDO CRISTIANO;04/10/2026;0002;;200,00;1.200,00
PAGTO FATURA NUBANK;09/10/2026;0003;1.482,40;;-282,40
''';

// Arquivo sem cabeçalho em que a descrição vem depois de um código numérico
const _oddCsv = '''
12345|05/10/2026|MERCADO BOM PRECO|R\$ 150,90|ok
12346|06/10/2026|POSTO SHELL|R\$ 80,00|ok
''';

void main() {
  group('Mapeamento de colunas', () {
    test('palpite pelo cabeçalho reconhece débito e crédito separados', () {
      final guess = StatementParser.guessCsvMapping(_bankCsv);

      expect(guess.delimiter, ';');
      // A primeira linha é o nome da conta, não o cabeçalho das colunas
      expect(guess.hasHeader, isFalse);
      expect(guess.roles, hasLength(6));
    });

    test('lê débito como saída e crédito como entrada, pulando o que não tem data', () {
      const mapping = CsvMapping(
        delimiter: ';',
        hasHeader: true,
        roles: [
          CsvColumnRole.description,
          CsvColumnRole.date,
          CsvColumnRole.ignore,
          CsvColumnRole.debit,
          CsvColumnRole.credit,
          CsvColumnRole.ignore,
        ],
      );
      final lines = StatementParser.parseCsvWithMapping(
        _bankCsv,
        mapping,
        source: StatementSourceType.bankAccount,
      );

      expect(lines, hasLength(3));
      expect(lines[0].description, 'PIX ENVIADO PADARIA');
      expect(lines[0].amount.cents, 2500);
      expect(lines[0].kind, StatementLineKind.purchase);
      expect(lines[1].kind, StatementLineKind.income);
      expect(lines[1].amount.cents, 20000);
      expect(lines[2].kind, StatementLineKind.payment);
      expect(lines[2].amount.cents, 148240);
    });

    test('arquivo sem cabeçalho e com separador incomum, com as colunas escolhidas', () {
      const mapping = CsvMapping(
        delimiter: '|',
        hasHeader: false,
        roles: [
          CsvColumnRole.ignore,
          CsvColumnRole.date,
          CsvColumnRole.description,
          CsvColumnRole.amount,
          CsvColumnRole.ignore,
        ],
      );
      final lines = StatementParser.parseCsvWithMapping(_oddCsv, mapping);

      expect(lines.map((l) => l.description), ['MERCADO BOM PRECO', 'POSTO SHELL']);
      expect(lines.map((l) => l.amount.cents), [15090, 8000]);
      expect(lines.every((l) => l.signature != null), isTrue);
    });

    test('reconhece o separador "|" sozinho', () {
      final guess = StatementParser.guessCsvMapping(_oddCsv);
      expect(guess.delimiter, '|');
      expect(guess.roles.take(4), [
        CsvColumnRole.ignore,
        CsvColumnRole.date,
        CsvColumnRole.description,
        CsvColumnRole.amount,
      ]);
      expect(StatementParser.parseCsv(_oddCsv), hasLength(2));
    });

    test('a prévia deixa todas as linhas com o mesmo número de colunas', () {
      final preview = StatementParser.csvPreview(_bankCsv);
      expect(preview.map((row) => row.length).toSet(), {6});
      expect(preview[1][1], 'Data');
    });

    test('data, descrição e valor são únicos; valor e débito/crédito não convivem', () {
      var mapping = const CsvMapping(
        delimiter: ';',
        hasHeader: true,
        roles: [CsvColumnRole.date, CsvColumnRole.ignore, CsvColumnRole.amount, CsvColumnRole.ignore],
      );
      mapping = mapping.withRole(1, CsvColumnRole.date);
      expect(mapping.roles, [CsvColumnRole.ignore, CsvColumnRole.date, CsvColumnRole.amount, CsvColumnRole.ignore]);

      mapping = mapping.withRole(3, CsvColumnRole.debit);
      expect(mapping.roles[2], CsvColumnRole.ignore);
      expect(mapping.missing, 'Escolha a coluna da descrição.');

      mapping = mapping.withRole(0, CsvColumnRole.description);
      expect(mapping.isComplete, isTrue);
      expect(CsvMapping.fromJson(mapping.toJson())!.roles, mapping.roles);
    });

    test('guarda o mapeamento por cartão ou conta mesmo sem armazenamento', () async {
      final store = CsvMappingStore();
      const mapping = CsvMapping(delimiter: '|', hasHeader: false, roles: [CsvColumnRole.date]);
      await store.save('pm_1', mapping);

      expect((await store.load('pm_1'))!.delimiter, '|');
      expect(await store.load('pm_2'), isNull);
    });
  });

  testWidgets('a tela de colunas só confirma quando acha lançamentos', (tester) async {
    tester.view.physicalSize = const Size(1200, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    CsvMapping? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await CsvMappingDialog.show(
                context,
                content: _oddCsv,
                fileName: 'banco.csv',
                initial: const CsvMapping(delimiter: '|', hasHeader: false, roles: []),
                source: StatementSourceType.creditCard,
              );
            },
            child: const Text('abrir'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    FilledButton confirm() => tester.widget<FilledButton>(find.byKey(const Key('csv_mapping_confirm')));
    expect(find.text('Escolha a coluna da data.'), findsOneWidget);
    expect(confirm().onPressed, isNull);

    Future<void> choose(int column, String label) async {
      // A tabela rola na horizontal: a coluna pode estar fora da vista
      await tester.ensureVisible(find.byKey(Key('csv_column_$column')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('csv_column_$column')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
    }

    await choose(1, 'Data');
    await choose(2, 'Descrição');
    await choose(3, 'Valor');

    expect(find.text('2 lançamentos encontrados.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('csv_mapping_confirm')));
    await tester.pumpAndSettle();

    expect(result!.roles.take(4), [
      CsvColumnRole.ignore,
      CsvColumnRole.date,
      CsvColumnRole.description,
      CsvColumnRole.amount,
    ]);
  });
}
