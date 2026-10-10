import '../../../../core/domain/value_objects/money.dart';
import '../entities/shopping_item.dart';
import '../entities/shopping_list.dart';
import '../entities/shopping_trip.dart';

abstract class ShoppingRepository {
  Future<List<ShoppingList>> getLists();
  Future<List<ShoppingItem>> getItems(String listId);
  Future<void> addItem(ShoppingItem item);
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
