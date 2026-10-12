import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/domain/value_objects/financial_cycle.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/features/finance/data/datasources/mock_finance_datasource.dart';
import 'package:omni_lar/features/p2p/data/datasources/mock_p2p_datasource.dart';
import 'package:omni_lar/features/settlement/data/datasources/mock_settlement_datasource.dart';
import 'package:omni_lar/features/settlement/domain/entities/member_net_balance.dart';
import 'package:omni_lar/features/settlement/domain/entities/settlement_options.dart';
import 'package:omni_lar/features/settlement/domain/entities/settlement_summary.dart';
import 'package:omni_lar/features/settlement/domain/entities/super_pix_transfer.dart';
import 'package:omni_lar/features/settlement/domain/entities/transfer_settlement_resolution.dart';
import 'package:omni_lar/features/settlement/presentation/widgets/partial_payment_dialog.dart';

void main() {
  group('Pagamento Parcial no Fechamento do Ciclo (Super Pix)', () {
    late MockFinanceDataSource mockFinance;
    late MockP2PDataSource mockP2P;
    late MockSettlementDataSource mockSettlement;

    final testCycle = FinancialCycle(
      start: DateTime(2026, 10, 5),
      end: DateTime(2026, 11, 4),
    );

    const testTransfer = SuperPixTransfer(
      id: 'sp_carlos_to_marina',
      fromMemberId: 'member_carlos',
      fromMemberName: 'Carlos',
      toMemberId: 'member_marina',
      toMemberName: 'Marina',
      amount: Money(80000), // R$ 800,00
      description: 'Acerto do ciclo',
    );

    final testSummary = SettlementSummary(
      cycle: testCycle,
      totalHouseExpenses: const Money(300000),
      totalContributions: const Money(200000),
      totalP2PCleared: const Money(80000),
      houseTreasuryBalance: const Money.zero(),
      status: SettlementStatus.readyToSettle,
      memberBalances: const [
        MemberNetBalance(
          memberId: 'member_carlos',
          memberName: 'Carlos',
          contributionDue: Money(150000),
          contributionPaid: Money(70000),
          outOfPocketExpenses: Money.zero(),
          p2pLentDue: Money.zero(),
          p2pBorrowedDue: Money(80000),
        ),
      ],
      transfers: const [testTransfer],
    );

    setUp(() {
      mockFinance = MockFinanceDataSource();
      mockP2P = MockP2PDataSource();
      mockSettlement = MockSettlementDataSource(
        financeDataSource: mockFinance,
        p2pDataSource: mockP2P,
      );
    });

    test(
      'Liquidação parcial cria novo Empréstimo P2P para cobrir a diferença restante',
      () async {
        // Carlos só consegue pagar R$ 500,00 dos R$ 800,00
        // Marina cobre os R$ 300,00 restantes parcelando em 3x via P2P
        const resolution = TransferSettlementResolution(
          transferId: 'sp_carlos_to_marina',
          amountExpected: Money(80000), // R$ 800,00
          amountPaid: Money(50000), // R$ 500,00
          shortfallAction: ShortfallAction.createP2PLoan,
          loanInstallmentsCount: 3,
        );

        final options = const SettlementOptions().copyWith(
          transferResolutions: {'sp_carlos_to_marina': resolution},
        );

        final initialLoans = await mockP2P.getLoans();
        final initialCount = initialLoans.length;

        await mockSettlement.confirmSettlement(testSummary, options: options);

        // 1. Verifica que novo empréstimo P2P foi gerado com a diferença de R$ 300,00
        final updatedLoans = await mockP2P.getLoans();
        expect(updatedLoans.length, equals(initialCount + 1));

        final createdLoan = updatedLoans.first;
        expect(
          createdLoan.totalAmount,
          equals(const Money(30000)),
        ); // R$ 300,00
        expect(createdLoan.borrowerMemberId, equals('member_carlos'));
        expect(createdLoan.lenderMemberId, equals('member_marina'));
        expect(createdLoan.installmentsCount, equals(3));
        expect(createdLoan.installments.length, equals(3));

        // 2. Verifica que a transferência gravada registrou o valor efetivamente pago
        final refreshedSummary = await mockSettlement.getSettlementSummary(
          testCycle,
        );
        expect(refreshedSummary.status, equals(SettlementStatus.settled));
        expect(
          refreshedSummary.transfers.first.amount,
          equals(const Money(50000)),
        );
        expect(
          refreshedSummary.transfers.first.explanation,
          contains('Parcial:'),
        );
      },
    );

    testWidgets(
      'PartialPaymentDialog permite configurar valor parcial e ação de shortfall',
      (tester) async {
        TransferSettlementResolution? savedResolution;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: PartialPaymentDialog(
                transfer: testTransfer,
                vaults: const [],
                onSave: (res) {
                  savedResolution = res;
                },
              ),
            ),
          ),
        );

        expect(find.text('Pagamento Parcial do Super Pix'), findsOneWidget);
        expect(find.text('Carlos ➔ Marina'), findsOneWidget);

        // Altera o valor no TextField para 500,00
        final textField = find.byType(TextField);
        await tester.enterText(textField, '500,00');
        await tester.pumpAndSettle();

        expect(find.textContaining('300,00'), findsWidgets);

        // Rola para baixo no diálogo para revelar o botão de confirmar
        await tester.drag(find.byType(ListView), const Offset(0, -600));
        await tester.pumpAndSettle();

        // Clica em confirmar
        final submitButton = find.text('Confirmar Pagamento Parcial');
        expect(submitButton, findsOneWidget);
        await tester.tap(submitButton);
        await tester.pumpAndSettle();

        expect(savedResolution, isNotNull);
        expect(savedResolution!.amountPaid, equals(const Money(50000)));
        expect(savedResolution!.shortfall, equals(const Money(30000)));
        expect(
          savedResolution!.shortfallAction,
          equals(ShortfallAction.createP2PLoan),
        );
      },
    );

    test('Cobertura com Caixinha da Casa: modo Fundo Perdido (grant) não gera empréstimo', () async {
      final resolution = TransferSettlementResolution(
        transferId: testTransfer.id,
        amountExpected: testTransfer.amount,
        amountPaid: const Money(50000), // R$ 500 pago
        shortfallAction: ShortfallAction.deductFromVault,
        vaultId: 'vault_reserva',
        vaultRepaymentMode: VaultRepaymentMode.grant,
      );

      final options = SettlementOptions(
        transferResolutions: {testTransfer.id: resolution},
      );

      final initialLoans = await mockP2P.getLoans();
      final initialLoansCount = initialLoans.length;

      await mockSettlement.confirmSettlement(testSummary, options: options);

      final postLoans = await mockP2P.getLoans();
      // Não deve ter criado nenhum novo empréstimo
      expect(postLoans.length, equals(initialLoansCount));
    });

    test('Cobertura com Caixinha da Casa: modo Reposição Livre (openEnded) cria empréstimo para a Casa sem vencimento no ciclo', () async {
      final resolution = TransferSettlementResolution(
        transferId: testTransfer.id,
        amountExpected: testTransfer.amount,
        amountPaid: const Money(50000), // R$ 500 pago
        shortfallAction: ShortfallAction.deductFromVault,
        vaultId: 'vault_reserva',
        vaultRepaymentMode: VaultRepaymentMode.openEnded,
      );

      final options = SettlementOptions(
        transferResolutions: {testTransfer.id: resolution},
      );

      await mockSettlement.confirmSettlement(testSummary, options: options);

      final loans = await mockP2P.getLoans();
      final vaultLoan = loans.firstWhere((l) => l.lenderMemberId == 'entity_caixa');

      expect(vaultLoan, isNotNull);
      expect(vaultLoan.totalAmount, equals(const Money(30000))); // R$ 300,00 de shortfall
      expect(vaultLoan.title, contains('Reposição da Caixinha'));
      expect(vaultLoan.firstDueDate.year, equals(2099)); // Sem vencimento compulsório no ciclo
    });
  });
}
