import 'package:equatable/equatable.dart';

import 'category_default_split.dart';

class ExpenseCategory extends Equatable {
  final String id;
  final String name;
  final String icon; // Icon name or unicode
  final String colorHex;
  final String? ownerMemberId; // Se a categoria tiver um dono específico (ex: 100% Carro para o Cris)

  /// Gasto variável no Planejamento de Aportes (estimado pela média do
  /// histórico). Null: nunca foi escolhido, vale a adivinhação pelo nome.
  final bool? isVariableSpend;

  /// Divisão que o lançamento da categoria já abre marcada (0097). Null: sem
  /// padrão, vale a divisão da casa.
  final CategoryDefaultSplit? defaultSplit;

  const ExpenseCategory({
    required this.id,
    required this.name,
    required this.icon,
    required this.colorHex,
    this.ownerMemberId,
    this.isVariableSpend,
    this.defaultSplit,
  });

  bool get hasOwner => ownerMemberId != null;

  /// O que o planejador usa: só o interruptor do cadastro (a migração 0098
  /// marcou as categorias que o nome sugeria variáveis). Sem escolha, não é.
  bool get countsAsVariableSpend => isVariableSpend ?? false;

  @override
  List<Object?> get props => [id, name, icon, colorHex, ownerMemberId, isVariableSpend, defaultSplit];
}
