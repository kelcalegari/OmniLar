import 'package:equatable/equatable.dart';

import '../../../finance/domain/entities/import_params.dart';

class ShoppingList extends Equatable {
  final String id;
  final String name;
  final String icon;
  final bool isDefault;

  /// Categoria da despesa criada ao fechar a compra (0101); nulo = a de mercado.
  final String? defaultCategoryId;

  /// Divisão dessa despesa (0101); 'category' = a da categoria ou da casa.
  final ImportSplitMode defaultSplitMode;

  const ShoppingList({
    required this.id,
    required this.name,
    this.icon = 'shopping_cart_outlined',
    this.isDefault = false,
    this.defaultCategoryId,
    this.defaultSplitMode = ImportSplitMode.category,
  });

  ShoppingList copyWith({
    String? defaultCategoryId,
    bool clearDefaultCategory = false,
    ImportSplitMode? defaultSplitMode,
  }) =>
      ShoppingList(
        id: id,
        name: name,
        icon: icon,
        isDefault: isDefault,
        defaultCategoryId: clearDefaultCategory ? null : (defaultCategoryId ?? this.defaultCategoryId),
        defaultSplitMode: defaultSplitMode ?? this.defaultSplitMode,
      );

  @override
  List<Object?> get props => [id, name, icon, isDefault, defaultCategoryId, defaultSplitMode];
}
