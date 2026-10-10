import '../../../../core/domain/value_objects/money.dart';
import '../../domain/entities/shopping_item.dart';
import '../../domain/entities/shopping_list.dart';
import '../../domain/entities/shopping_trip.dart';
import '../../domain/repositories/shopping_repository.dart';
import '../datasources/shopping_datasource.dart';

class ShoppingRepositoryImpl implements ShoppingRepository {
  final ShoppingDataSource _dataSource;

  ShoppingRepositoryImpl(this._dataSource);

  @override
  Future<List<ShoppingList>> getLists() => _dataSource.getLists();

  @override
  Future<List<ShoppingItem>> getItems(String listId) => _dataSource.getItems(listId);

  @override
  Future<void> addItem(ShoppingItem item) => _dataSource.addItem(item);

  @override
  Future<void> toggleItemBought(String itemId) => _dataSource.toggleItemBought(itemId);

  @override
  Future<void> deleteItem(String itemId) => _dataSource.deleteItem(itemId);

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
