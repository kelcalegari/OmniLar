import '../../../../core/domain/value_objects/money.dart';
import '../../domain/entities/shopping_item.dart';
import '../../domain/entities/shopping_list.dart';
import '../../domain/entities/shopping_trip.dart';
import 'shopping_datasource.dart';

class DynamicShoppingDataSource implements ShoppingDataSource {
  final ShoppingDataSource remote;
  final ShoppingDataSource mock;
  final bool Function() isDemoMode;

  DynamicShoppingDataSource({
    required this.remote,
    required this.mock,
    required this.isDemoMode,
  });

  ShoppingDataSource get _active => isDemoMode() ? mock : remote;

  @override
  Future<List<ShoppingList>> getLists() => _active.getLists();

  @override
  Future<List<ShoppingItem>> getItems(String listId) => _active.getItems(listId);

  @override
  Stream<List<ShoppingItem>> watchItems(String listId) => _active.watchItems(listId);

  @override
  Future<void> addItem(ShoppingItem item) => _active.addItem(item);

  @override
  Future<void> toggleItemBought(String itemId) => _active.toggleItemBought(itemId);

  @override
  Future<void> setItemBought(String itemId, {required bool bought, DateTime? at}) =>
      _active.setItemBought(itemId, bought: bought, at: at);

  @override
  Future<void> deleteItem(String itemId) => _active.deleteItem(itemId);

  @override
  Future<void> updateItem(ShoppingItem item) => _active.updateItem(item);

  @override
  Future<ShoppingTrip> completeTrip({
    required String listId,
    required Money totalAmount,
    required String paymentMethodId,
    required String paidByMemberId,
    Money? personalItemsAmount,
    String? personalDebtorMemberId,
  }) =>
      _active.completeTrip(
        listId: listId,
        totalAmount: totalAmount,
        paymentMethodId: paymentMethodId,
        paidByMemberId: paidByMemberId,
        personalItemsAmount: personalItemsAmount,
        personalDebtorMemberId: personalDebtorMemberId,
      );
}
