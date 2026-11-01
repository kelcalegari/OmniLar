import '../../../core/domain/value_objects/money.dart';

/// Cota de cada morador gravada no retrato do fechamento (`summary_snapshot`
/// de `settlements`). Só vale para ciclo fechado: rascunho (ciclo reaberto) ou
/// fechamento antigo sem retrato devolvem nulo, e o planejador segue calculando.
Map<String, Money>? settledContributionDuesFromRow(Map<String, dynamic>? row) {
  if (row == null) return null;
  final status = row['status'];
  if (status != 'confirmed' && status != 'completed') return null;
  final snapshot = row['summary_snapshot'];
  if (snapshot is! Map) return null;
  final balances = snapshot['member_balances'];
  if (balances is! List || balances.isEmpty) return null;
  final dues = <String, Money>{};
  for (final b in balances) {
    if (b is! Map) continue;
    final id = b['member_id'];
    if (id is! String) continue;
    dues[id] = Money((b['contribution_due_cents'] as num?)?.toInt() ?? 0);
  }
  return dues.isEmpty ? null : dues;
}
