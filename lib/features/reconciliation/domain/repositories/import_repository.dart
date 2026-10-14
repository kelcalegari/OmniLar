import '../../../../core/domain/value_objects/money.dart';
import '../services/import_session.dart';

/// Uma importação já confirmada, para o histórico.
class ImportBatch {
  final String id;
  final String sourceName;
  final String? paymentMethodId;
  final String fileName;
  final DateTime? invoiceDueDate;
  final Money total;
  final int linesCount;

  /// Despesas e empréstimos que a importação criou (linhas com esse resultado).
  final int createdCount;
  final DateTime createdAt;
  final bool isUndone;

  const ImportBatch({
    required this.id,
    required this.sourceName,
    required this.fileName,
    required this.total,
    required this.linesCount,
    required this.createdCount,
    required this.createdAt,
    this.paymentMethodId,
    this.invoiceDueDate,
    this.isUndone = false,
  });
}

abstract class ImportRepository {
  /// Grava tudo o que a revisão decidiu, de uma vez: despesas, empréstimos,
  /// correções e o registro da importação. Se algo falha, nada é gravado.
  Future<void> confirmImport(ImportSession session, ImportPlan plan);

  /// Assinaturas das linhas já importadas de um cartão ou conta (fora as de
  /// importações desfeitas e as que ficaram de fora por ciclo fechado).
  Future<Set<String>> importedSignatures(String paymentMethodId);

  /// Importações da casa, da mais recente para a mais antiga.
  Future<List<ImportBatch>> getHistory({int limit = 20});

  /// Exclui as despesas e os empréstimos que a importação criou. As correções
  /// feitas em despesas que já existiam não são revertidas.
  Future<void> undoImport(String batchId);
}
