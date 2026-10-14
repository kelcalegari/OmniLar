import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/domain/value_objects/money.dart';
import '../../../core/errors/failures.dart';
import '../../../core/utils/uuid.dart';
import '../../finance/data/datasources/house_expense_payload.dart';
import '../../p2p/data/datasources/p2p_loan_payload.dart';
import '../domain/entities/imported_statement_line.dart';
import '../domain/repositories/import_repository.dart';
import '../domain/services/import_session.dart';

String _dateOnly(DateTime date) => date.toIso8601String().split('T')[0];

String _destinationToDb(LineDestination destination) => switch (destination) {
      LineDestination.house => 'house',
      LineDestination.splitP2P => 'p2p_loan',
      LineDestination.cardOwnerPersonal => 'personal',
      LineDestination.ignored => 'ignored',
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
        },
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
  Future<void> undoImport(String batchId) async {
    try {
      await client.rpc('undo_import', params: {'p_batch_id': batchId});
    } catch (e) {
      throw _failure('Erro ao desfazer a importação', e);
    }
  }
}
