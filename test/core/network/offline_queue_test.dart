import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:omni_lar/core/network/offline_queue.dart';

void main() {
  group('OfflineQueueManager (Tolerância Offline & Idempotência)', () {
    late OfflineQueueManager queue;

    setUp(() {
      queue = OfflineQueueManager();
    });

    tearDown(() {
      queue.dispose();
    });

    test('Enfileira ações com IDs únicos e payload preservado', () {
      expect(queue.pendingActions, isEmpty);

      queue.enqueue(OfflineActionType.addExpense, {'title': 'Padaria', 'cents': 3500});
      queue.enqueue(OfflineActionType.addShoppingItem, {'name': 'Café', 'quantity': 1.0});

      expect(queue.pendingActions.length, 2);
      expect(queue.pendingActions.first.type, OfflineActionType.addExpense);
      expect(queue.pendingActions.first.payload['cents'], 3500);
      expect(queue.pendingActions.last.type, OfflineActionType.addShoppingItem);
      expect(queue.pendingActions.last.payload['name'], 'Café');
    });

    test('Remove ação enfileirada após sincronização com sucesso', () {
      queue.enqueue(OfflineActionType.addTask, {'title': 'Lavar louça'});
      final actionId = queue.pendingActions.first.id;

      queue.remove(actionId);
      expect(queue.pendingActions, isEmpty);
    });

    test('Limpa fila completamente', () {
      queue.enqueue(OfflineActionType.addExpense, {'cents': 1000});
      queue.enqueue(OfflineActionType.addExpense, {'cents': 2000});
      expect(queue.pendingActions.length, 2);

      queue.clear();
      expect(queue.pendingActions, isEmpty);
    });

    test('Serializa para JSON e restaura fila preservando integridade das mutações', () {
      queue.enqueue(OfflineActionType.addExpense, {'title': 'Feira', 'cents': 4200});
      queue.enqueue(OfflineActionType.payInstallment, {'loanId': 'l1', 'cents': 1500});

      final dumped = queue.dumpToJson();
      expect(dumped.length, 2);
      expect(dumped[0]['type'], 'addExpense');
      expect(dumped[0]['payload']['cents'], 4200);

      final newQueue = OfflineQueueManager();
      newQueue.restoreFromJson(dumped);

      expect(newQueue.pendingActions.length, 2);
      expect(newQueue.pendingActions[0].type, OfflineActionType.addExpense);
      expect(newQueue.pendingActions[0].payload['title'], 'Feira');
      expect(newQueue.pendingActions[1].type, OfflineActionType.payInstallment);
      expect(newQueue.pendingActions[1].payload['cents'], 1500);

      newQueue.dispose();
    });

    test('Persiste e restaura do FlutterSecureStorage criptografado', () async {
      final inMemoryStorage = <String, String>{};
      final mockStorage = MockFlutterSecureStorage();

      when(() => mockStorage.read(key: any(named: 'key'))).thenAnswer(
        (invocation) async => inMemoryStorage[invocation.namedArguments[#key] as String],
      );
      when(() => mockStorage.write(key: any(named: 'key'), value: any(named: 'value'))).thenAnswer(
        (invocation) async {
          inMemoryStorage[invocation.namedArguments[#key] as String] =
              invocation.namedArguments[#value] as String;
        },
      );
      when(() => mockStorage.delete(key: any(named: 'key'))).thenAnswer(
        (invocation) async {
          inMemoryStorage.remove(invocation.namedArguments[#key] as String);
        },
      );

      final queueWithStorage = OfflineQueueManager(mockStorage);
      await queueWithStorage.init();
      expect(queueWithStorage.pendingActions, isEmpty);

      queueWithStorage.enqueue(OfflineActionType.addExpense, {'title': 'Mercado Central', 'cents': 9800});
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(inMemoryStorage.containsKey(OfflineQueueManager.storageKey), isTrue);

      // Simula reinicialização do app recarregando nova instância
      final restartedQueue = OfflineQueueManager(mockStorage);
      await restartedQueue.init();

      expect(restartedQueue.pendingActions.length, 1);
      expect(restartedQueue.pendingActions.first.type, OfflineActionType.addExpense);
      expect(restartedQueue.pendingActions.first.payload['title'], 'Mercado Central');
      expect(restartedQueue.pendingActions.first.payload['cents'], 9800);

      restartedQueue.clear();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(inMemoryStorage.containsKey(OfflineQueueManager.storageKey), isFalse);

      queueWithStorage.dispose();
      restartedQueue.dispose();
    });
  });
}

class MockFlutterSecureStorage extends Mock implements FlutterSecureStorage {}

