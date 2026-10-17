import '../../../../core/domain/value_objects/money.dart';
import '../entities/shopping_item.dart';
import '../entities/shopping_list.dart';
import '../entities/shopping_trip.dart';

abstract class ShoppingRepository {
  Future<List<ShoppingList>> getLists();
  Future<List<ShoppingItem>> getItems(String listId);
  Stream<List<ShoppingItem>> watchItems(String listId);
  Future<void> addItem(ShoppingItem item);

  /// Altera nome, quantidade e se o item é pessoal.
  Future<void> updateItem(ShoppingItem item);
  Future<void> toggleItemBought(String itemId);

  /// Marca ou desmarca o item como comprado. Sem conexão a marcação entra na
  /// fila offline e devolve false (a tela atualiza o item por conta própria).
  Future<bool> setItemBought(String itemId, {required bool bought});
  /// Retorna false quando ficou na fila offline para ser reenviada.
  Future<bool> deleteItem(String itemId);
  Future<ShoppingTrip> completeTrip({
    required String listId,
    required Money totalAmount,
    required String paymentMethodId,
    required String paidByMemberId,
    Money? personalItemsAmount,
    String? personalDebtorMemberId,
  });
}
