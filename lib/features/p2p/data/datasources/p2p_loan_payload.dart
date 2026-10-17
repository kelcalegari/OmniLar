import '../../../../core/utils/uuid.dart';
import '../../domain/entities/p2p_loan.dart';
import '../../domain/services/p2p_calculator.dart';

/// Empréstimo com as parcelas no formato da RPC `create_p2p_loan`, que grava
/// os dois em uma transação. Empréstimo sem parcelas ganha as parcelas aqui.
Map<String, dynamic> p2pLoanPayload(P2PLoan loan, {required String houseId}) {
  final installments = loan.installments.isNotEmpty
      ? loan.installments
      : loan.isOpenEnded
          ? P2PCalculator.buildOpenEndedInstallment(
              loanId: loan.id,
              totalAmount: loan.totalAmount,
            )
          : P2PCalculator.generateInstallments(
              loanId: loan.id,
              totalAmount: loan.totalAmount,
              installmentsCount: loan.installmentsCount,
              firstDueDate: loan.firstDueDate,
            );

  return {
    if (isUuid(loan.id)) 'id': loan.id,
    'house_id': houseId,
    if (!loan.isHouseLender) 'lender_id': loan.lenderMemberId,
    'lender_is_house': loan.isHouseLender,
    // Caixinha passa por create_house_loan, que faz o saque junto
    if (loan.isHouseLender && loan.houseFunding == HouseLoanFunding.cycle && loan.fundedOn != null) ...{
      'house_funding': 'cycle',
      'funded_on': loan.fundedOn!.toIso8601String().split('T')[0],
    },
    'repayment_mode': loan.isOpenEnded ? 'open_ended' : 'installments',
    'settle_in_cycle': loan.settleInCycle,
    'borrower_id': loan.borrowerMemberId,
    'title': loan.title,
    if (loan.description != null) 'description': loan.description,
    'total_amount_cents': loan.totalAmount.cents,
    'installments_count': loan.installmentsCount,
    'status': loan.status == LoanStatus.paid
        ? 'completed'
        : loan.status == LoanStatus.forgiven
            ? 'forgiven'
            : loan.status == LoanStatus.renegotiated
                ? 'renegotiated'
                : 'active',
    'created_at': loan.createdAt.toUtc().toIso8601String(),
    'installments': [
      for (final inst in installments)
        {
          if (isUuid(inst.id)) 'id': inst.id,
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
          if (inst.paidAt != null) 'paid_at': inst.paidAt!.toUtc().toIso8601String(),
        },
    ],
  };
}
