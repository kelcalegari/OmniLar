import '../../../../core/domain/value_objects/money.dart';
import '../../domain/entities/shopping_item.dart';
import '../../domain/entities/shopping_list.dart';
import '../../domain/entities/shopping_trip.dart';

abstract class ShoppingDataSource {
  Future<List<ShoppingList>> getLists();
  Future<List<ShoppingItem>> getItems(String listId);
  Stream<List<ShoppingItem>> watchItems(String listId);
  Future<void> addItem(ShoppingItem item);

  /// Altera nome, quantidade e se o item é pessoal.
  Future<void> updateItem(ShoppingItem item);
  Future<void> toggleItemBought(String itemId);
  Future<void> deleteItem(String itemId);
  Future<ShoppingTrip> completeTrip({
    required String listId,
    required Money totalAmount,
    required String paymentMethodId,
    required String paidByMemberId,
    Money? personalItemsAmount,
    String? personalDebtorMemberId,
  });
}
