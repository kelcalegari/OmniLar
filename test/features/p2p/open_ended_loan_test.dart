import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/di/service_locator.dart';
import 'package:omni_lar/core/domain/value_objects/financial_cycle.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/features/finance/domain/entities/house_member.dart';
import 'package:omni_lar/features/finance/presentation/cubit/finance_cubit.dart';
import 'package:omni_lar/features/p2p/data/datasources/mock_p2p_datasource.dart';
import 'package:omni_lar/features/p2p/domain/entities/p2p_installment.dart';
import 'package:omni_lar/features/p2p/domain/entities/p2p_loan.dart';
import 'package:omni_lar/features/p2p/domain/services/p2p_calculator.dart';
import 'package:omni_lar/features/p2p/presentation/cubit/p2p_cubit.dart';
import 'package:omni_lar/features/p2p/presentation/pages/create_loan_page.dart';
import 'package:omni_lar/features/settlement/domain/services/global_clearing_engine.dart';

P2PLoan _openEndedLoan({String id = 'loan_livre', int totalCents = 30000, int paidCents = 0}) {
  return P2PLoan(
    id: id,
    title: 'Empréstimo livre',
    totalAmount: Money(totalCents),
    lenderMemberId: 'member_carlos',
    borrowerMemberId: 'member_marina',
    installmentsCount: 1,
    createdAt: DateTime(2026, 10, 1),
    firstDueDate: P2PLoan.openEndedPlaceholderDueDate,
    installments: P2PCalculator.buildOpenEndedInstallment(
      loanId: id,
      totalAmount: Money(totalCents),
      alreadyPaid: Money(paidCents),
    ),
    repaymentMode: LoanRepaymentMode.openEnded,
  );
}

void main() {
  group('Empréstimo sem prazo - domínio', () {
    test('Gera uma única parcela de saldo aberto sem vencimento real', () {
      final installments = P2PCalculator.buildOpenEndedInstallment(
        loanId: 'l1',
        totalAmount: const Money(30000),
      );

      expect(installments, hasLength(1));
      expect(installments.first.amount.cents, 30000);
      expect(installments.first.paidAmount.cents, 0);
      expect(installments.first.dueDate, P2PLoan.openEndedPlaceholderDueDate);
      expect(installments.first.status, InstallmentStatus.pending);
    });

    test('Registra abatimentos anteriores e limita ao total', () {
      final partial = P2PCalculator.buildOpenEndedInstallment(
        loanId: 'l1',
        totalAmount: const Money(30000),
        alreadyPaid: const Money(10000),
      );
      expect(partial.first.paidAmount.cents, 10000);
      expect(partial.first.remainingAmount.cents, 20000);

      final capped = P2PCalculator.buildOpenEndedInstallment(
        loanId: 'l1',
        totalAmount: const Money(30000),
        alreadyPaid: const Money(50000),
      );
      expect(capped.first.isFullyPaid, isTrue);
      expect(capped.first.paidAmount.cents, 30000);
    });

    test('Empréstimo sem prazo expõe a modalidade e o saldo devedor', () {
      final loan = _openEndedLoan(paidCents: 5000);
      expect(loan.isOpenEnded, isTrue);
      expect(loan.remainingAmount.cents, 25000);
      expect(loan.totalPaidAmount.cents, 5000);
      expect(loan.copyWith(title: 'x').repaymentMode, LoanRepaymentMode.openEnded);
    });

    test('Empréstimos parcelados continuam como padrão', () {
      final loan = P2PLoan(
        id: 'l2',
        title: 'Parcelado',
        totalAmount: const Money(10000),
        lenderMemberId: 'a',
        borrowerMemberId: 'b',
        installmentsCount: 1,
        createdAt: DateTime(2026, 10, 1),
        firstDueDate: DateTime(2026, 10, 20),
      );
      expect(loan.repaymentMode, LoanRepaymentMode.installments);
      expect(loan.isOpenEnded, isFalse);
    });

    test('Caixa da Casa é reconhecido como credor', () {
      final loan = _openEndedLoan().copyWith();
      expect(loan.isHouseLender, isFalse);
      final houseLoan = P2PLoan(
        id: 'l3',
        title: 'Reposição da Caixinha',
        totalAmount: const Money(10000),
        lenderMemberId: P2PLoan.houseLenderId,
        borrowerMemberId: 'member_marina',
        installmentsCount: 1,
        createdAt: DateTime(2026, 10, 1),
        firstDueDate: P2PLoan.openEndedPlaceholderDueDate,
        repaymentMode: LoanRepaymentMode.openEnded,
      );
      expect(houseLoan.isHouseLender, isTrue);
    });
  });

  group('Empréstimo sem prazo - abatimentos (datasource local)', () {
    test('Abatimentos livres reduzem o saldo até quitar', () async {
      final ds = MockP2PDataSource();
      await ds.createLoan(_openEndedLoan(id: 'loan_ab'));
      final instId = (await ds.getLoans()).firstWhere((l) => l.id == 'loan_ab').installments.first.id;

      await ds.payInstallment(instId, const Money(7000));
      var loan = (await ds.getLoans()).firstWhere((l) => l.id == 'loan_ab');
      expect(loan.remainingAmount.cents, 23000);
      expect(loan.status, LoanStatus.active);

      await ds.payInstallment(instId, const Money(23000));
      loan = (await ds.getLoans()).firstWhere((l) => l.id == 'loan_ab');
      expect(loan.remainingAmount.cents, 0);
      expect(loan.status, LoanStatus.paid);
    });

    test('Combinar parcelas converte o empréstimo sem prazo em parcelado', () async {
      final ds = MockP2PDataSource();
      await ds.createLoan(_openEndedLoan(id: 'loan_rn'));
      await ds.renegotiateLoan('loan_rn', 3, DateTime(2026, 11, 10));

      final loan = (await ds.getLoans()).firstWhere((l) => l.id == 'loan_rn');
      expect(loan.repaymentMode, LoanRepaymentMode.installments);
      expect(loan.remainingAmount.cents, 30000);
    });
  });

  group('Empréstimo sem prazo - Fechamento do Ciclo', () {
    const engine = GlobalClearingEngine();
    final cycle = FinancialCycle(
      start: DateTime(2026, 10, 5),
      end: DateTime(2026, 11, 4),
    );
    const members = [
      HouseMember(id: 'member_carlos', name: 'Carlos', role: 'owner'),
      HouseMember(id: 'member_marina', name: 'Marina', role: 'member'),
    ];

    P2PLoan loanDueInCycle(LoanRepaymentMode mode) => P2PLoan(
          id: 'loan_${mode.name}',
          title: 'Empréstimo',
          totalAmount: const Money(10000),
          lenderMemberId: 'member_carlos',
          borrowerMemberId: 'member_marina',
          installmentsCount: 1,
          createdAt: DateTime(2026, 10, 1),
          firstDueDate: DateTime(2026, 10, 20),
          installments: [
            P2PInstallment(
              id: 'inst_${mode.name}',
              loanId: 'loan_${mode.name}',
              number: 1,
              totalCount: 1,
              amount: const Money(10000),
              dueDate: DateTime(2026, 10, 20),
            ),
          ],
          repaymentMode: mode,
        );

    test('Parcelado com vencimento no ciclo entra no fechamento', () {
      final summary = engine.computeSettlement(
        cycle: cycle,
        members: members,
        expenses: const [],
        contributions: const [],
        loans: [loanDueInCycle(LoanRepaymentMode.installments)],
      );
      expect(summary.totalP2PCleared.cents, 10000);
    });

    test('Sem prazo nunca entra no fechamento, mesmo com data dentro do ciclo', () {
      final summary = engine.computeSettlement(
        cycle: cycle,
        members: members,
        expenses: const [],
        contributions: const [],
        loans: [loanDueInCycle(LoanRepaymentMode.openEnded), _openEndedLoan()],
      );
      expect(summary.totalP2PCleared.cents, 0);
      final marina = summary.memberBalances.firstWhere((m) => m.memberId == 'member_marina');
      expect(marina.p2pBorrowedDue.cents, 0);
    });
  });

  group('CreateLoanPage - modalidade sem prazo', () {
    setUpAll(() async {
      if (!sl.isRegistered<P2PCubit>()) {
        await initServiceLocator();
      }
    });

    Widget buildPage() {
      return MultiBlocProvider(
        providers: [
          BlocProvider.value(value: sl<P2PCubit>()),
          BlocProvider.value(value: sl<FinanceCubit>()),
        ],
        child: const MaterialApp(home: CreateLoanPage()),
      );
    }

    testWidgets('Escolher "Sem prazo" esconde parcelas e vencimento', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      expect(find.text('Número de Parcelas'), findsOneWidget);
      expect(find.text('Vencimento da 1ª Parcela'), findsOneWidget);

      await tester.tap(find.text('Sem prazo'));
      await tester.pumpAndSettle();

      expect(find.text('Número de Parcelas'), findsNothing);
      expect(find.text('Vencimento da 1ª Parcela'), findsNothing);
      expect(find.text('Empréstimo iniciado no passado?'), findsNothing);
      expect(find.text('Já houve abatimentos?'), findsOneWidget);
    });
  });
}
