import '../../../../core/network/offline_queue.dart';
import '../../../../core/network/offline_sync_service.dart';
import '../../../../core/utils/uuid.dart';
import '../offline/shopping_item_offline_codec.dart';
import '../../../../core/domain/value_objects/money.dart';
import '../../domain/entities/shopping_item.dart';
import '../../domain/entities/shopping_list.dart';
import '../../domain/entities/shopping_trip.dart';
import '../../domain/repositories/shopping_repository.dart';
import '../datasources/shopping_datasource.dart';

class ShoppingRepositoryImpl implements ShoppingRepository {
  final ShoppingDataSource _dataSource;
  final OfflineSyncService? _offlineSync;

  ShoppingRepositoryImpl(this._dataSource, [this._offlineSync]);

  @override
  Future<List<ShoppingList>> getLists() => _dataSource.getLists();

  @override
  Future<List<ShoppingItem>> getItems(String listId) => _dataSource.getItems(listId);

  @override
  Stream<List<ShoppingItem>> watchItems(String listId) => _dataSource.watchItems(listId);

  @override
  Future<void> addItem(ShoppingItem item) async {
    final sync = _offlineSync;
    if (sync == null || !sync.isActive) return _dataSource.addItem(item);

    final withId = isUuid(item.id) ? item : item.copyWith(id: generateUuidV4());
    await sync.runOrQueue(
      OfflineActionType.addShoppingItem,
      () => shoppingItemToJson(withId),
      () => _dataSource.addItem(withId),
    );
  }

  @override
  Future<void> toggleItemBought(String itemId) => _dataSource.toggleItemBought(itemId);

  @override
  Future<bool> setItemBought(String itemId, {required bool bought}) async {
    final sync = _offlineSync;
    final at = DateTime.now();
    // Só o que já tem id real pode ser reenviado depois
    if (sync == null || !sync.isActive || !isUuid(itemId)) {
      await _dataSource.setItemBought(itemId, bought: bought, at: at);
      return true;
    }
    return sync.runOrQueue(
      OfflineActionType.setShoppingItemBought,
      () => {'id': itemId, 'bought': bought, 'at': at.toIso8601String()},
      () => _dataSource.setItemBought(itemId, bought: bought, at: at),
    );
  }

  @override
  Future<void> deleteItem(String itemId) => _dataSource.deleteItem(itemId);

  @override
  Future<void> updateItem(ShoppingItem item) async {
    final sync = _offlineSync;
    // Só o que já tem id real pode ser reenviado depois
    if (sync == null || !sync.isActive || !isUuid(item.id)) {
      return _dataSource.updateItem(item);
    }
    await sync.runOrQueue(
      OfflineActionType.updateShoppingItem,
      () => shoppingItemToJson(item),
      () => _dataSource.updateItem(item),
    );
  }

  @override
  Future<ShoppingTrip> completeTrip({
    required String listId,
    required Money totalAmount,
    required String paymentMethodId,
    required String paidByMemberId,
    Money? personalItemsAmount,
    String? personalDebtorMemberId,
  }) =>
      _dataSource.completeTrip(
        listId: listId,
        totalAmount: totalAmount,
        paymentMethodId: paymentMethodId,
        paidByMemberId: paidByMemberId,
        personalItemsAmount: personalItemsAmount,
        personalDebtorMemberId: personalDebtorMemberId,
      );
}
