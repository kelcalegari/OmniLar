import '../../../../core/domain/value_objects/money.dart';
import '../entities/imported_statement_line.dart';
import '../entities/installment_plan.dart';
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

/// O que o usuário decidiu para um estabelecimento em um cartão ou conta,
/// para a próxima importação já vir assim.
class ImportRule {
  final String? id;

  /// Nome do estabelecimento sem acento, número de loja nem parcela.
  final String matchKey;
  final String merchantName;
  final LineDestination destination;
  final String? categoryId;
  final String? assignedMemberId;

  const ImportRule({
    required this.matchKey,
    required this.merchantName,
    required this.destination,
    this.id,
    this.categoryId,
    this.assignedMemberId,
  });
}

/// Compra da fatura que virou (parte de) um empréstimo, para o detalhe dele.
class LoanPurchase {
  final DateTime date;
  final String title;
  final Money amount;

  const LoanPurchase({required this.date, required this.title, required this.amount});
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

  /// Regras aprendidas para um cartão ou conta.
  Future<List<ImportRule>> getRules(String paymentMethodId);

  /// Guarda as regras; a de um estabelecimento que já tinha regra é trocada.
  Future<void> saveRules(String paymentMethodId, List<ImportRule> rules);
  Future<void> deleteRule(String ruleId);

  /// Compras de importações ativas que formam o empréstimo [loanId], por data.
  Future<List<LoanPurchase>> purchasesOfLoan(String loanId);

  /// Compras parceladas de um cartão que ainda estão em curso, com as
  /// despesas das parcelas e as parcelas que as importações ativas já trataram.
  Future<List<InstallmentPlan>> installmentPlans(String paymentMethodId);
}
