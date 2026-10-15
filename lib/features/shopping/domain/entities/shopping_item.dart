import 'package:equatable/equatable.dart';
import '../../../../core/domain/value_objects/money.dart';

/// Item da lista de compras. Não tem categoria própria: a compra fechada vira
/// uma despesa na categoria de mercado da casa (ver `completeShoppingTrip`).
class ShoppingItem extends Equatable {
  final String id;
  final String listId;
  final String name;
  final double quantity;
  final String unit;
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
        isPersonal,
        assignedMemberId,
        isBought,
        estimatedPrice,
        actualPrice,
        boughtBy,
        boughtAt,
      ];
}
