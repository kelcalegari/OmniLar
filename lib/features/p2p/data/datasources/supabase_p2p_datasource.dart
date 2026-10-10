import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/domain/value_objects/money.dart';
import '../../../../core/errors/failures.dart';
import '../../domain/entities/p2p_loan.dart';
import '../../domain/entities/p2p_installment.dart';
import '../../domain/services/p2p_calculator.dart';
import 'p2p_datasource.dart';

class SupabaseP2PDataSource implements P2PDataSource {
  final SupabaseClient client;
  final String Function() getCurrentHouseId;

  SupabaseP2PDataSource({
    required this.client,
    required this.getCurrentHouseId,
  });

  String get _houseId => getCurrentHouseId();

  bool _isUuid(String id) {
    final uuidRegex = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    );
    return uuidRegex.hasMatch(id);
  }

  @override
  Future<List<P2PLoan>> getLoans() async {
    try {
      final rows = await client
          .from('p2p_loans')
          .select('*, p2p_installments(*)')
          .eq('house_id', _houseId)
          .order('created_at', ascending: false);

      return rows.map((r) {
        final rawInstallments = (r['p2p_installments'] as List<dynamic>? ?? []);
        final sortedInstallments = rawInstallments
            .map((i) => i as Map<String, dynamic>)
            .toList()
          ..sort((a, b) => ((a['installment_number'] as int?) ?? 0)
              .compareTo((b['installment_number'] as int?) ?? 0));

        final installmentsCount = (r['installments_count'] as int?) ?? 1;
        final installments = sortedInstallments.map((i) {
          final amountCents = (i['amount_cents'] as int?) ?? 0;
          final paidCents = (i['paid_cents'] as int?) ?? 0;
          final statusStr = (i['status'] as String?) ?? 'pending';
          final dueDateStr = i['due_date'] as String;
          final paidAtStr = i['paid_at'] as String?;

          return P2PInstallment(
            id: i['id'] as String,
            loanId: r['id'] as String,
            number: (i['installment_number'] as int?) ?? 1,
            totalCount: installmentsCount,
            amount: Money(amountCents),
            paidAmount: Money(paidCents),
            dueDate: DateTime.parse(dueDateStr),
            paidAt: paidAtStr != null ? DateTime.tryParse(paidAtStr) : null,
            isForgiven: statusStr == 'forgiven',
            isCancelled: statusStr == 'renegotiated',
          );
        }).toList();

        final statusStr = (r['status'] as String?) ?? 'active';
        LoanStatus status;
        switch (statusStr) {
          case 'completed':
            status = LoanStatus.paid;
            break;
          case 'forgiven':
            status = LoanStatus.forgiven;
            break;
          case 'renegotiated':
            status = LoanStatus.renegotiated;
            break;
          case 'pendingAcceptance':
          case 'pending':
            status = LoanStatus.pendingAcceptance;
            break;
          default:
            status = LoanStatus.active;
        }

        final createdAt = DateTime.parse(r['created_at'] as String);
        final firstDueDate = installments.isNotEmpty
            ? installments.first.dueDate
            : createdAt;

        return P2PLoan(
          id: r['id'] as String,
          title: r['title'] as String,
          description: r['description'] as String?,
          totalAmount: Money((r['total_amount_cents'] as int?) ?? 0),
          lenderMemberId: r['lender_id'] as String,
          borrowerMemberId: r['borrower_id'] as String,
          installmentsCount: installmentsCount,
          createdAt: createdAt,
          firstDueDate: firstDueDate,
          status: status,
          installments: installments,
          attachmentUrl: r['attachment_url'] as String?,
        );
      }).toList();
    } catch (e) {
      throw ServerFailure('Erro ao carregar empréstimos P2P: $e');
    }
  }

  @override
  Future<void> createLoan(P2PLoan loan) async {
    try {
      final currentUserId = client.auth.currentUser?.id;
      final loanData = {
        if (_isUuid(loan.id)) 'id': loan.id,
        'house_id': _houseId,
        'lender_id': loan.lenderMemberId,
        'borrower_id': loan.borrowerMemberId,
        'title': loan.title,
        'description': loan.description,
        'total_amount_cents': loan.totalAmount.cents,
        'installments_count': loan.installmentsCount,
        'status': loan.status == LoanStatus.paid
            ? 'completed'
            : loan.status == LoanStatus.forgiven
                ? 'forgiven'
                : loan.status == LoanStatus.renegotiated
                    ? 'renegotiated'
                    : 'active',
        'created_by': currentUserId ?? loan.lenderMemberId,
        'created_at': loan.createdAt.toIso8601String(),
      };

      final insertedLoan = await client
          .from('p2p_loans')
          .insert(loanData)
          .select('id')
          .single();

      final realLoanId = insertedLoan['id'] as String;

      final installmentsToInsert = loan.installments.isNotEmpty
          ? loan.installments
          : P2PCalculator.generateInstallments(
              loanId: realLoanId,
              totalAmount: loan.totalAmount,
              installmentsCount: loan.installmentsCount,
              firstDueDate: loan.firstDueDate,
            );

      final installmentRows = installmentsToInsert.map((inst) {
        return {
          if (_isUuid(inst.id)) 'id': inst.id,
          'loan_id': realLoanId,
          'installment_number': inst.number,
          'amount_cents': inst.amount.cents,
          'paid_cents': inst.paidAmount.cents,
          'due_date': inst.dueDate.toIso8601String().split('T')[0],
          'status': inst.isForgiven
              ? 'forgiven'
              : inst.isCancelled
                  ? 'renegotiated'
                  : inst.isFullyPaid
                      ? 'paid'
                      : inst.paidAmount.isPositive
                          ? 'partial'
                          : 'pending',
          'paid_at': inst.paidAt?.toIso8601String(),
        };
      }).toList();

      if (installmentRows.isNotEmpty) {
        await client.from('p2p_installments').insert(installmentRows);
      }
    } catch (e) {
      throw ServerFailure('Erro ao criar empréstimo P2P: $e');
    }
  }

  @override
  Future<void> payInstallment(String installmentId, Money amount) async {
    try {
      // 1. Invoca a RPC de pagamento seguro no Supabase
      await client.rpc('pay_p2p_installment', params: {
        'p_installment_id': installmentId,
        'p_amount_cents': amount.cents,
      });

      // 2. Verifica se todas as parcelas deste empréstimo foram quitadas para atualizar o status do empréstimo para 'completed'
      final instRow = await client
          .from('p2p_installments')
          .select('loan_id')
          .eq('id', installmentId)
          .single();
      final loanId = instRow['loan_id'] as String;

      final remainingInstallments = await client
          .from('p2p_installments')
          .select('id, status')
          .eq('loan_id', loanId)
          .neq('status', 'paid');

      if (remainingInstallments.isEmpty) {
        await client
            .from('p2p_loans')
            .update({'status': 'completed'})
            .eq('id', loanId);
      }
    } catch (e) {
      throw ServerFailure('Erro ao registrar pagamento de parcela P2P: $e');
    }
  }

  @override
  Future<void> forgiveLoan(String loanId) async {
    try {
      await client
          .from('p2p_loans')
          .update({'status': 'forgiven'})
          .eq('id', loanId);

      await client
          .from('p2p_installments')
          .update({'status': 'forgiven'})
          .eq('loan_id', loanId)
          .neq('status', 'paid');
    } catch (e) {
      throw ServerFailure('Erro ao perdoar empréstimo P2P: $e');
    }
  }

  @override
  Future<void> renegotiateLoan(
    String loanId,
    int newInstallmentsCount,
    DateTime newFirstDueDate,
  ) async {
    try {
      final rows = await client
          .from('p2p_installments')
          .select()
          .eq('loan_id', loanId)
          .order('installment_number', ascending: true);

      int remainingCents = 0;
      int paidCount = 0;

      for (final r in rows) {
        final amountCents = r['amount_cents'] as int;
        final paidCents = r['paid_cents'] as int? ?? 0;
        final status = r['status'] as String? ?? 'pending';

        if (status == 'paid' || paidCents >= amountCents) {
          paidCount++;
        } else if (status != 'forgiven' && status != 'renegotiated') {
          remainingCents += (amountCents - paidCents);
        }
      }

      if (remainingCents <= 0) {
        throw const ServerFailure('Não há saldo remanescente a ser renegociado.');
      }

      // Marca parcelas pendentes como 'renegotiated'
      await client
          .from('p2p_installments')
          .update({'status': 'renegotiated'})
          .eq('loan_id', loanId)
          .neq('status', 'paid')
          .neq('status', 'forgiven');

      final remainingMoney = Money(remainingCents);
      final splitAmounts = remainingMoney.splitEqually(newInstallmentsCount);
      final totalCombinedCount = paidCount + newInstallmentsCount;

      final newRows = <Map<String, dynamic>>[];
      for (int i = 0; i < newInstallmentsCount; i++) {
        final dueMonth = newFirstDueDate.month + i;
        final dueYear = newFirstDueDate.year + ((dueMonth - 1) ~/ 12);
        final normalizedMonth = ((dueMonth - 1) % 12) + 1;
        final maxDayInMonth = DateTime(dueYear, normalizedMonth + 1, 0).day;
        final safeDay = newFirstDueDate.day > maxDayInMonth ? maxDayInMonth : newFirstDueDate.day;
        final dueDate = DateTime(dueYear, normalizedMonth, safeDay);

        newRows.add({
          'loan_id': loanId,
          'installment_number': paidCount + i + 1,
          'amount_cents': splitAmounts[i].cents,
          'paid_cents': 0,
          'due_date': dueDate.toIso8601String().split('T')[0],
          'status': 'pending',
        });
      }

      await client.from('p2p_installments').insert(newRows);

      await client.from('p2p_loans').update({
        'status': 'renegotiated',
        'installments_count': totalCombinedCount,
      }).eq('id', loanId);
    } catch (e) {
      if (e is Failure) rethrow;
      throw ServerFailure('Erro ao renegociar empréstimo P2P: $e');
    }
  }
}
