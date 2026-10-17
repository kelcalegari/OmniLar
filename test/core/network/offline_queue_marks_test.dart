import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/network/offline_queue.dart';
import 'package:omni_lar/core/network/offline_sync_service.dart';
import 'package:omni_lar/features/calendar/data/datasources/mock_calendar_datasource.dart';
import 'package:omni_lar/features/calendar/data/repositories/calendar_repository_impl.dart';
import 'package:omni_lar/features/shopping/data/datasources/shopping_datasource.dart';
import 'package:omni_lar/features/shopping/data/repositories/shopping_repository_impl.dart';

const _itemId = '11111111-2222-4333-8444-555555555555';
const _taskId = '66666666-7777-4888-9999-000000000000';

class _FlakyShoppingDataSource extends Fake implements ShoppingDataSource {
  bool online = false;
  final marks = <bool>[];

  @override
  Future<void> setItemBought(String itemId, {required bool bought, DateTime? at}) async {
    if (!online) throw Exception('SocketException: Failed host lookup');
    marks.add(bought);
  }

  final deleted = <String>[];

  @override
  Future<void> deleteItem(String itemId) async {
    if (!online) throw Exception('SocketException: Failed host lookup');
    deleted.add(itemId);
  }
}

class _FlakyCalendarDataSource extends MockCalendarDataSource {
  bool online = false;
  final marks = <bool>[];

  @override
  Future<void> setTaskCompleted({
    required String taskId,
    required bool completed,
    required String completedByMemberId,
    DateTime? at,
  }) async {
    if (!online) throw Exception('SocketException: Failed host lookup');
    marks.add(completed);
  }

  final deleted = <String>[];

  @override
  Future<void> deleteTask(String taskId) async {
    if (!online) throw Exception('SocketException: Failed host lookup');
    deleted.add(taskId);
  }
}

void main() {
  late OfflineQueueManager queue;
  late OfflineSyncService sync;

  setUp(() {
    queue = OfflineQueueManager();
    sync = OfflineSyncService(queue: queue, currentScope: () => 'user-1|house-1');
  });

  tearDown(() => queue.dispose());

  test('item marcado como comprado sem sinal entra na fila e é reenviado com o mesmo estado', () async {
    final dataSource = _FlakyShoppingDataSource();
    final repository = ShoppingRepositoryImpl(dataSource, sync);
    sync.registerHandler(
      OfflineActionType.setShoppingItemBought,
      (p) => dataSource.setItemBought(p['id'] as String, bought: p['bought'] as bool),
    );

    expect(await repository.setItemBought(_itemId, bought: true), isFalse);
    expect(sync.pendingForCurrentScope.single.type, OfflineActionType.setShoppingItemBought);

    dataSource.online = true;
    expect((await sync.drain()).synced, 1);
    // Reenviar marca de novo como comprado: não inverte
    expect(dataSource.marks, [true]);
    expect(await repository.setItemBought(_itemId, bought: true), isTrue);
    expect(dataSource.marks, [true, true]);
  });

  test('tarefa concluída sem conexão entra na fila e é reenviada', () async {
    final dataSource = _FlakyCalendarDataSource();
    final repository = CalendarRepositoryImpl(dataSource, sync);
    sync.registerHandler(
      OfflineActionType.setTaskCompleted,
      (p) => dataSource.setTaskCompleted(
        taskId: p['id'] as String,
        completed: p['completed'] as bool,
        completedByMemberId: p['completedBy'] as String,
      ),
    );

    final sent = await repository.setTaskCompleted(
      taskId: _taskId,
      completed: true,
      completedByMemberId: 'user-1',
    );
    expect(sent, isFalse);
    expect(sync.pendingForCurrentScope.single.payload['completed'], isTrue);

    dataSource.online = true;
    expect((await sync.drain()).synced, 1);
    expect(dataSource.marks, [true]);
  });

  test('item de compra excluído sem sinal entra na fila e é reenviado', () async {
    final dataSource = _FlakyShoppingDataSource();
    final repository = ShoppingRepositoryImpl(dataSource, sync);
    sync.registerHandler(
      OfflineActionType.deleteShoppingItem,
      (p) => dataSource.deleteItem(p['id'] as String),
    );

    expect(await repository.deleteItem(_itemId), isFalse);
    expect(sync.pendingForCurrentScope.single.type, OfflineActionType.deleteShoppingItem);

    dataSource.online = true;
    expect((await sync.drain()).synced, 1);
    expect(dataSource.deleted, [_itemId]);
  });

  test('tarefa excluída sem conexão entra na fila e é reenviada', () async {
    final dataSource = _FlakyCalendarDataSource();
    final repository = CalendarRepositoryImpl(dataSource, sync);
    sync.registerHandler(
      OfflineActionType.deleteTask,
      (p) => dataSource.deleteTask(p['id'] as String),
    );

    expect(await repository.deleteTask(_taskId), isFalse);
    expect(sync.pendingForCurrentScope.single.type, OfflineActionType.deleteTask);

    dataSource.online = true;
    expect((await sync.drain()).synced, 1);
    expect(dataSource.deleted, [_taskId]);
  });
}
