import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/features/p2p/domain/entities/p2p_installment.dart';
import 'package:omni_lar/features/p2p/domain/entities/p2p_loan.dart';
import 'package:omni_lar/features/p2p/presentation/cubit/p2p_state.dart';

void main() {
  group('P2PState House Loans and Settled Loans Visibility', () {
    const currentUserId = 'user_me';
    const otherMember1 = 'user_cris';
    const otherMember2 = 'user_lucas';

    test('houseLoans filters active loans where the house is the lender', () {
      final houseLoanActive = P2PLoan(
        id: 'h_loan_1',
        title: 'Empréstimo da Casa para Cris',
        totalAmount: const Money(50000), // R$ 500,00
        lenderMemberId: P2PLoan.houseLenderId,
        borrowerMemberId: otherMember1,
        installmentsCount: 1,
        createdAt: DateTime(2026, 10, 1),
        firstDueDate: DateTime(2026, 10, 15),
        status: LoanStatus.active,
        installments: [
          P2PInstallment(
            id: 'h_inst_1',
            loanId: 'h_loan_1',
            number: 1,
            totalCount: 1,
            dueDate: DateTime(2026, 10, 15),
            amount: const Money(50000),
            paidAmount: const Money(10000), // R$ 100,00 pago, R$ 400,00 restante
          ),
        ],
      );

      final p2pLoanBetweenOthers = P2PLoan(
        id: 'p2p_loan_1',
        title: 'P2P Cris para Lucas',
        totalAmount: const Money(30000),
        lenderMemberId: otherMember1,
        borrowerMemberId: otherMember2,
        installmentsCount: 1,
        createdAt: DateTime(2026, 10, 1),
        firstDueDate: DateTime(2026, 10, 15),
        status: LoanStatus.active,
        installments: [
          P2PInstallment(
            id: 'p2p_inst_1',
            loanId: 'p2p_loan_1',
            number: 1,
            totalCount: 1,
            dueDate: DateTime(2026, 10, 15),
            amount: const Money(30000),
          ),
        ],
      );

      final state = P2PState(
        allLoans: [houseLoanActive, p2pLoanBetweenOthers],
        currentUserId: currentUserId,
      );

      // Apenas o empréstimo da casa aparece em houseLoans
      expect(state.houseLoans.length, 1);
      expect(state.houseLoans.first.id, 'h_loan_1');
      expect(state.houseLoans.first.isHouseLender, isTrue);

      // totalHouseLoansPending reflete o saldo devedor restante (R$ 400,00)
      expect(state.totalHouseLoansPending.cents, 40000);
    });

    test('settledLoans shows all liquidated loans in the house, regardless of who is viewing', () {
      final settledBetweenOthers = P2PLoan(
        id: 'settled_1',
        title: 'Quitado entre Cris e Lucas',
        totalAmount: const Money(20000),
        lenderMemberId: otherMember1,
        borrowerMemberId: otherMember2,
        installmentsCount: 1,
        createdAt: DateTime(2026, 9, 1),
        firstDueDate: DateTime(2026, 9, 15),
        status: LoanStatus.paid,
        installments: [
          P2PInstallment(
            id: 's_inst_1',
            loanId: 'settled_1',
            number: 1,
            totalCount: 1,
            dueDate: DateTime(2026, 9, 15),
            amount: const Money(20000),
            paidAmount: const Money(20000),
            paidAt: DateTime(2026, 9, 14),
          ),
        ],
      );

      final settledWithHouse = P2PLoan(
        id: 'settled_house',
        title: 'Quitado com o Caixa da Casa',
        totalAmount: const Money(100000),
        lenderMemberId: P2PLoan.houseLenderId,
        borrowerMemberId: otherMember1,
        installmentsCount: 1,
        createdAt: DateTime(2026, 9, 1),
        firstDueDate: DateTime(2026, 9, 15),
        status: LoanStatus.paid,
        installments: [
          P2PInstallment(
            id: 's_inst_h',
            loanId: 'settled_house',
            number: 1,
            totalCount: 1,
            dueDate: DateTime(2026, 9, 15),
            amount: const Money(100000),
            paidAmount: const Money(100000),
            paidAt: DateTime(2026, 9, 10),
          ),
        ],
      );

      final activeLoan = P2PLoan(
        id: 'active_1',
        title: 'Ainda em Aberto',
        totalAmount: const Money(15000),
        lenderMemberId: otherMember1,
        borrowerMemberId: otherMember2,
        installmentsCount: 1,
        createdAt: DateTime(2026, 10, 1),
        firstDueDate: DateTime(2026, 10, 15),
        status: LoanStatus.active,
        installments: [
          P2PInstallment(
            id: 'a_inst_1',
            loanId: 'active_1',
            number: 1,
            totalCount: 1,
            dueDate: DateTime(2026, 10, 15),
            amount: const Money(15000),
          ),
        ],
      );

      final state = P2PState(
        allLoans: [settledBetweenOthers, settledWithHouse, activeLoan],
        currentUserId: currentUserId, // current user não é nem credor nem devedor desses empréstimos
      );

      // Na aba Quitados, todos os empréstimos quitados da casa devem estar visíveis
      expect(state.settledLoans.length, 2);
      expect(state.settledLoans.map((l) => l.id).toSet(), {'settled_1', 'settled_house'});
      expect(state.allSettledLoans.length, 2);
    });

    test('loansTheyOweMe excludes house loans because the house is the lender', () {
      final houseLoan = P2PLoan(
        id: 'h_loan_me',
        title: 'Empréstimo da Casa para Cris',
        totalAmount: const Money(50000),
        lenderMemberId: P2PLoan.houseLenderId,
        borrowerMemberId: otherMember1,
        installmentsCount: 1,
        createdAt: DateTime(2026, 10, 1),
        firstDueDate: DateTime(2026, 10, 15),
        status: LoanStatus.active,
        installments: [
          P2PInstallment(
            id: 'h_inst_me',
            loanId: 'h_loan_me',
            number: 1,
            totalCount: 1,
            dueDate: DateTime(2026, 10, 15),
            amount: const Money(50000),
          ),
        ],
      );

      final personalLoanIlent = P2PLoan(
        id: 'p_loan_me',
        title: 'Eu emprestei para Cris',
        totalAmount: const Money(25000),
        lenderMemberId: currentUserId,
        borrowerMemberId: otherMember1,
        installmentsCount: 1,
        createdAt: DateTime(2026, 10, 1),
        firstDueDate: DateTime(2026, 10, 15),
        status: LoanStatus.active,
        installments: [
          P2PInstallment(
            id: 'p_inst_me',
            loanId: 'p_loan_me',
            number: 1,
            totalCount: 1,
            dueDate: DateTime(2026, 10, 15),
            amount: const Money(25000),
          ),
        ],
      );

      final state = P2PState(
        allLoans: [houseLoan, personalLoanIlent],
        currentUserId: currentUserId,
      );

      // loansTheyOweMe traz apenas empréstimos pessoais do usuário
      expect(state.loansTheyOweMe.length, 1);
      expect(state.loansTheyOweMe.first.id, 'p_loan_me');
    });
  });
}
