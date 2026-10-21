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
          categoryName: 'Moradia',
          paidByMemberName: 'Cris',
        ),
        ExpenseShareAudit(
          expenseId: 'e3',
          expenseTitle: 'Cerveja Artesanal Particular',
          totalExpenseAmount: const Money(4000),
          allocatedAmount: const Money(4000),
          ruleDescription: 'Item pessoal exclusivo',
          date: DateTime(2026, 10, 14),
          isPersonal: true,
          categoryName: 'Bebidas',
          paidByMemberName: 'Cris',
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
      contributionDue: const Money(104000),
      contributionPaid: const Money(30000),
      outOfPocketTotal: const Money(25000),
      p2pLentTotal: const Money.zero(),
      p2pBorrowedTotal: const Money(5000),
      netBalance: const Money(-54000),
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
    testWidgets(
      'Permite filtrar despesas entre Em Comum e Exclusivas e abrir detalhes ao tocar na transacao',
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

        // Ambas as transações aparecem na lista inicial
        expect(find.text('Aluguel do Lar'), findsOneWidget);
        expect(find.text('Cerveja Artesanal Particular'), findsOneWidget);
        expect(find.text('RATEIO COMUM'), findsOneWidget);
        expect(find.text('100% EXCLUSIVO'), findsOneWidget);

        // Filtra para ver apenas exclusivas
        await tester.tap(find.textContaining('Exclusivas (1)'));
        await tester.pumpAndSettle();

        expect(find.text('Cerveja Artesanal Particular'), findsOneWidget);
        expect(find.text('Aluguel do Lar'), findsNothing);

        // Filtra para ver apenas rateadas em comum
        await tester.tap(find.textContaining('Em Comum (1)'));
        await tester.pumpAndSettle();

        expect(find.text('Aluguel do Lar'), findsOneWidget);
        expect(find.text('Cerveja Artesanal Particular'), findsNothing);

        // Toca na transação de Aluguel para abrir o modal de detalhes
        await tester.tap(find.text('Aluguel do Lar'));
        await tester.pumpAndSettle();

        expect(find.text('Gasto Rateado em Comum'), findsOneWidget);
        expect(find.text('Moradia'), findsWidgets);
        expect(find.text('Entendido'), findsOneWidget);

        // Fecha o modal
        await tester.tap(find.text('Entendido'));
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'Exibe total desembolsado no ciclo e secao de emprestimos quitados no ciclo',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final auditWithCyclePayments = MemberAuditTrail(
          memberId: 'm_lucas',
          memberName: 'Lucas',
          expenseShares: const [],
          contributionsMade: [
            ContributionAudit(
              contributionId: 'cb_10',
              amount: const Money(100000), // R$ 1.000,00 aporte
              date: DateTime(2026, 10, 10),
            ),
          ],
          outOfPocketExpenses: const [],
          p2pReceivables: const [],
          p2pPayables: const [],
          contributionDue: const Money(100000),
          contributionPaid: const Money(100000),
          outOfPocketTotal: const Money.zero(),
          p2pLentTotal: const Money.zero(),
          p2pBorrowedTotal: const Money.zero(),
          netBalance: const Money.zero(),
          p2pPaidInCycle: [
            P2PInstallmentAudit(
              loanId: 'l_casa',
              description: 'Acordo com Caixa da Casa',
              otherMemberId: 'entity_caixa',
              otherMemberName: 'Caixa da Casa',
              installmentNumber: 1,
              totalInstallments: 1,
              amount: const Money(100000), // R$ 1.000,00 emprestimo pago
              dueDate: DateTime(2026, 10, 15),
              isReceivable: false,
            ),
          ],
          p2pPaidInCycleTotal: const Money(100000),
        );

        final summaryWithPayments = SettlementSummary(
          cycle: cycle,
          memberBalances: [
            const MemberNetBalance(
              memberId: 'm_lucas',
              memberName: 'Lucas',
              contributionDue: Money(100000),
              contributionPaid: Money(100000),
              outOfPocketExpenses: Money.zero(),
              p2pLentDue: Money.zero(),
              p2pBorrowedDue: Money.zero(),
            ),
          ],
          transfers: const [],
          totalHouseExpenses: const Money.zero(),
          totalContributions: const Money(100000),
          totalP2PCleared: const Money.zero(),
          houseTreasuryBalance: const Money.zero(),
          auditTrails: {'m_lucas': auditWithCyclePayments},
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SettlementAuditSheet(
                summary: summaryWithPayments,
                initialMemberId: 'm_lucas',
              ),
            ),
          ),
        );

        // Deve exibir o total desembolsado no ciclo de R$ 2.000,00
        expect(find.textContaining('Total Desembolsado no Ciclo:'), findsOneWidget);
        expect(find.textContaining('2.000,00'), findsWidgets);
        expect(find.textContaining('Aporte +'), findsOneWidget);

        // Deve exibir a seção de quitados no ciclo
        expect(find.textContaining('QUITADOS / PAGOS NESTE CICLO'), findsOneWidget);
        expect(find.textContaining('Acordo com Caixa da Casa'), findsOneWidget);
        expect(find.text('QUITADO'), findsOneWidget);
      },
    );
  });
}
