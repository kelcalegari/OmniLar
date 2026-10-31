import '../../../core/errors/failures.dart';
import '../../../core/utils/uuid.dart';
import '../../finance/data/datasources/finance_datasource.dart';
import '../../finance/domain/entities/house_expense.dart';
import '../../p2p/data/datasources/p2p_datasource.dart';
import '../domain/entities/installment_plan.dart';
import '../domain/repositories/import_repository.dart';
import '../domain/services/import_session.dart';
import '../domain/services/installment_purchase.dart';

class _StoredImport {
  final ImportBatch batch;
  final List<ImportLineRecord> records;

  /// Planos de parcelamento que esta importação criou e parcelas previstas
  /// que ela confirmou.
  final Set<String> createdPlanIds;
  final List<InstallmentLink> confirmedForecasts;

  /// Previstas que ela tirou da casa e o que os planos eram antes dela.
  final List<({String planId, int number, HouseExpense expense})> replacedForecasts;
  final List<InstallmentPlan> previousPlans;

  const _StoredImport(
    this.batch,
    this.records, {
    this.createdPlanIds = const {},
    this.confirmedForecasts = const [],
    this.replacedForecasts = const [],
    this.previousPlans = const [],
  });
}

/// Plano guardado em memória com as despesas das parcelas, pelo número.
class _StoredPlan {
  InstallmentPlan plan;
  final Map<int, InstallmentParcel> parcels = {};

  /// Empréstimos da compra lançada à mão.
  final List<String> loanIds = [];

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
    final replacedForecasts = <({String planId, int number, HouseExpense expense})>[];
    for (final expenseId in plan.forecastDeletions) {
      await finance.deleteExpense(expenseId);
      for (final entry in _plans.entries) {
        final parcels = entry.value.parcels;
        for (final number in parcels.keys.toList()) {
          if (parcels[number]!.expense.id != expenseId) continue;
          replacedForecasts.add((planId: entry.key, number: number, expense: parcels[number]!.expense));
          parcels.remove(number);
        }
      }
    }

    final createdPlanIds = <String>{};
    final previousPlans = <InstallmentPlan>[];
    for (final installment in plan.installmentPlans) {
      final stored = _plans[installment.id];
      // Como no banco: o aceite só muda pelo devedor, e plano novo nasce sem ele
      if (stored == null) {
        _plans[installment.id] = _StoredPlan(InstallmentPlan(
          id: installment.id,
          paymentMethodId: installment.paymentMethodId,
          merchantKey: installment.merchantKey,
          title: installment.title,
          total: installment.total,
          installmentAmount: installment.installmentAmount,
          anchorNumber: installment.anchorNumber,
          anchorLineDate: installment.anchorLineDate,
          anchorDueDate: installment.anchorDueDate,
          destination: installment.destination,
          categoryId: installment.categoryId,
          assignedMemberId: installment.assignedMemberId,
          status: installment.status,
        ));
        createdPlanIds.add(installment.id);
      } else {
        previousPlans.add(stored.plan);
        stored.plan = stored.plan.copyWith(
          destination: installment.destination,
          categoryId: installment.categoryId,
          assignedMemberId: installment.assignedMemberId,
          clearAssignedMember: installment.assignedMemberId == null,
          status: installment.status,
        );
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
        replacedForecasts: replacedForecasts,
        previousPlans: previousPlans,
      ),
    );
  }

  @override
  Future<List<InstallmentPlan>> installmentPlans(String paymentMethodId) async => [
        for (final stored in _plans.values)
          if (stored.plan.paymentMethodId == paymentMethodId) _snapshot(stored),
      ];

  @override
  Future<List<InstallmentPlan>> houseInstallmentPlans() async => [
        for (final stored in _plans.values)
          if (stored.plan.isActive) _snapshot(stored),
      ];

  @override
  Future<void> acceptInstallmentPlan(String planId) async {
    final stored = _plans[planId];
    if (stored == null) throw const NotFoundFailure('Compra parcelada não encontrada.');
    stored.plan = stored.plan.copyWith(acceptedBy: stored.plan.assignedMemberId);
  }

  @override
  Future<void> createInstallmentPurchase(InstallmentPurchase purchase) async {
    final stored = _StoredPlan(purchase.plan);
    for (final (index, expense) in purchase.expenses.indexed) {
      await finance.addExpense(expense);
      stored.parcels[purchase.firstNumber + index] = InstallmentParcel(expense: expense, isForecast: true);
    }
    for (final loan in purchase.loans) {
      await p2p.createLoan(loan);
      stored.loanIds.add(loan.id);
    }
    _plans[purchase.plan.id] = stored;
  }

  @override
  Future<void> deleteInstallmentPurchase(String planId) async {
    final stored = _plans[planId];
    if (stored == null) throw const NotFoundFailure('Compra parcelada não encontrada.');
    if (stored.parcels.values.any((p) => !p.isForecast)) {
      throw const ServerFailure(
        'Uma fatura importada já confirmou parcela desta compra. Desfaça antes a importação dessa fatura.',
      );
    }
    for (final parcel in stored.parcels.values) {
      await finance.deleteExpense(parcel.expense.id);
    }
    for (final loanId in stored.loanIds) {
      await p2p.deleteLoan(loanId);
    }
    _plans.remove(planId);
  }

  /// O plano como o banco devolve: parcelas e o que as importações ativas trataram.
  InstallmentPlan _snapshot(_StoredPlan stored) => stored.plan.copyWith(
        parcels: Map.of(stored.parcels),
        importedNumbers: {
          for (final other in _imports)
            if (!other.batch.isUndone)
              for (final record in other.records)
                if (record.installmentPlanId == stored.plan.id && record.outcome != LineOutcome.skipped)
                  ?record.installmentNumber,
        },
      );

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

    // Só a importação mais recente de cada compra parcelada pode ser desfeita
    // (as mais novas ficam antes na lista)
    final touched = {
      ...stored.createdPlanIds,
      for (final record in stored.records) ?record.installmentPlanId,
    };
    final usedLater = _imports
        .take(index)
        .any((other) => !other.batch.isUndone && other.records.any((r) => touched.contains(r.installmentPlanId)));
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
    for (final previous in stored.previousPlans) {
      final target = _plans[previous.id];
      target?.plan = target.plan.copyWith(
        destination: previous.destination,
        categoryId: previous.categoryId,
        assignedMemberId: previous.assignedMemberId,
        clearAssignedMember: previous.assignedMemberId == null,
        status: previous.status,
      );
    }
    for (final replaced in stored.replacedForecasts) {
      final target = _plans[replaced.planId];
      if (target == null) continue;
      await finance.addExpense(replaced.expense);
      target.parcels[replaced.number] = InstallmentParcel(expense: replaced.expense, isForecast: true);
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
      replacedForecasts: stored.replacedForecasts,
      previousPlans: stored.previousPlans,
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

  @override
  Future<void> createInstallmentPurchase(InstallmentPurchase purchase) =>
      _active.createInstallmentPurchase(purchase);

  @override
  Future<List<InstallmentPlan>> houseInstallmentPlans() => _active.houseInstallmentPlans();

  @override
  Future<void> deleteInstallmentPurchase(String planId) => _active.deleteInstallmentPurchase(planId);

  @override
  Future<void> acceptInstallmentPlan(String planId) => _active.acceptInstallmentPlan(planId);
}
