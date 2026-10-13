import 'p2p_loan_payload.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/domain/value_objects/money.dart';
import '../../../../core/errors/failures.dart';
import '../../domain/entities/p2p_loan.dart';
import '../../domain/entities/p2p_installment.dart';
import '../../domain/entities/p2p_payment_record.dart';
import 'p2p_datasource.dart';

class SupabaseP2PDataSource implements P2PDataSource {
  final SupabaseClient client;
  final String Function() getCurrentHouseId;

  SupabaseP2PDataSource({
    required this.client,
    required this.getCurrentHouseId,
  });

  String get _houseId => getCurrentHouseId();

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
            paidAt: paidAtStr != null ? DateTime.tryParse(paidAtStr)?.toLocal() : null,
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

        final repaymentMode = (r['repayment_mode'] as String?) == 'open_ended'
            ? LoanRepaymentMode.openEnded
            : LoanRepaymentMode.installments;
        final lenderIsHouse = (r['lender_is_house'] as bool?) ?? false;
        final lenderId = lenderIsHouse || r['lender_id'] == null
            ? P2PLoan.houseLenderId
            : r['lender_id'] as String;

        final createdAt = DateTime.parse(r['created_at'] as String).toLocal();
        final firstDueDate = installments.isNotEmpty
            ? installments.first.dueDate
            : createdAt;

        return P2PLoan(
          repayToVaultId: r['repay_to_vault_id'] as String?,
          id: r['id'] as String,
          title: r['title'] as String,
          description: r['description'] as String?,
          totalAmount: Money((r['total_amount_cents'] as int?) ?? 0),
          lenderMemberId: lenderId,
          borrowerMemberId: r['borrower_id'] as String,
          installmentsCount: installmentsCount,
          createdAt: createdAt,
          firstDueDate: firstDueDate,
          status: status,
          installments: installments,
          attachmentUrl: r['attachment_url'] as String?,
          repaymentMode: repaymentMode,
          settleInCycle: (r['settle_in_cycle'] as bool?) ?? true,
        );
      }).toList();
    } catch (e) {
      throw ServerFailure('Erro ao carregar empréstimos P2P: $e');
    }
  }

  @override
  Future<void> createLoan(P2PLoan loan) async {
    try {
      // Empréstimo e parcelas entram juntos: ou tudo, ou nada
      await client.rpc('create_p2p_loan', params: {
        'p_loan': p2pLoanPayload(loan, houseId: _houseId),
      });
    } catch (e) {
      throw ServerFailure('Erro ao criar empréstimo P2P: $e');
    }
  }

  @override
  Future<void> payInstallment(String installmentId, Money amount, {String? vaultId}) async {
    try {
      // Acordo com o Lar pago para uma Caixinha: a baixa e o depósito vão juntos
      if (vaultId != null) {
        await client.rpc('pay_house_loan_to_vault', params: {
          'p_vault_id': vaultId,
          'p_amount_cents': amount.cents,
          'p_installment_id': installmentId,
        });
        return;
      }
      // A RPC grava o ledger, baixa a parcela e marca o empréstimo como
      // 'completed' quando não sobra nada em aberto.
      await client.rpc('pay_p2p_installment', params: {
        'p_installment_id': installmentId,
        'p_amount_cents': amount.cents,
      });
    } catch (e) {
      throw ServerFailure('Erro ao registrar pagamento de parcela P2P: $e');
    }
  }

  @override
  Future<void> forgiveLoan(String loanId) async {
    try {
      // Só o credor (ou o admin, no Caixa da Casa) pode perdoar: validado na RPC.
      await client.rpc('forgive_p2p_loan', params: {'p_loan_id': loanId});
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
      // A RPC reparcela o saldo em aberto em uma única transação.
      await client.rpc('renegotiate_p2p_loan', params: {
        'p_loan_id': loanId,
        'p_installments_count': newInstallmentsCount,
        'p_first_due_date': newFirstDueDate.toIso8601String().split('T')[0],
      });
    } catch (e) {
      if (e is Failure) rethrow;
      throw ServerFailure('Erro ao renegociar empréstimo P2P: $e');
    }
  }

  @override
  Future<void> deleteLoan(String loanId) async {
    try {
      await client.from('p2p_loans').delete().eq('id', loanId);
    } catch (e) {
      if (e is Failure) rethrow;
      throw ServerFailure('Erro ao excluir empréstimo P2P: $e');
    }
  }

  @override
  Future<List<P2PPaymentRecord>> getLoanPayments(String loanId) async {
    try {
      final rows = await client
          .from('payment_allocations')
          .select('allocated_cents, created_at, p2p_installments!inner(loan_id)')
          .eq('p2p_installments.loan_id', loanId)
          .order('created_at', ascending: false);

      return rows.map((r) {
        return P2PPaymentRecord(
          amount: Money((r['allocated_cents'] as int?) ?? 0),
          paidAt: DateTime.parse(r['created_at'] as String).toLocal(),
        );
      }).toList();
    } catch (e) {
      throw ServerFailure('Erro ao carregar histórico de pagamentos P2P: $e');
    }
  }

  @override
  Future<void> payLoan(String loanId, Money amount, {String? vaultId}) async {
    try {
      if (vaultId != null) {
        await client.rpc('pay_house_loan_to_vault', params: {
          'p_vault_id': vaultId,
          'p_amount_cents': amount.cents,
          'p_loan_id': loanId,
        });
        return;
      }
      // A RPC distribui o valor das parcelas mais antigas para as mais novas
      // e marca o empréstimo como 'completed' quando o saldo zera.
      await client.rpc('pay_p2p_loan', params: {
        'p_loan_id': loanId,
        'p_amount_cents': amount.cents,
      });
    } catch (e) {
      throw ServerFailure('Erro ao registrar abatimento do empréstimo P2P: $e');
    }
  }

  @override
  Future<void> setSettleInCycle(String loanId, bool settleInCycle) async {
    try {
      await client
          .from('p2p_loans')
          .update({'settle_in_cycle': settleInCycle})
          .eq('id', loanId);
    } catch (e) {
      throw ServerFailure('Erro ao atualizar cobrança no ciclo do empréstimo P2P: $e');
    }
  }
}
