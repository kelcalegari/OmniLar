import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/features/auth/domain/entities/user_profile.dart';
import 'package:omni_lar/features/auth/domain/repositories/auth_repository.dart';
import 'package:omni_lar/features/p2p/domain/entities/p2p_loan.dart';
import 'package:omni_lar/features/p2p/domain/entities/p2p_payment_record.dart';
import 'package:omni_lar/features/p2p/domain/entities/p2p_installment.dart';
import 'package:omni_lar/features/p2p/domain/repositories/p2p_repository.dart';
import 'package:omni_lar/features/p2p/presentation/cubit/p2p_cubit.dart';
import 'package:omni_lar/features/p2p/presentation/cubit/p2p_state.dart';

class MockP2PRepoForTest implements P2PRepository {
  final List<P2PLoan> loans = [];

  @override
  Future<List<P2PLoan>> getLoans() async => List.unmodifiable(loans);

  @override
  Future<void> createLoan(P2PLoan loan) async => loans.add(loan);

  @override
  Future<void> deleteLoan(String loanId) async => loans.removeWhere((l) => l.id == loanId);

  @override
  Future<void> forgiveLoan(String loanId) async {}

  @override
  Future<void> payLoan(String loanId, Money amount) async {}

  @override
  Future<void> setSettleInCycle(String loanId, bool settleInCycle) async {}

  @override
  Future<List<P2PPaymentRecord>> getLoanPayments(String loanId) async => const [];

  @override
  Future<void> payInstallment(String installmentId, Money amount) async {}

  @override
  Future<void> renegotiateLoan(String loanId, int newInstallmentsCount, DateTime newFirstDueDate) async {}
}

class FakeAuthRepoForTest implements AuthRepository {
  UserProfile? user;
  bool isDemo = false;

  @override
  Stream<UserProfile?> get authStateChanges => const Stream.empty();

  @override
  UserProfile? get currentUser => user;

  @override
  bool get isDemoMode => isDemo;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('P2PCubit - Resolução Dinâmica de Usuário Autenticado e Partes', () {
    late MockP2PRepoForTest repo;
    late FakeAuthRepoForTest auth;
    final realUserUuid = 'e8a09f12-1234-4567-89ab-cdef01234567';
    final otherUserUuid = '77b08a34-9876-5432-10fe-dcba98765432';

    setUp(() {
      repo = MockP2PRepoForTest();
      auth = FakeAuthRepoForTest();
      auth.user = const UserProfile(
        id: 'e8a09f12-1234-4567-89ab-cdef01234567',
        email: 'kelvyn@test.com',
        fullName: 'Kelvyn',
      );
      auth.isDemo = false;
    });

    test('loadLoans resolve automaticamente o UUID do usuário logado e popula Eu Devo / Me Devem', () async {
      final loanWhereIAmLender = P2PLoan(
        id: 'loan_1',
        title: 'Empréstimo Feito por Mim',
        totalAmount: const Money(15000),
        lenderMemberId: realUserUuid,
        borrowerMemberId: otherUserUuid,
        installmentsCount: 1,
        createdAt: DateTime.now(),
        firstDueDate: DateTime.now(),
        installments: [
          P2PInstallment(
            id: 'inst_1',
            loanId: 'loan_1',
            number: 1,
            totalCount: 1,
            amount: const Money(15000),
            dueDate: DateTime.now(),
          ),
        ],
      );

      final loanWhereIAmDebtor = P2PLoan(
        id: 'loan_2',
        title: 'Empréstimo Que Tomei',
        totalAmount: const Money(8000),
        lenderMemberId: otherUserUuid,
        borrowerMemberId: realUserUuid,
        installmentsCount: 1,
        createdAt: DateTime.now(),
        firstDueDate: DateTime.now(),
        installments: [
          P2PInstallment(
            id: 'inst_2',
            loanId: 'loan_2',
            number: 1,
            totalCount: 1,
            amount: const Money(8000),
            dueDate: DateTime.now(),
          ),
        ],
      );

      repo.loans.addAll([loanWhereIAmLender, loanWhereIAmDebtor]);

      final cubit = P2PCubit(repo, auth);
      await cubit.loadLoans();

      expect(cubit.state.status, P2PStatus.success);
      expect(cubit.state.currentUserId, equals(realUserUuid));

      // Credor: Me Devem (loanWhereIAmLender)
      expect(cubit.state.loansTheyOweMe.length, equals(1));
      expect(cubit.state.loansTheyOweMe.first.id, equals('loan_1'));
      expect(cubit.state.totalTheyOweMe.cents, equals(15000));

      // Devedor: Eu Devo (loanWhereIAmDebtor)
      expect(cubit.state.loansIDowe.length, equals(1));
      expect(cubit.state.loansIDowe.first.id, equals('loan_2'));
      expect(cubit.state.totalIDowe.cents, equals(8000));

      // Saldo líquido
      expect(cubit.state.netBalance.cents, equals(7000)); // 15000 - 8000
    });

    test('deleteLoan exclui o empréstimo e atualiza os saldos', () async {
      final loan = P2PLoan(
        id: 'loan_to_delete',
        title: 'Teste Exclusão',
        totalAmount: const Money(5000),
        lenderMemberId: realUserUuid,
        borrowerMemberId: otherUserUuid,
        installmentsCount: 1,
        createdAt: DateTime.now(),
        firstDueDate: DateTime.now(),
      );
      repo.loans.add(loan);

      final cubit = P2PCubit(repo, auth);
      await cubit.loadLoans();
      expect(cubit.state.allLoans.length, equals(1));

      await cubit.deleteLoan('loan_to_delete');
      expect(cubit.state.allLoans.isEmpty, isTrue);
      expect(cubit.state.loansTheyOweMe.isEmpty, isTrue);
    });
  });
}
