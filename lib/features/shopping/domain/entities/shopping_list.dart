import 'package:equatable/equatable.dart';

class ShoppingList extends Equatable {
  final String id;
  final String name;
  final String icon;
  final bool isDefault;

  const ShoppingList({
    required this.id,
    required this.name,
    this.icon = 'shopping_cart_outlined',
    this.isDefault = false,
  });

  @override
  List<Object?> get props => [id, name, icon, isDefault];
}
