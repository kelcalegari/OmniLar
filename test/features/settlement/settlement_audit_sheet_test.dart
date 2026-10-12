import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/domain/value_objects/financial_cycle.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/features/settlement/domain/entities/member_audit_trail.dart';
import 'package:omni_lar/features/settlement/domain/entities/member_net_balance.dart';
import 'package:omni_lar/features/settlement/domain/entities/settlement_summary.dart';
import 'package:omni_lar/features/settlement/domain/entities/super_pix_transfer.dart';
import 'package:omni_lar/features/settlement/presentation/widgets/settlement_audit_sheet.dart';

void main() {
  group('SettlementAuditSheet Widget Tests', () {
    final cycle = FinancialCycle(
      start: DateTime(2026, 10, 5),
      end: DateTime(2026, 11, 4),
    );

    final auditKelvynn = MemberAuditTrail(
      memberId: 'm_kelvynn',
      memberName: 'Kelvynn',
      expenseShares: [
        ExpenseShareAudit(
          expenseId: 'e1',
          expenseTitle: 'Aluguel do Lar',
          totalExpenseAmount: const Money(200000),
          allocatedAmount: const Money(100000),
          ruleDescription: '50% da despesa',
          date: DateTime(2026, 10, 10),
        ),
      ],
      contributionsMade: [
        ContributionAudit(
          contributionId: 'c1',
          amount: const Money(30000),
          date: DateTime(2026, 10, 12),
        ),
      ],
      outOfPocketExpenses: [
        OutOfPocketAudit(
          expenseId: 'e2',
          title: 'Conta de Energia',
          amount: const Money(25000),
          date: DateTime(2026, 10, 15),
        ),
      ],
      p2pReceivables: const [],
      p2pPayables: [
        P2PInstallmentAudit(
          loanId: 'l1',
          description: 'Jogo Nintendo',
          otherMemberId: 'm_cris',
          otherMemberName: 'Cris',
          installmentNumber: 1,
          totalInstallments: 2,
          amount: const Money(5000),
          dueDate: DateTime(2026, 10, 20),
          isReceivable: false,
        ),
      ],
      contributionDue: const Money(100000),
      contributionPaid: const Money(30000),
      outOfPocketTotal: const Money(25000),
      p2pLentTotal: const Money.zero(),
      p2pBorrowedTotal: const Money(5000),
      // (250 - (1000 - 300)) - 50 = 250 - 700 - 50 = -500
      netBalance: const Money(-50000),
    );

    final auditCris = MemberAuditTrail(
      memberId: 'm_cris',
      memberName: 'Cris',
      expenseShares: [
        ExpenseShareAudit(
          expenseId: 'e1',
          expenseTitle: 'Aluguel do Lar',
          totalExpenseAmount: const Money(200000),
          allocatedAmount: const Money(100000),
          ruleDescription: '50% da despesa',
          date: DateTime(2026, 10, 10),
        ),
      ],
      contributionsMade: const [],
      outOfPocketExpenses: const [],
      p2pReceivables: [
        P2PInstallmentAudit(
          loanId: 'l1',
          description: 'Jogo Nintendo',
          otherMemberId: 'm_kelvynn',
          otherMemberName: 'Kelvynn',
          installmentNumber: 1,
          totalInstallments: 2,
          amount: const Money(5000),
          dueDate: DateTime(2026, 10, 20),
          isReceivable: true,
        ),
      ],
      p2pPayables: const [],
      contributionDue: const Money(100000),
      contributionPaid: const Money.zero(),
      outOfPocketTotal: const Money.zero(),
      p2pLentTotal: const Money(5000),
      p2pBorrowedTotal: const Money.zero(),
      netBalance: const Money(-95000),
    );

    final summary = SettlementSummary(
      cycle: cycle,
      memberBalances: [
        const MemberNetBalance(
          memberId: 'm_kelvynn',
          memberName: 'Kelvynn',
          contributionDue: Money(100000),
          contributionPaid: Money(30000),
          outOfPocketExpenses: Money(25000),
          p2pLentDue: Money.zero(),
          p2pBorrowedDue: Money(5000),
        ),
        const MemberNetBalance(
          memberId: 'm_cris',
          memberName: 'Cris',
          contributionDue: Money(100000),
          contributionPaid: Money.zero(),
          outOfPocketExpenses: Money.zero(),
          p2pLentDue: Money(5000),
          p2pBorrowedDue: Money.zero(),
        ),
      ],
      transfers: const [
        SuperPixTransfer(
          id: 't1',
          fromMemberId: 'm_kelvynn',
          fromMemberName: 'Kelvynn',
          toMemberId: 'm_cris',
          toMemberName: 'Cris',
          amount: Money(5000),
          description: 'Acerto P2P',
          explanation: 'Compensação direta entre Kelvynn e Cris.',
        ),
      ],
      totalHouseExpenses: const Money(200000),
      totalContributions: const Money(30000),
      totalP2PCleared: const Money(5000),
      houseTreasuryBalance: const Money(-170000),
      auditTrails: {'m_kelvynn': auditKelvynn, 'm_cris': auditCris},
    );

    testWidgets('Exibe cabeçalho, equação de saldo e seções de detalhamento', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SettlementAuditSheet(
              summary: summary,
              initialMemberId: 'm_kelvynn',
            ),
          ),
        ),
      );

      // 1. Título do modal
      expect(find.text('Auditoria do Cálculo'), findsOneWidget);

      // 2. Chips de seleção de morador
      expect(find.text('Kelvynn'), findsWidgets);
      expect(find.text('Cris'), findsWidgets);

      // 3. Fórmula e status do morador Kelvynn
      expect(find.text('Saldo Líquido de Kelvynn:'), findsOneWidget);
      expect(find.text('A PAGAR'), findsOneWidget);
      expect(
        find.text('Despesas do Bolso (Reembolso da Casa)'),
        findsOneWidget,
      );
      expect(
        find.text('Aporte Pendente (Meta menos o já pago)'),
        findsOneWidget,
      );

      // 4. Seções detalhadas
      expect(find.textContaining('Cota de Despesas da Casa'), findsOneWidget);
      expect(find.text('Aluguel do Lar'), findsOneWidget);
      expect(find.text('Conta de Energia'), findsOneWidget);
      expect(find.textContaining('Jogo Nintendo'), findsOneWidget);

      // 5. Botão de copiar memória de cálculo
      expect(find.text('Copiar memória de cálculo de Kelvynn'), findsOneWidget);
    });

    testWidgets(
      'Troca de morador atualiza a memória de cálculo para o outro membro',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SettlementAuditSheet(
                summary: summary,
                initialMemberId: 'm_kelvynn',
              ),
            ),
          ),
        );

        expect(find.text('Saldo Líquido de Kelvynn:'), findsOneWidget);

        // Clica no chip do Cris
        await tester.tap(find.widgetWithText(ChoiceChip, 'Cris'));
        await tester.pumpAndSettle();

        expect(find.text('Saldo Líquido de Cris:'), findsOneWidget);
        expect(find.text('Copiar memória de cálculo de Cris'), findsOneWidget);
      },
    );
  });
}
