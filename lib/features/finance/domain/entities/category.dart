import 'package:equatable/equatable.dart';

class ExpenseCategory extends Equatable {
  final String id;
  final String name;
  final String icon; // Icon name or unicode
  final String colorHex;
  final String? ownerMemberId; // Se a categoria tiver um dono específico (ex: 100% Carro para o Cris)

  /// Gasto variável no Planejamento de Aportes (estimado pela média do
  /// histórico). Null: nunca foi escolhido, vale a adivinhação pelo nome.
  final bool? isVariableSpend;

  const ExpenseCategory({
    required this.id,
    required this.name,
    required this.icon,
    required this.colorHex,
    this.ownerMemberId,
    this.isVariableSpend,
  });

  bool get hasOwner => ownerMemberId != null;

  /// O que o planejador usa: a escolha do cadastro ou, sem ela, o nome.
  bool get countsAsVariableSpend => isVariableSpend ?? looksLikeVariableSpend;

  /// Nome de consumo variável comum no orçamento da casa (mercado, contas de
  /// consumo): o padrão de quem nunca mexeu no interruptor.
  bool get looksLikeVariableSpend {
    final n = name.toLowerCase();
    return n.contains('mercado') ||
        n.contains('alimenta') ||
        n.contains('feira') ||
        n.contains('luz') ||
        n.contains('energia') ||
        n.contains('água') ||
        n.contains('agua') ||
        n.contains('gás') ||
        n.contains('gas') ||
        id.toLowerCase().contains('mercado');
  }

  @override
  List<Object?> get props => [id, name, icon, colorHex, ownerMemberId, isVariableSpend];
}
