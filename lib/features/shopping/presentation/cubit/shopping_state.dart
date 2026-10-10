import 'package:equatable/equatable.dart';
import '../../domain/entities/shopping_item.dart';
import '../../domain/entities/shopping_list.dart';

enum ShoppingCubitStatus {
  initial,
  loading,
  loaded,
  submitting,
  tripCompleted,
  error,
}

class ShoppingState extends Equatable {
  final ShoppingCubitStatus status;
  final List<ShoppingList> lists;
  final ShoppingList? selectedList;
  final List<ShoppingItem> items;
  final bool isShoppingMode;
  final String? errorMessage;

  const ShoppingState({
    this.status = ShoppingCubitStatus.initial,
    this.lists = const [],
    this.selectedList,
    this.items = const [],
    this.isShoppingMode = false,
    this.errorMessage,
  });

  int get pendingCount => items.where((i) => !i.isBought).length;
  int get boughtCount => items.where((i) => i.isBought).length;
  double get progress => items.isEmpty ? 0.0 : boughtCount / items.length;

  ShoppingState copyWith({
    ShoppingCubitStatus? status,
    List<ShoppingList>? lists,
    ShoppingList? selectedList,
    List<ShoppingItem>? items,
    bool? isShoppingMode,
    String? errorMessage,
  }) {
    return ShoppingState(
      status: status ?? this.status,
      lists: lists ?? this.lists,
      selectedList: selectedList ?? this.selectedList,
      items: items ?? this.items,
      isShoppingMode: isShoppingMode ?? this.isShoppingMode,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  @override
  List<Object?> get props => [
        status,
        lists,
        selectedList,
        items,
        isShoppingMode,
        errorMessage,
      ];
}
