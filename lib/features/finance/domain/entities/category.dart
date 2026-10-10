import 'package:equatable/equatable.dart';

class ExpenseCategory extends Equatable {
  final String id;
  final String name;
  final String icon; // Icon name or unicode
  final String colorHex;
  final String? ownerMemberId; // Se a categoria tiver um dono específico (ex: 100% Carro para o Cris)

  const ExpenseCategory({
    required this.id,
    required this.name,
    required this.icon,
    required this.colorHex,
    this.ownerMemberId,
  });

  bool get hasOwner => ownerMemberId != null;

  @override
  List<Object?> get props => [id, name, icon, colorHex, ownerMemberId];
}
