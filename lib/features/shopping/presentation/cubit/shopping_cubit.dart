import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/domain/value_objects/money.dart';
import '../../domain/entities/shopping_item.dart';
import '../../domain/entities/shopping_list.dart';
import '../../domain/repositories/shopping_repository.dart';
import 'shopping_state.dart';

class ShoppingCubit extends BlocBase<ShoppingState> {
  final ShoppingRepository _repository;

  ShoppingCubit(this._repository) : super(const ShoppingState());

  Future<void> loadShoppingData() async {
    emit(state.copyWith(status: ShoppingCubitStatus.loading));
    try {
      final lists = await _repository.getLists();
      final defaultList = lists.firstWhere((l) => l.isDefault, orElse: () => lists.first);
      final items = await _repository.getItems(defaultList.id);

      emit(state.copyWith(
        status: ShoppingCubitStatus.loaded,
        lists: lists,
        selectedList: defaultList,
        items: items,
      ));
    } catch (e) {
      emit(state.copyWith(
        status: ShoppingCubitStatus.error,
        errorMessage: 'Erro ao carregar listas de compras: $e',
      ));
    }
  }

  void selectList(ShoppingList list) async {
    emit(state.copyWith(selectedList: list, status: ShoppingCubitStatus.loading));
    try {
      final items = await _repository.getItems(list.id);
      emit(state.copyWith(status: ShoppingCubitStatus.loaded, items: items));
    } catch (e) {
      emit(state.copyWith(status: ShoppingCubitStatus.error, errorMessage: '$e'));
    }
  }

  void toggleShoppingMode() {
    emit(state.copyWith(isShoppingMode: !state.isShoppingMode));
  }

  Future<void> addItem({
    required String name,
    double quantity = 1,
    String unit = 'un',
    String category = 'Geral',
    bool isPersonal = false,
    String? assignedMemberId,
    Money? estimatedPrice,
  }) async {
    if (state.selectedList == null) return;
    try {
      final item = ShoppingItem(
        id: 'item_${DateTime.now().millisecondsSinceEpoch}',
        listId: state.selectedList!.id,
        name: name,
        quantity: quantity,
        unit: unit,
        category: category,
        isPersonal: isPersonal,
        assignedMemberId: assignedMemberId,
        estimatedPrice: estimatedPrice,
      );

      await _repository.addItem(item);
      final updatedItems = await _repository.getItems(state.selectedList!.id);
      emit(state.copyWith(items: updatedItems));
    } catch (e) {
      emit(state.copyWith(errorMessage: 'Erro ao adicionar item: $e'));
    }
  }

  Future<void> toggleItemBought(String itemId) async {
    if (state.selectedList == null) return;
    try {
      await _repository.toggleItemBought(itemId);
      final updatedItems = await _repository.getItems(state.selectedList!.id);
      emit(state.copyWith(items: updatedItems));
    } catch (e) {
      emit(state.copyWith(errorMessage: 'Erro ao atualizar item: $e'));
    }
  }

  Future<void> deleteItem(String itemId) async {
    if (state.selectedList == null) return;
    try {
      await _repository.deleteItem(itemId);
      final updatedItems = await _repository.getItems(state.selectedList!.id);
      emit(state.copyWith(items: updatedItems));
    } catch (e) {
      emit(state.copyWith(errorMessage: 'Erro ao remover item: $e'));
    }
  }

  Future<void> completeTrip({
    required Money totalAmount,
    required String paymentMethodId,
    required String paidByMemberId,
    Money? personalItemsAmount,
    String? personalDebtorMemberId,
  }) async {
    if (state.selectedList == null) return;
    emit(state.copyWith(status: ShoppingCubitStatus.submitting));
    try {
      await _repository.completeTrip(
        listId: state.selectedList!.id,
        totalAmount: totalAmount,
        paymentMethodId: paymentMethodId,
        paidByMemberId: paidByMemberId,
        personalItemsAmount: personalItemsAmount,
        personalDebtorMemberId: personalDebtorMemberId,
      );

      final updatedItems = await _repository.getItems(state.selectedList!.id);
      emit(state.copyWith(
        status: ShoppingCubitStatus.tripCompleted,
        items: updatedItems,
        isShoppingMode: false,
      ));
    } catch (e) {
      emit(state.copyWith(
        status: ShoppingCubitStatus.error,
        errorMessage: 'Erro ao finalizar compra: $e',
      ));
    }
  }
}
