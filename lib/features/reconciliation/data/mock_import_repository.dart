import '../../../core/errors/failures.dart';
import '../../../core/utils/uuid.dart';
import '../../finance/data/datasources/finance_datasource.dart';
import '../../finance/domain/entities/house_expense.dart';
import '../../p2p/data/datasources/p2p_datasource.dart';
import '../domain/entities/installment_plan.dart';
import '../domain/repositories/import_repository.dart';
import '../domain/services/import_session.dart';

class _StoredImport {
  final ImportBatch batch;
  final List<ImportLineRecord> records;

  /// Planos de parcelamento que esta importação criou e parcelas previstas
  /// que ela confirmou.
  final Set<String> createdPlanIds;
  final List<InstallmentLink> confirmedForecasts;

  const _StoredImport(
    this.batch,
    this.records, {
    this.createdPlanIds = const {},
    this.confirmedForecasts = const [],
  });
}

/// Plano guardado em memória com as despesas das parcelas, pelo número.
class _StoredPlan {
  InstallmentPlan plan;
  final Map<int, InstallmentParcel> parcels = {};

  _StoredPlan(this.plan);
}

/// Importações do modo demo e dos testes: grava nas mesmas fontes em memória
/// que o resto do app usa e guarda o histórico enquanto o app estiver aberto.
class MockImportRepository implements ImportRepository {
  final FinanceDataSource finance;
  final P2PDataSource p2p;

  MockImportRepository({required this.finance, required this.p2p});

  final List<_StoredImport> _imports = [];

  /// Regras por cartão ou conta.
  final Map<String, List<ImportRule>> _rules = {};

  /// Compras parceladas, pelo id do plano.
  final Map<String, _StoredPlan> _plans = {};

  @override
  Future<List<ImportRule>> getRules(String paymentMethodId) async =>
      List.of(_rules[paymentMethodId] ?? const []);

  @override
  Future<void> saveRules(String paymentMethodId, List<ImportRule> rules) async {
    final stored = _rules.putIfAbsent(paymentMethodId, () => []);
    for (final rule in rules) {
      stored.removeWhere((r) => r.matchKey == rule.matchKey);
      stored.add(
        ImportRule(
          id: generateUuidV4(),
          matchKey: rule.matchKey,
          merchantName: rule.merchantName,
          destination: rule.destination,
          categoryId: rule.categoryId,
          assignedMemberId: rule.assignedMemberId,
        ),
      );
    }
  }

  @override
  Future<void> deleteRule(String ruleId) async {
    for (final stored in _rules.values) {
      stored.removeWhere((r) => r.id == ruleId);
    }
  }

  @override
  Future<void> confirmImport(ImportSession session, ImportPlan plan) async {
    for (final expense in plan.newExpenses) {
      await finance.addExpense(expense);
    }
    for (final expense in plan.expenseUpdates) {
      await finance.updateExpense(expense);
    }
    for (final loan in plan.loans) {
      await p2p.createLoan(loan);
    }
    for (final expenseId in plan.forecastDeletions) {
      await finance.deleteExpense(expenseId);
      for (final stored in _plans.values) {
        stored.parcels.removeWhere((_, parcel) => parcel.expense.id == expenseId);
      }
    }

    final createdPlanIds = <String>{};
    for (final installment in plan.installmentPlans) {
      final stored = _plans[installment.id];
      if (stored == null) {
        _plans[installment.id] = _StoredPlan(installment);
        createdPlanIds.add(installment.id);
      } else {
        stored.plan = installment;
      }
    }
    final expenses = <String, HouseExpense>{
      for (final expense in plan.newExpenses) expense.id: expense,
      for (final expense in plan.expenseUpdates) expense.id: expense,
    };
    final confirmedForecasts = <InstallmentLink>[];
    for (final link in plan.installmentLinks) {
      final stored = _plans[link.planId];
      if (stored == null) continue;
      final previous = stored.parcels[link.number];
      if (previous != null && previous.expense.id != link.expenseId) {
        throw const ValidationFailure('Uma parcela desta fatura já está lançada no app. Abra a importação de novo.');
      }
      final expense = expenses[link.expenseId] ?? previous?.expense;
      if (expense == null) continue;
      if (previous != null && previous.isForecast && !link.isForecast) confirmedForecasts.add(link);
      stored.parcels[link.number] = InstallmentParcel(expense: expense, isForecast: link.isForecast);
    }

    _imports.insert(
      0,
      _StoredImport(
        ImportBatch(
          id: generateUuidV4(),
          sourceName: session.source.name,
          paymentMethodId: session.source.id,
          fileName: session.fileName,
          invoiceDueDate: session.invoiceDueDate,
          total: session.totals.file,
          linesCount: plan.lineRecords.length,
          createdCount: plan.lineRecords.where((r) => r.outcome == LineOutcome.created).length,
          createdAt: DateTime.now(),
        ),
        plan.lineRecords,
        createdPlanIds: createdPlanIds,
        confirmedForecasts: confirmedForecasts,
      ),
    );
  }

  @override
  Future<List<InstallmentPlan>> installmentPlans(String paymentMethodId) async => [
        for (final stored in _plans.values)
          if (stored.plan.paymentMethodId == paymentMethodId)
            InstallmentPlan(
              id: stored.plan.id,
              paymentMethodId: stored.plan.paymentMethodId,
              merchantKey: stored.plan.merchantKey,
              title: stored.plan.title,
              total: stored.plan.total,
              installmentAmount: stored.plan.installmentAmount,
              anchorNumber: stored.plan.anchorNumber,
              anchorLineDate: stored.plan.anchorLineDate,
              anchorDueDate: stored.plan.anchorDueDate,
              destination: stored.plan.destination,
              categoryId: stored.plan.categoryId,
              assignedMemberId: stored.plan.assignedMemberId,
              parcels: Map.of(stored.parcels),
              importedNumbers: {
                for (final other in _imports)
                  if (!other.batch.isUndone)
                    for (final record in other.records)
                      if (record.installmentPlanId == stored.plan.id &&
                          record.outcome != LineOutcome.skipped)
                        ?record.installmentNumber,
              },
            ),
      ];

  @override
  Future<Set<String>> importedSignatures(String paymentMethodId) async => {
        for (final stored in _imports)
          if (!stored.batch.isUndone && stored.batch.paymentMethodId == paymentMethodId)
            for (final record in stored.records)
              if (record.outcome != LineOutcome.skipped && record.line.signature != null)
                record.line.signature!,
      };

  @override
  Future<List<ImportBatch>> getHistory({int limit = 20}) async =>
      [for (final stored in _imports.take(limit)) stored.batch];

  @override
  Future<List<LoanPurchase>> purchasesOfLoan(String loanId) async => [
        for (final stored in _imports)
          if (!stored.batch.isUndone)
            for (final record in stored.records)
              if (record.loanId == loanId)
                LoanPurchase(
                  date: record.line.date,
                  title: record.title ?? record.line.description,
                  amount: record.line.amount,
                ),
      ]..sort((a, b) => a.date.compareTo(b.date));

  @override
  Future<void> undoImport(String batchId) async {
    final index = _imports.indexWhere((stored) => stored.batch.id == batchId);
    if (index < 0) throw const NotFoundFailure('Importação não encontrada.');
    final stored = _imports[index];
    if (stored.batch.isUndone) throw const ValidationFailure('Esta importação já foi desfeita.');

    final usedLater = _imports.any(
      (other) =>
          !other.batch.isUndone &&
          other.batch.id != batchId &&
          other.records.any((r) => stored.createdPlanIds.contains(r.installmentPlanId)),
    );
    if (usedLater) {
      throw const ValidationFailure(
        'Uma fatura importada depois desta já usa uma das compras parceladas dela. Desfaça antes a importação mais recente.',
      );
    }
    for (final link in stored.confirmedForecasts) {
      final parcel = _plans[link.planId]?.parcels[link.number];
      if (parcel != null) {
        _plans[link.planId]!.parcels[link.number] = InstallmentParcel(expense: parcel.expense, isForecast: true);
      }
    }
    for (final planId in stored.createdPlanIds) {
      final removed = _plans.remove(planId);
      for (final parcel in removed?.parcels.values ?? const <InstallmentParcel>[]) {
        if (parcel.isForecast) await finance.deleteExpense(parcel.expense.id);
      }
    }

    final created = stored.records.where((r) => r.outcome == LineOutcome.created);
    for (final expenseId in {for (final r in created) ?r.expenseId}) {
      await finance.deleteExpense(expenseId);
    }
    for (final loanId in {for (final r in created) ?r.loanId}) {
      await p2p.deleteLoan(loanId);
    }

    final batch = stored.batch;
    _imports[index] = _StoredImport(
      ImportBatch(
        id: batch.id,
        sourceName: batch.sourceName,
        paymentMethodId: batch.paymentMethodId,
        fileName: batch.fileName,
        invoiceDueDate: batch.invoiceDueDate,
        total: batch.total,
        linesCount: batch.linesCount,
        createdCount: batch.createdCount,
        createdAt: batch.createdAt,
        isUndone: true,
      ),
      stored.records,
      createdPlanIds: stored.createdPlanIds,
      confirmedForecasts: stored.confirmedForecasts,
    );
  }
}

/// Escolhe entre o banco e a memória conforme o modo demo, como as outras fontes.
class DynamicImportRepository implements ImportRepository {
  final ImportRepository remote;
  final ImportRepository mock;
  final bool Function() isDemoMode;

  DynamicImportRepository({required this.remote, required this.mock, required this.isDemoMode});

  ImportRepository get _active => isDemoMode() ? mock : remote;

  @override
  Future<void> confirmImport(ImportSession session, ImportPlan plan) =>
      _active.confirmImport(session, plan);

  @override
  Future<Set<String>> importedSignatures(String paymentMethodId) =>
      _active.importedSignatures(paymentMethodId);

  @override
  Future<List<ImportBatch>> getHistory({int limit = 20}) => _active.getHistory(limit: limit);

  @override
  Future<void> undoImport(String batchId) => _active.undoImport(batchId);

  @override
  Future<List<LoanPurchase>> purchasesOfLoan(String loanId) => _active.purchasesOfLoan(loanId);

  @override
  Future<List<ImportRule>> getRules(String paymentMethodId) => _active.getRules(paymentMethodId);

  @override
  Future<void> saveRules(String paymentMethodId, List<ImportRule> rules) =>
      _active.saveRules(paymentMethodId, rules);

  @override
  Future<void> deleteRule(String ruleId) => _active.deleteRule(ruleId);

  @override
  Future<List<InstallmentPlan>> installmentPlans(String paymentMethodId) =>
      _active.installmentPlans(paymentMethodId);
}
