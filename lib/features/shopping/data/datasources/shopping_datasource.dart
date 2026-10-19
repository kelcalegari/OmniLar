import '../../../../core/domain/value_objects/money.dart';
import '../../../finance/domain/entities/import_params.dart';
import '../../domain/entities/shopping_item.dart';
import '../../domain/entities/shopping_list.dart';
import '../../domain/entities/shopping_trip.dart';

abstract class ShoppingDataSource {
  Future<List<ShoppingList>> getLists();
  Future<List<ShoppingItem>> getItems(String listId);
  Stream<List<ShoppingItem>> watchItems(String listId);
  Future<void> addItem(ShoppingItem item);

  /// Altera nome, quantidade, unidade e se o item é pessoal.
  Future<void> updateItem(ShoppingItem item);
  Future<void> toggleItemBought(String itemId);

  /// Marca ou desmarca o item como comprado (pode ser repetido sem inverter de
  /// novo, por isso entra na fila offline). [at] é quando foi marcado.
  Future<void> setItemBought(String itemId, {required bool bought, DateTime? at});
  Future<void> deleteItem(String itemId);

  /// Categoria e divisão da despesa criada ao fechar a compra desta lista
  /// (0101). Categoria nula = a de mercado.
  Future<void> updateListDefaults(
    String listId, {
    String? categoryId,
    required ImportSplitMode splitMode,
  });
  Future<ShoppingTrip> completeTrip({
    required String listId,
    required Money totalAmount,
    required String paymentMethodId,
    required String paidByMemberId,
    Money? personalItemsAmount,
    String? personalDebtorMemberId,
  });
}
