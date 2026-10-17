import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/offline/offline_banner.dart';
import 'package:omni_lar/core/offline/offline_snapshot.dart';

class _MemoryStorage implements SnapshotStorage {
  final map = <String, String>{};

  @override
  Future<String?> read(String key) async => map[key];

  @override
  Future<void> write(String key, String value) async => map[key] = value;

  @override
  Future<void> delete(String key) async => map.remove(key);

  @override
  Future<Iterable<String>> keys() async => map.keys.toList();
}

void main() {
  late _MemoryStorage storage;
  late OfflineSnapshot snapshot;
  var userId = 'user_a';

  setUp(() {
    storage = _MemoryStorage();
    userId = 'user_a';
    snapshot = OfflineSnapshot(storage: storage, currentUserId: () => userId);
  });

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('Com rede, devolve e guarda; sem rede, devolve a cópia e acende a faixa', () async {
    final online = await snapshot.rows('items', () async => [
          {'id': '1', 'name': 'Café', 'quantity': 2}
        ]);
    await settle();
    expect(online.single['name'], 'Café');
    expect(snapshot.showingSince.value, isNull);

    final offline = await snapshot.rows('items', () async => throw Exception('sem rede'));
    expect(offline.single['name'], 'Café');
    expect(offline.single['quantity'], 2);
    expect(snapshot.showingSince.value, isNotNull);

    // A rede voltou: a faixa apaga
    await snapshot.rows('items', () async => [
          {'id': '1', 'name': 'Café'}
        ]);
    expect(snapshot.showingSince.value, isNull);
  });

  test('Sem cópia e sem rede, o erro segue adiante', () async {
    expect(() => snapshot.rows('nada', () async => throw Exception('sem rede')), throwsException);
  });

  test('A cópia é de cada conta e sai ao sair da conta', () async {
    await snapshot.row('profile', () async => {'full_name': 'Ana'});
    await settle();

    userId = 'user_b';
    expect(() => snapshot.row('profile', () async => throw Exception('sem rede')), throwsException);

    userId = 'user_a';
    expect((await snapshot.row('profile', () async => throw Exception('sem rede')))?['full_name'], 'Ana');

    await snapshot.clearAll();
    expect(storage.map, isEmpty);
    expect(snapshot.showingSince.value, isNull);
  });

  testWidgets('A faixa aparece só enquanto a cópia está em uso', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: OfflineBanner(snapshot: snapshot, child: const Scaffold(body: Text('Casa'))),
    ));
    expect(find.textContaining('Sem internet'), findsNothing);

    snapshot.showingSince.value = DateTime(2026, 10, 17, 14, 32);
    await tester.pump();
    expect(find.text('Sem internet — mostrando os dados de 17/10 às 14:32'), findsOneWidget);
    expect(find.text('Casa'), findsOneWidget);
  });
}
