import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/features/finance/data/datasources/mock_finance_datasource.dart';
import 'package:omni_lar/features/finance/data/repositories/finance_repository_impl.dart';
import 'package:omni_lar/features/finance/domain/entities/card_invoice.dart';
import 'package:omni_lar/features/finance/domain/entities/house_expense.dart';
import 'package:omni_lar/features/finance/domain/entities/split_rule.dart';
import 'package:omni_lar/features/finance/domain/entities/third_party_receipt.dart';
import 'package:omni_lar/features/finance/presentation/cubit/finance_cubit.dart';
import 'package:omni_lar/features/finance/presentation/cubit/finance_state.dart';
import 'package:omni_lar/features/finance/presentation/widgets/third_party_receipts_card.dart';

/// Caso do dono: marmitas de R$ 192 no cartão de um morador, R$ 32 dele e
/// R$ 160 de quem não mora na casa, pagos por Pix na conta da Casa.
void main() {
  late MockFinanceDataSource ds;
  late FinanceCubit cubit;

  Future<int> vaultBalance(String vaultId) async =>
      (await ds.getSavingsVaults()).firstWhere((v) => v.id == vaultId).currentBalance.cents;

  setUp(() async {
    ds = MockFinanceDataSource();
    cubit = FinanceCubit(FinanceRepositoryImpl(ds));
    await cubit.loadCycleData();
  });

  tearDown(() => cubit.close());

  group('Entrada de terceiros na caixinha', () {
    test('Registrar guarda na caixinha sem virar aporte nem mexer no Caixa do ciclo', () async {
      final before = await vaultBalance('vault_reserva');
      final contributionsBefore = cubit.state.contributions.length;
      final openingBefore = cubit.state.summary?.openingBalance;

      final ok = await cubit.registerThirdPartyReceipt(
        payerName: 'Pessoal do trabalho',
        amount: const Money(16000),
        receivedOn: DateTime(2026, 10, 17),
        vaultId: 'vault_reserva',
        paymentMethodId: 'pm_card_carlos',
        description: 'marmitas de sábado',
      );

      expect(ok, isTrue);
      expect(await vaultBalance('vault_reserva'), before + 16000);
      expect(cubit.state.contributions.length, contributionsBefore);
      expect(cubit.state.summary?.openingBalance, openingBefore);
      final held = cubit.state.heldThirdPartyReceipts.single;
      expect(held.payerName, 'Pessoal do trabalho');
      expect(held.paymentMethodId, 'pm_card_carlos');
      expect(held.description, 'marmitas de sábado');
      final tx = (await ds.getVaultTransactions('vault_reserva')).last;
      expect(tx.isDeposit, isTrue);
      expect(tx.cycleStartDate, isNull, reason: 'dinheiro de fora, não do Caixa do ciclo');
    });

    test('Sem quem pagou ou com valor zero, nada é gravado', () async {
      final before = await vaultBalance('vault_reserva');

      expect(
        await cubit.registerThirdPartyReceipt(
          payerName: '  ',
          amount: const Money(16000),
          receivedOn: DateTime(2026, 10, 17),
          vaultId: 'vault_reserva',
        ),
        isFalse,
      );
      expect(
        await cubit.registerThirdPartyReceipt(
          payerName: 'Fulano',
          amount: const Money.zero(),
          receivedOn: DateTime(2026, 10, 17),
          vaultId: 'vault_reserva',
        ),
        isFalse,
      );
      expect(await vaultBalance('vault_reserva'), before);
      expect(cubit.state.thirdPartyReceipts, isEmpty);
    });

    test('Usar tira da caixinha; desfazer devolve; usar duas vezes é recusado', () async {
      await cubit.registerThirdPartyReceipt(
        payerName: 'Pessoal',
        amount: const Money(16000),
        receivedOn: DateTime(2026, 10, 17),
        vaultId: 'vault_reserva',
      );
      final receipt = cubit.state.heldThirdPartyReceipts.single;
      final held = await vaultBalance('vault_reserva');

      expect(
        await cubit.useThirdPartyReceipts(
          receiptIds: [receipt.id],
          use: ThirdPartyReceiptUse.passedToOwner,
          paymentMethodId: 'pm_card_carlos',
        ),
        isTrue,
      );
      expect(await vaultBalance('vault_reserva'), held - 16000);
      final used = cubit.state.thirdPartyReceipts.single;
      expect(used.use, ThirdPartyReceiptUse.passedToOwner);
      expect(used.usedPaymentMethodId, 'pm_card_carlos');
      expect((await ds.getVaultTransactions('vault_reserva')).last.cycleStartDate, isNull,
          reason: 'o repasse não volta ao Caixa do ciclo');

      expect(
        await cubit.useThirdPartyReceipts(receiptIds: [receipt.id], use: ThirdPartyReceiptUse.housePaid),
        isFalse,
      );
      expect(await vaultBalance('vault_reserva'), held - 16000);

      expect(await cubit.reopenThirdPartyReceipt(receipt.id), isTrue);
      expect(await vaultBalance('vault_reserva'), held);
      expect(cubit.state.heldThirdPartyReceipts.single.id, receipt.id);
    });

    test('Excluir uma entrada guardada tira o valor da caixinha; usada, só depois de desfazer', () async {
      final before = await vaultBalance('vault_viagem');
      await cubit.registerThirdPartyReceipt(
        payerName: 'Ana',
        amount: const Money(3200),
        receivedOn: DateTime(2026, 10, 17),
        vaultId: 'vault_viagem',
      );
      final receipt = cubit.state.heldThirdPartyReceipts.single;

      await cubit.useThirdPartyReceipts(receiptIds: [receipt.id], use: ThirdPartyReceiptUse.housePaid);
      expect(await cubit.deleteThirdPartyReceipt(receipt.id), isFalse);

      await cubit.reopenThirdPartyReceipt(receipt.id);
      expect(await cubit.deleteThirdPartyReceipt(receipt.id), isTrue);
      expect(await vaultBalance('vault_viagem'), before);
      expect(cubit.state.thirdPartyReceipts, isEmpty);
    });
  });

  group('Pagamento da fatura com repasses', () {
    final dueDate = DateTime(2026, 11, 5);

    Future<void> marmitas() async {
      // Na fatura do app só a parte da casa: os R$ 160 foram pagos por terceiros
      await ds.addExpense(HouseExpense(
        id: 'marmita_casa',
        title: 'Marmitas',
        amount: const Money(3200),
        date: DateTime(2026, 10, 17),
        dueDate: dueDate,
        categoryId: 'cat_mercado',
        paidByMemberId: 'member_carlos',
        paymentMethodId: 'pm_card_carlos',
        splitRule: const SplitRule.percentage(null),
        status: ExpenseStatus.pending,
      ));
      await cubit.registerThirdPartyReceipt(
        payerName: 'Pessoal',
        amount: const Money(16000),
        receivedOn: DateTime(2026, 10, 17),
        vaultId: 'vault_reserva',
        paymentMethodId: 'pm_card_carlos',
      );
    }

    test('Paga pelo titular: o repasse sai da caixinha para ele', () async {
      await marmitas();
      final receipt = cubit.state.heldThirdPartyReceipts.single;
      final held = await vaultBalance('vault_reserva');

      final ok = await cubit.payCardInvoice(
        paymentMethodId: 'pm_card_carlos',
        invoiceDueDate: dueDate,
        paidAt: DateTime(2026, 11, 4),
        thirdPartyReceiptIds: [receipt.id],
      );

      expect(ok, isTrue);
      expect(await vaultBalance('vault_reserva'), held - 16000);
      final used = cubit.state.thirdPartyReceipts.single;
      expect(used.use, ThirdPartyReceiptUse.passedToOwner);
      expect(used.usedDueDate, dueDate);
    });

    test('Paga pela conta da Casa: o repasse é usado pela Casa', () async {
      await marmitas();
      final receipt = cubit.state.heldThirdPartyReceipts.single;

      await cubit.payCardInvoice(
        paymentMethodId: 'pm_card_carlos',
        invoiceDueDate: dueDate,
        paidAt: DateTime(2026, 11, 4),
        paidByHouse: true,
        thirdPartyReceiptIds: [receipt.id],
      );

      expect(cubit.state.thirdPartyReceipts.single.use, ThirdPartyReceiptUse.housePaid);
    });

    test('Desfazer o pagamento da fatura devolve o repasse à caixinha', () async {
      await marmitas();
      final receipt = cubit.state.heldThirdPartyReceipts.single;
      final held = await vaultBalance('vault_reserva');
      await cubit.payCardInvoice(
        paymentMethodId: 'pm_card_carlos',
        invoiceDueDate: dueDate,
        paidAt: DateTime(2026, 11, 4),
        thirdPartyReceiptIds: [receipt.id],
      );

      expect(
        await cubit.undoCardInvoicePayment(paymentMethodId: 'pm_card_carlos', invoiceDueDate: dueDate),
        isTrue,
      );
      expect(await vaultBalance('vault_reserva'), held);
      expect(cubit.state.heldThirdPartyReceipts.single.id, receipt.id);
    });
  });

  group('Fatura importada sem compra da casa', () {
    CardInvoice invoice(DateTime due, {bool importOnly = false, DateTime? paidAt}) => CardInvoice(
          paymentMethodId: 'pm_card_carlos',
          dueDate: due,
          total: Money(importOnly ? 19200 : 3200),
          purchasesCount: importOnly ? 0 : 1,
          paidAt: paidAt,
          importOnly: importOnly,
        );

    test('Aparece para pagar quando o vencimento não tem compra da casa', () {
      final open = CardInvoice.withImported(
        [invoice(DateTime(2026, 12, 5))],
        [invoice(DateTime(2026, 11, 5), importOnly: true), invoice(DateTime(2026, 12, 5), importOnly: true)],
        paid: false,
      );

      // O vencimento com compra da casa continua sendo o das compras
      expect(open.map((i) => (i.dueDate, i.importOnly)), [
        (DateTime(2026, 11, 5), true),
        (DateTime(2026, 12, 5), false),
      ]);
    });

    test('Paga, entra na lista de pagamentos registrados da mais recente para a mais antiga', () {
      final paid = CardInvoice.withImported(
        [invoice(DateTime(2026, 10, 5), paidAt: DateTime(2026, 10, 4))],
        [invoice(DateTime(2026, 11, 5), importOnly: true, paidAt: DateTime(2026, 11, 4))],
        paid: true,
      );

      expect(paid.map((i) => i.dueDate), [DateTime(2026, 11, 5), DateTime(2026, 10, 5)]);
    });
  });

  group('ThirdPartyReceiptsCard', () {
    Future<void> pump(WidgetTester tester) => tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: BlocProvider.value(
                value: cubit,
                child: BlocBuilder<FinanceCubit, FinanceState>(
                  builder: (context, state) => SingleChildScrollView(
                    child: ThirdPartyReceiptsCard(state: state, cubit: cubit),
                  ),
                ),
              ),
            ),
          ),
        );

    testWidgets('Mostra o guardado e registra uma entrada pelo formulário', (tester) async {
      await tester.runAsync(() => cubit.registerThirdPartyReceipt(
            payerName: 'Pessoal',
            amount: const Money(16000),
            receivedOn: DateTime(2026, 10, 17),
            vaultId: 'vault_reserva',
            paymentMethodId: 'pm_card_carlos',
          ));
      await pump(tester);

      expect(find.text('Repasses de terceiros'), findsOneWidget);
      expect(find.textContaining('Pessoal'), findsOneWidget);
      expect(find.textContaining('para Nubank Carlos (Carlos)'), findsOneWidget);

      await tester.tap(find.byKey(const Key('add_third_party_receipt')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('receipt_payer')), 'Ana');
      await tester.tap(find.byKey(const Key('receipt_save')));
      await tester.pumpAndSettle();
      // Sem valor, o formulário não fecha
      expect(find.text('Informe o valor.'), findsOneWidget);
    });
  });
}
