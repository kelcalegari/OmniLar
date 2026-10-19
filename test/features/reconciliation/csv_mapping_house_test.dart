import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:omni_lar/features/reconciliation/data/csv_mapping_store.dart';
import 'package:omni_lar/features/reconciliation/domain/entities/csv_mapping.dart';

class _MockStorage extends Mock implements FlutterSecureStorage {}

/// Armazenamento do aparelho com [values] já guardados.
FlutterSecureStorage _storageWith(Map<String, String> values) {
  final storage = _MockStorage();
  when(() => storage.read(key: any(named: 'key'))).thenAnswer((i) async => values[i.namedArguments[#key]]);
  when(() => storage.write(key: any(named: 'key'), value: any(named: 'value'))).thenAnswer((i) async {
    values[i.namedArguments[#key] as String] = i.namedArguments[#value] as String;
  });
  return storage;
}

class _FakeRemote implements CsvMappingRemote {
  Map<String, String>? stored;
  String? house = 'casa_1';
  bool failLoad = false;
  bool failSave = false;
  int loads = 0;
  final saved = <String, String>{};

  _FakeRemote([this.stored]);

  @override
  String? get houseKey => house;

  @override
  Future<Map<String, String>?> loadAll() async {
    loads++;
    if (failLoad) throw Exception('sem conexão');
    return stored;
  }

  @override
  Future<void> save(String paymentMethodId, String mappingJson) async {
    if (failSave) throw Exception('sem conexão');
    saved[paymentMethodId] = mappingJson;
    stored = {...?stored, paymentMethodId: mappingJson};
  }
}

const _pipe = CsvMapping(
  delimiter: '|',
  hasHeader: false,
  roles: [CsvColumnRole.ignore, CsvColumnRole.date, CsvColumnRole.description, CsvColumnRole.amount],
);
const _semi = CsvMapping(
  delimiter: ';',
  hasHeader: true,
  roles: [CsvColumnRole.date, CsvColumnRole.description, CsvColumnRole.amount],
);

void main() {
  test('o mapeamento da casa vale em outro aparelho', () async {
    final remote = _FakeRemote({'pm_1': _pipe.toJson()});
    final store = CsvMappingStore(null, remote);

    final loaded = await store.load('pm_1');
    expect(loaded!.delimiter, '|');
    expect(loaded.roles, _pipe.roles);
    expect(await store.load('pm_2'), isNull);
    expect(remote.loads, 1);
  });

  test('ao salvar, vai para a casa e o outro aparelho lê', () async {
    final remote = _FakeRemote({});
    await CsvMappingStore(null, remote).save('pm_1', _semi);

    expect(remote.saved['pm_1'], _semi.toJson());
    final other = CsvMappingStore(null, remote);
    expect((await other.load('pm_1'))!.delimiter, ';');
  });

  test('sem conexão com a casa, segue com o da memória e não perde o salvamento', () async {
    final remote = _FakeRemote()
      ..failLoad = true
      ..failSave = true;
    final store = CsvMappingStore(null, remote);

    await store.save('pm_1', _semi);
    expect((await store.load('pm_1'))!.delimiter, ';');
    expect(remote.saved, isEmpty);
    // Outro pm: tenta ler a casa de novo na próxima vez
    expect(await store.load('pm_9'), isNull);
    final before = remote.loads;
    await store.load('pm_8');
    expect(remote.loads, greaterThan(before));
  });

  test('sem o mapeamento da casa vale o do aparelho e ele é enviado à casa', () async {
    final remote = _FakeRemote({});
    final store = CsvMappingStore(_storageWith({'omnilar_csv_mapping_pm_1': _pipe.toJson()}), remote);

    final loaded = await store.load('pm_1');
    expect(loaded!.delimiter, '|');
    expect(remote.saved['pm_1'], _pipe.toJson());
  });

  test('o da casa vence o do aparelho', () async {
    final remote = _FakeRemote({'pm_1': _semi.toJson()});
    final store = CsvMappingStore(_storageWith({'omnilar_csv_mapping_pm_1': _pipe.toJson()}), remote);

    expect((await store.load('pm_1'))!.delimiter, ';');
    expect(remote.saved, isEmpty);
  });

  test('banco sem a coluna ou demo (remoto nulo) usa só o aparelho', () async {
    final remote = _FakeRemote(null);
    final store = CsvMappingStore(_storageWith({'omnilar_csv_mapping_pm_1': _pipe.toJson()}), remote);

    expect((await store.load('pm_1'))!.delimiter, '|');
    expect(remote.saved, isEmpty);
  });

  test('trocar de casa lê os mapeamentos da outra', () async {
    final remote = _FakeRemote({'pm_1': _pipe.toJson()});
    final store = CsvMappingStore(null, remote);
    await store.load('pm_x');

    remote
      ..house = 'casa_2'
      ..stored = {'pm_2': _semi.toJson()};
    expect((await store.load('pm_2'))!.delimiter, ';');
    expect(remote.loads, 2);
  });
}
