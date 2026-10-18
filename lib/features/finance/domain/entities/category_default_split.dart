import 'package:equatable/equatable.dart';

import 'house_member.dart';
import 'split_rule.dart';

/// Divisão que o lançamento de despesa de uma categoria já abre marcada
/// (coluna `categories.default_split`, 0097). É só sugestão: quem lança ainda
/// escolhe outra. Usa os mesmos tipos da divisão de despesas (`split_type`),
/// menos o valor fixo, que muda a cada lançamento:
/// - `percentage`: percentual de cada morador, somando 100;
/// - `category_owner`: um morador responde pela despesa inteira.
class CategoryDefaultSplit extends Equatable {
  /// Percentual por morador (id -> %). Preenchido quando [type] é percentage.
  final Map<String, double>? percentages;

  /// Morador que responde por tudo. Preenchido quando [type] é categoryOwner.
  final String? memberId;

  final SplitType type;

  const CategoryDefaultSplit.percentage(Map<String, double> this.percentages)
      : type = SplitType.percentage,
        memberId = null;

  const CategoryDefaultSplit.singleResponsible(String this.memberId)
      : type = SplitType.categoryOwner,
        percentages = null;

  /// Soma dos percentuais aceita como 100%, como no banco.
  static const double totalTolerance = 0.01;

  /// Os percentuais fecham 100%?
  static bool percentagesClose(Iterable<double> values) =>
      (values.fold<double>(0, (a, b) => a + b) - 100).abs() <= totalTolerance;

  /// Lê o jsonb da coluna; formato desconhecido ou inválido vale como sem padrão.
  static CategoryDefaultSplit? fromJson(Object? json) {
    if (json is! Map) return null;
    switch (json['type']) {
      case 'category_owner':
        final id = json['member_id'];
        return id is String && id.isNotEmpty ? CategoryDefaultSplit.singleResponsible(id) : null;
      case 'percentage':
        final raw = json['percentages'];
        if (raw is! Map) return null;
        final map = <String, double>{};
        for (final entry in raw.entries) {
          final value = entry.value;
          if (value is! num || value < 0 || value > 100) return null;
          map[entry.key.toString()] = value.toDouble();
        }
        return map.isNotEmpty && percentagesClose(map.values) ? CategoryDefaultSplit.percentage(map) : null;
    }
    return null;
  }

  Map<String, dynamic> toJson() => type == SplitType.categoryOwner
      ? {'type': 'category_owner', 'member_id': memberId}
      : {'type': 'percentage', 'percentages': percentages};

  /// A regra para os moradores de hoje. Quem saiu da casa depois de escolhido é
  /// ignorado; null quando sobra ninguém (vale a divisão da casa).
  SplitRule? toRule(List<HouseMember> members) {
    final ids = {for (final m in members) m.id};
    if (type == SplitType.categoryOwner) {
      return ids.contains(memberId) ? SplitRule.singleResponsible(memberId) : null;
    }
    final kept = {
      for (final e in percentages!.entries)
        if (ids.contains(e.key)) e.key: e.value,
    };
    if (kept.values.fold<double>(0, (a, b) => a + b) <= 0) return null;
    return SplitRule.percentage(kept);
  }

  @override
  List<Object?> get props => [type, percentages, memberId];
}
