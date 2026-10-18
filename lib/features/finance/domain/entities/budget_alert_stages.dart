import 'package:equatable/equatable.dart';

/// Percentuais da média em que o alerta de orçamento da categoria avisa
/// (`houses.budget_alert_stages` e `categories.budget_alert_stages`, 0099).
/// Abaixo de 100 vale ao chegar no estágio; de 100 em diante, ao passar dele.
class BudgetAlertStages extends Equatable {
  /// O que o agendador sempre fez: perto do previsto (90%) e passou (100%).
  static const defaults = BudgetAlertStages([90, 100]);

  static const int minStage = 1;
  static const int maxStage = 300;
  static const int maxCount = 4;

  /// Em ordem crescente, sem repetição.
  final List<int> stages;

  const BudgetAlertStages(this.stages);

  /// Lista inválida (fora da faixa, fora de ordem, vazia) vale o [fallback].
  factory BudgetAlertStages.fromJson(Object? json, {BudgetAlertStages fallback = defaults}) {
    if (json is! List) return fallback;
    final values = <int>[];
    for (final raw in json) {
      if (raw is! num || raw != raw.truncate()) return fallback;
      values.add(raw.toInt());
    }
    final parsed = BudgetAlertStages(values);
    return parsed.isValid ? parsed : fallback;
  }

  /// "80, 100" -> [80, 100]. Null se não for uma lista válida.
  static BudgetAlertStages? parse(String text) {
    final parts = text.split(RegExp(r'[,;\s]+')).where((p) => p.isNotEmpty).toList();
    final values = <int>[];
    for (final part in parts) {
      final value = int.tryParse(part.replaceAll('%', ''));
      if (value == null) return null;
      values.add(value);
    }
    final parsed = BudgetAlertStages(values);
    return parsed.isValid ? parsed : null;
  }

  bool get isValid =>
      stages.isNotEmpty &&
      stages.length <= maxCount &&
      stages.every((s) => s >= minStage && s <= maxStage) &&
      [for (var i = 1; i < stages.length; i++) stages[i] > stages[i - 1]].every((ok) => ok);

  List<int> toJson() => List<int>.of(stages);

  /// Maior estágio atingido por [percent] (0 = nenhum), como o agendador.
  int stageFor(int percent) {
    var reached = 0;
    for (final stage in stages) {
      if (stage < 100 ? percent >= stage : percent > stage) reached = stage;
    }
    return reached;
  }

  /// "80% e 100%".
  String get label {
    final parts = stages.map((s) => '$s%').toList();
    if (parts.length == 1) return parts.first;
    return '${parts.sublist(0, parts.length - 1).join(', ')} e ${parts.last}';
  }

  /// Texto editável: "80, 100".
  String get editText => stages.join(', ');

  @override
  List<Object?> get props => [stages];
}
