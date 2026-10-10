import 'package:equatable/equatable.dart';
import '../../../../core/domain/value_objects/money.dart';

class ShoppingItem extends Equatable {
  final String id;
  final String listId;
  final String name;
  final double quantity;
  final String unit;
  final String category;
  final bool isPersonal;
  final String? assignedMemberId;
  final bool isBought;
  final Money? estimatedPrice;
  final Money? actualPrice;
  final String? boughtBy;
  final DateTime? boughtAt;

  const ShoppingItem({
    required this.id,
    required this.listId,
    required this.name,
    this.quantity = 1,
    this.unit = 'un',
    this.category = 'Geral',
    this.isPersonal = false,
    this.assignedMemberId,
    this.isBought = false,
    this.estimatedPrice,
    this.actualPrice,
    this.boughtBy,
    this.boughtAt,
  });

  ShoppingItem copyWith({
    String? id,
    String? listId,
    String? name,
    double? quantity,
    String? unit,
    String? category,
    bool? isPersonal,
    String? assignedMemberId,
    bool? isBought,
    Money? estimatedPrice,
    Money? actualPrice,
    String? boughtBy,
    DateTime? boughtAt,
  }) {
    return ShoppingItem(
      id: id ?? this.id,
      listId: listId ?? this.listId,
      name: name ?? this.name,
      quantity: quantity ?? this.quantity,
      unit: unit ?? this.unit,
      category: category ?? this.category,
      isPersonal: isPersonal ?? this.isPersonal,
      assignedMemberId: assignedMemberId ?? this.assignedMemberId,
      isBought: isBought ?? this.isBought,
      estimatedPrice: estimatedPrice ?? this.estimatedPrice,
      actualPrice: actualPrice ?? this.actualPrice,
      boughtBy: boughtBy ?? this.boughtBy,
      boughtAt: boughtAt ?? this.boughtAt,
    );
  }

  @override
  List<Object?> get props => [
        id,
        listId,
        name,
        quantity,
        unit,
        category,
        isPersonal,
        assignedMemberId,
        isBought,
        estimatedPrice,
        actualPrice,
        boughtBy,
        boughtAt,
      ];
}
