import '../../../../core/domain/value_objects/money.dart';
import '../../domain/entities/shopping_item.dart';

/// Serialização de itens de compras para a fila offline.

Map<String, dynamic> shoppingItemToJson(ShoppingItem item) => {
  'id': item.id,
  'listId': item.listId,
  'name': item.name,
  'quantity': item.quantity,
  'unit': item.unit,
  'category': item.category,
  'isPersonal': item.isPersonal,
  'assignedMemberId': item.assignedMemberId,
  'isBought': item.isBought,
  'estimatedCents': item.estimatedPrice?.cents,
  'actualCents': item.actualPrice?.cents,
  'boughtBy': item.boughtBy,
  'boughtAt': item.boughtAt?.toIso8601String(),
};

ShoppingItem shoppingItemFromJson(Map<String, dynamic> json) => ShoppingItem(
  id: json['id'] as String,
  listId: json['listId'] as String,
  name: json['name'] as String,
  quantity: (json['quantity'] as num?)?.toDouble() ?? 1,
  unit: json['unit'] as String? ?? 'un',
  category: json['category'] as String? ?? 'Geral',
  isPersonal: json['isPersonal'] as bool? ?? false,
  assignedMemberId: json['assignedMemberId'] as String?,
  isBought: json['isBought'] as bool? ?? false,
  estimatedPrice: json['estimatedCents'] != null
      ? Money((json['estimatedCents'] as num).toInt())
      : null,
  actualPrice: json['actualCents'] != null ? Money((json['actualCents'] as num).toInt()) : null,
  boughtBy: json['boughtBy'] as String?,
  boughtAt: json['boughtAt'] != null ? DateTime.parse(json['boughtAt'] as String) : null,
);
