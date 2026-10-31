import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/domain/value_objects/money.dart';
import '../../../core/errors/failures.dart';
import '../../../core/utils/uuid.dart';
import '../../finance/data/datasources/house_expense_payload.dart';
import '../../finance/data/datasources/house_expense_row.dart';
import '../../p2p/data/datasources/p2p_loan_payload.dart';
import '../domain/entities/imported_statement_line.dart';
import '../domain/entities/installment_plan.dart';
import '../domain/repositories/import_repository.dart';
import '../domain/services/import_session.dart';
import '../domain/services/installment_purchase.dart';

String _dateOnly(DateTime date) => date.toIso8601String().split('T')[0];

String _destinationToDb(LineDestination destination) => switch (destination) {
      LineDestination.house => 'house',
      LineDestination.splitP2P => 'p2p_loan',
      LineDestination.cardOwnerPersonal => 'personal',
      LineDestination.ignored => 'ignored',
      LineDestination.thirdParty => 'third_party',
    };

InstallmentPlanStatus _planStatusFromDb(String? value) => switch (value) {
      'finished' => InstallmentPlanStatus.finished,
      'cancelled' => InstallmentPlanStatus.cancelled,
      _ => InstallmentPlanStatus.active,
    };

LineDestination _destinationFromDb(String? value) => switch (value) {
      'p2p_loan' => LineDestination.splitP2P,
      'personal' => LineDestination.cardOwnerPersonal,
      'ignored' => LineDestination.ignored,
      'third_party' => LineDestination.thirdParty,
      _ => LineDestination.house,
    };

/// Importação no formato da RPC `confirm_import`, que grava tudo em uma transação.
Map<String, dynamic> importPayload(
  ImportSession session,
  ImportPlan plan, {
  required String houseId,
  required String? currentUserId,
}) {
  return {
    'batch': {
      'house_id': houseId,
      'source_type': session.source.isCreditCard ? 'credit_card' : 'bank_statement',
      'account_name': session.source.name,
      if (isUuid(session.source.id)) 'payment_method_id': session.source.id,
      'file_name': session.fileName,
      if (session.invoiceDueDate != null) 'invoice_due_date': _dateOnly(session.invoiceDueDate!),
      if (isUuid(session.payerMemberId)) 'payer_id': session.payerMemberId,
      'total_cents': session.totals.file.cents,
    },
    'expenses': [
      for (final expense in plan.newExpenses)
        houseExpensePayload(expense, houseId: houseId, currentUserId: currentUserId),
    ],
    'loans': [for (final loan in plan.loans) p2pLoanPayload(loan, houseId: houseId)],
    'expense_updates': [
      for (final expense in plan.expenseUpdates)
        {
          'id': expense.id,
          'amount_cents': expense.amount.cents,
          if (isUuid(expense.paymentMethodId)) 'payment_method_id': expense.paymentMethodId,
          if (isUuid(expense.paidByMemberId)) 'paid_by_id': expense.paidByMemberId,
          'paid_out_of_pocket': expense.paidOutOfPocket,
          if (expense.dueDate != null) 'due_date': _dateOnly(expense.dueDate!),
          'split_rules': splitRuleRows(expense),
        },
    ],
    'lines': [
      for (final record in plan.lineRecords)
        {
          'line_date': _dateOnly(record.line.date),
          'description': record.line.description,
          'amount_cents': record.line.amount.cents,
          'kind': record.line.kind.name,
          if (record.line.externalId != null) 'external_id': record.line.externalId,
          if (record.line.signature != null) 'signature': record.line.signature,
          if (record.title != null) 'title': record.title,
          'split_destination': _destinationToDb(record.line.destination),
          if (isUuid(record.line.categoryId)) 'category_id': record.line.categoryId,
          if (isUuid(record.line.assignedMemberId)) 'assigned_member_id': record.line.assignedMemberId,
          'decision': record.outcome.name,
          if (isUuid(record.expenseId)) 'expense_id': record.expenseId,
          if (isUuid(record.loanId)) 'loan_id': record.loanId,
          if (isUuid(record.installmentPlanId)) 'installment_plan_id': record.installmentPlanId,
          'installment_number': ?record.installmentNumber,
        },
    ],
    'installment_plans': [
      for (final installment in plan.installmentPlans)
        if (isUuid(installment.id) && isUuid(installment.paymentMethodId))
          {
            'id': installment.id,
            'payment_method_id': installment.paymentMethodId,
            'merchant_key': installment.merchantKey,
            'title': installment.title,
            'installments_total': installment.total,
            'installment_cents': installment.installmentAmount.cents,
            'anchor_number': installment.anchorNumber,
            'anchor_line_date': _dateOnly(installment.anchorLineDate),
            if (installment.anchorDueDate != null) 'anchor_due_date': _dateOnly(installment.anchorDueDate!),
            'destination': _destinationToDb(installment.destination),
            if (isUuid(installment.categoryId)) 'category_id': installment.categoryId,
            if (isUuid(installment.assignedMemberId)) 'assigned_member_id': installment.assignedMemberId,
            'status': installment.status.name,
          },
    ],
    'installment_links': [
      for (final link in plan.installmentLinks)
        if (isUuid(link.expenseId) && isUuid(link.planId))
          {
            'expense_id': link.expenseId,
            'plan_id': link.planId,
            'number': link.number,
            'is_forecast': link.isForecast,
          },
    ],
    'forecast_deletions': [
      for (final id in plan.forecastDeletions)
        if (isUuid(id)) id,
    ],
  };
}

class SupabaseImportRepository implements ImportRepository {
  final SupabaseClient client;
  final String Function() getCurrentHouseId;

  SupabaseImportRepository({required this.client, required this.getCurrentHouseId});

  String get _houseId => getCurrentHouseId();

  /// A mensagem do próprio banco (ciclo fechado, empréstimo já pago) vai para a tela.
  Failure _failure(String action, Object error) => error is PostgrestException
      ? ServerFailure(error.message)
      : ServerFailure('$action: $error');

  @override
  Future<void> confirmImport(ImportSession session, ImportPlan plan) async {
    try {
      await client.rpc('confirm_import', params: {
        'p_import': importPayload(
          session,
          plan,
          houseId: _houseId,
          currentUserId: client.auth.currentUser?.id,
        ),
      });
    } catch (e) {
      throw _failure('Erro ao gravar a importação', e);
    }
  }

  @override
  Future<Set<String>> importedSignatures(String paymentMethodId) async {
    if (!isUuid(paymentMethodId)) return const {};
    try {
      final rows = await client
          .from('import_lines')
          .select('signature, import_batches!inner(payment_method_id, status)')
          .eq('house_id', _houseId)
          .eq('import_batches.payment_method_id', paymentMethodId)
          .eq('import_batches.status', 'confirmed')
          .neq('decision', 'skipped')
          .not('signature', 'is', null);
      return {for (final row in rows) row['signature'] as String};
    } catch (e) {
      throw _failure('Erro ao consultar importações anteriores', e);
    }
  }

  @override
  Future<List<ImportBatch>> getHistory({int limit = 20}) async {
    try {
      final rows = await client
          .from('import_batches')
          .select(
            'id, account_name, payment_method_id, file_name, invoice_due_date, total_cents, '
            'lines_count, status, created_at, import_lines(decision)',
          )
          .eq('house_id', _houseId)
          .order('created_at', ascending: false)
          .limit(limit);

      return [
        for (final row in rows)
          ImportBatch(
            id: row['id'] as String,
            sourceName: row['account_name'] as String? ?? '',
            paymentMethodId: row['payment_method_id'] as String?,
            fileName: row['file_name'] as String? ?? '',
            invoiceDueDate: DateTime.tryParse(row['invoice_due_date'] as String? ?? ''),
            total: Money((row['total_cents'] as num?)?.toInt() ?? 0),
            linesCount: (row['lines_count'] as num?)?.toInt() ?? 0,
            createdCount: ((row['import_lines'] as List?) ?? const [])
                .where((line) => (line as Map)['decision'] == 'created')
                .length,
            createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
            isUndone: row['status'] == 'undone',
          ),
      ];
    } catch (e) {
      throw _failure('Erro ao carregar o histórico de importações', e);
    }
  }

  @override
  Future<List<LoanPurchase>> purchasesOfLoan(String loanId) async {
    if (!isUuid(loanId)) return const [];
    try {
      final rows = await client
          .from('import_lines')
          .select('line_date, title, description, amount_cents, import_batches!inner(status)')
          .eq('house_id', _houseId)
          .eq('loan_id', loanId)
          .eq('import_batches.status', 'confirmed')
          .order('line_date');
      return [
        for (final row in rows)
          LoanPurchase(
            date: DateTime.parse(row['line_date'] as String),
            title: (row['title'] as String?) ?? (row['description'] as String? ?? ''),
            amount: Money((row['amount_cents'] as num).toInt()),
          ),
      ];
    } catch (e) {
      throw _failure('Erro ao carregar as compras do empréstimo', e);
    }
  }

  @override
  Future<List<InstallmentPlan>> installmentPlans(String paymentMethodId) async {
    if (!isUuid(paymentMethodId)) return const [];
    return _installmentPlans(paymentMethodId: paymentMethodId);
  }

  @override
  Future<List<InstallmentPlan>> houseInstallmentPlans() => _installmentPlans(activeOnly: true);

  @override
  Future<void> acceptInstallmentPlan(String planId) async {
    try {
      await client.rpc('accept_installment_plan', params: {'p_plan_id': planId});
    } catch (e) {
      throw _failure('Erro ao aceitar o parcelamento', e);
    }
  }

  @override
  Future<void> deleteInstallmentPurchase(String planId) async {
    try {
      await client.rpc('delete_installment_purchase', params: {'p_plan_id': planId});
    } catch (e) {
      throw _failure('Erro ao excluir a compra parcelada', e);
    }
  }

  @override
  Future<void> createInstallmentPurchase(InstallmentPurchase purchase) async {
    final plan = purchase.plan;
    final userId = client.auth.currentUser?.id;
    try {
      await client.rpc('create_installment_purchase', params: {
        'p_purchase': {
          'plan': {
            'id': plan.id,
            'house_id': _houseId,
            'payment_method_id': plan.paymentMethodId,
            'merchant_key': plan.merchantKey,
            'title': plan.title,
            'installments_total': plan.total,
            'installment_cents': plan.installmentAmount.cents,
            'anchor_number': plan.anchorNumber,
            'anchor_line_date': _dateOnly(plan.anchorLineDate),
            if (plan.anchorDueDate != null) 'anchor_due_date': _dateOnly(plan.anchorDueDate!),
            'destination': _destinationToDb(plan.destination),
            if (isUuid(plan.categoryId)) 'category_id': plan.categoryId,
            if (isUuid(plan.assignedMemberId)) 'assigned_member_id': plan.assignedMemberId,
          },
          'expenses': [
            for (final (index, expense) in purchase.expenses.indexed)
              {
                ...houseExpensePayload(expense, houseId: _houseId, currentUserId: userId),
                'installment_number': purchase.firstNumber + index,
              },
          ],
          'loans': [for (final loan in purchase.loans) p2pLoanPayload(loan, houseId: _houseId)],
        },
      });
    } catch (e) {
      throw _failure('Erro ao lançar a compra parcelada', e);
    }
  }

  Future<List<InstallmentPlan>> _installmentPlans({String? paymentMethodId, bool activeOnly = false}) async {
    try {
      var query = client.from('installment_plans').select().eq('house_id', _houseId);
      if (paymentMethodId != null) query = query.eq('payment_method_id', paymentMethodId);
      if (activeOnly) query = query.eq('status', 'active');
      final planRows = await query;
      // Plano cuja última parcela venceu há mais de dois meses já terminou
      final cutoff = DateTime.now().subtract(const Duration(days: 60));
      final rows = [
        for (final row in planRows)
          if (_lastDueOf(row)?.isBefore(cutoff) != true) row,
      ];
      if (rows.isEmpty) return const [];
      final ids = [for (final row in rows) row['id'] as String];

      final expenseRows = await client
          .from('house_expenses')
          .select('*, house_expense_items(*), split_rules(*)')
          .eq('house_id', _houseId)
          .inFilter('installment_plan_id', ids)
          .isFilter('deleted_at', null);
      final lineRows = await client
          .from('import_lines')
          .select('installment_plan_id, installment_number, import_batches!inner(status)')
          .eq('house_id', _houseId)
          .inFilter('installment_plan_id', ids)
          .eq('import_batches.status', 'confirmed')
          .neq('decision', 'skipped');

      final parcels = <String, Map<int, InstallmentParcel>>{};
      for (final row in expenseRows) {
        final number = (row['installment_number'] as num?)?.toInt();
        if (number == null) continue;
        parcels.putIfAbsent(row['installment_plan_id'] as String, () => {})[number] =
            InstallmentParcel(
          expense: houseExpenseFromRow(row),
          isForecast: row['is_forecast'] as bool? ?? false,
        );
      }
      final imported = <String, Set<int>>{};
      for (final row in lineRows) {
        final number = (row['installment_number'] as num?)?.toInt();
        if (number == null) continue;
        imported.putIfAbsent(row['installment_plan_id'] as String, () => {}).add(number);
      }

      return [
        for (final row in rows)
          InstallmentPlan(
            id: row['id'] as String,
            paymentMethodId: row['payment_method_id'] as String,
            merchantKey: row['merchant_key'] as String,
            title: row['title'] as String,
            total: (row['installments_total'] as num).toInt(),
            installmentAmount: Money((row['installment_cents'] as num).toInt()),
            anchorNumber: (row['anchor_number'] as num).toInt(),
            anchorLineDate: DateTime.parse(row['anchor_line_date'] as String),
            anchorDueDate: DateTime.tryParse(row['anchor_due_date'] as String? ?? ''),
            destination: _destinationFromDb(row['destination'] as String?),
            categoryId: row['category_id'] as String?,
            assignedMemberId: row['assigned_member_id'] as String?,
            status: _planStatusFromDb(row['status'] as String?),
            origin: row['origin'] == 'manual' ? InstallmentPlanOrigin.manual : InstallmentPlanOrigin.import,
            acceptedBy: row['accepted_by'] as String?,
            parcels: parcels[row['id']] ?? const {},
            importedNumbers: imported[row['id']] ?? const {},
          ),
      ];
    } catch (e) {
      throw _failure('Erro ao carregar as compras parceladas', e);
    }
  }

  static DateTime? _lastDueOf(Map<String, dynamic> row) {
    final anchorDue = DateTime.tryParse(row['anchor_due_date'] as String? ?? '');
    if (anchorDue == null) return null;
    return addMonths(
      anchorDue,
      (row['installments_total'] as num).toInt() - (row['anchor_number'] as num).toInt(),
    );
  }

  @override
  Future<void> undoImport(String batchId) async {
    try {
      await client.rpc('undo_import', params: {'p_batch_id': batchId});
    } catch (e) {
      throw _failure('Erro ao desfazer a importação', e);
    }
  }

  @override
  Future<List<ImportRule>> getRules(String paymentMethodId) async {
    if (!isUuid(paymentMethodId)) return const [];
    try {
      final rows = await client
          .from('import_rules')
          .select('id, match_key, merchant_name, destination, category_id, assigned_member_id')
          .eq('house_id', _houseId)
          .eq('payment_method_id', paymentMethodId)
          .order('merchant_name');
      return [
        for (final row in rows)
          ImportRule(
            id: row['id'] as String,
            matchKey: row['match_key'] as String,
            merchantName: row['merchant_name'] as String,
            destination: _destinationFromDb(row['destination'] as String?),
            categoryId: row['category_id'] as String?,
            assignedMemberId: row['assigned_member_id'] as String?,
          ),
      ];
    } catch (e) {
      throw _failure('Erro ao carregar as regras aprendidas', e);
    }
  }

  @override
  Future<void> saveRules(String paymentMethodId, List<ImportRule> rules) async {
    if (rules.isEmpty || !isUuid(paymentMethodId)) return;
    try {
      await client.from('import_rules').upsert(
        [
          for (final rule in rules)
            {
              'house_id': _houseId,
              'payment_method_id': paymentMethodId,
              'match_key': rule.matchKey,
              'merchant_name': rule.merchantName,
              'destination': _destinationToDb(rule.destination),
              'category_id': isUuid(rule.categoryId) ? rule.categoryId : null,
              'assigned_member_id': isUuid(rule.assignedMemberId) ? rule.assignedMemberId : null,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            },
        ],
        onConflict: 'house_id,payment_method_id,match_key',
      );
    } catch (e) {
      throw _failure('Erro ao guardar as regras aprendidas', e);
    }
  }

  @override
  Future<void> deleteRule(String ruleId) async {
    try {
      await client.from('import_rules').delete().eq('id', ruleId);
    } catch (e) {
      throw _failure('Erro ao excluir a regra', e);
    }
  }
}
