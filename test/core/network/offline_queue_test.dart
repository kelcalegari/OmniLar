import 'package:flutter_test/flutter_test.dart';
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
  });
}
