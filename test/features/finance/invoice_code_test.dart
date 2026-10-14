import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/di/service_locator.dart';
import 'package:omni_lar/features/capture/domain/services/boleto_code.dart';
import 'package:omni_lar/features/finance/presentation/cubit/finance_cubit.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/features/finance/domain/entities/house_expense.dart';
import 'package:omni_lar/features/finance/domain/entities/payment_method.dart';
import 'package:omni_lar/features/finance/domain/entities/split_rule.dart';
import 'package:omni_lar/features/finance/domain/services/cycle_expense_grouping.dart';
import 'package:omni_lar/features/finance/presentation/widgets/bill_code_field.dart';
import 'package:omni_lar/features/finance/presentation/widgets/card_invoice_group_tile.dart';

/// Código de barras de boleto bancário válido.
String _bankBarcode({int cents = 50000}) {
  final rest = '1500${cents.toString().padLeft(10, '0')}${'2' * 25}';
  return '0019${BoletoCodeReader.bankGeneralDigit('0019$rest')}$rest';
}

void main() {
  setUpAll(() async {
    if (!sl.isRegistered<FinanceCubit>()) {
      await initServiceLocator();
    }
  });

  test('o código guardado na fatura fica no estado e pode ser apagado', () async {
    final cubit = sl<FinanceCubit>();
    await cubit.loadCycleData();
    final due = DateTime(2026, 11, 5);
    final line = BoletoCodeReader.read(_bankBarcode()).digitableLine;

    expect(await cubit.saveCardInvoiceCode(paymentMethodId: 'pm_card_carlos', invoiceDueDate: due, barcode: line), isTrue);
    expect(cubit.state.invoiceCodeFor('pm_card_carlos', due), line);
    expect(cubit.state.invoiceCodeFor('pm_card_marina', due), isNull);

    // Recarregar mantém o código
    await cubit.loadCycleData();
    expect(cubit.state.invoiceCodeFor('pm_card_carlos', due), line);

    expect(await cubit.saveCardInvoiceCode(paymentMethodId: 'pm_card_carlos', invoiceDueDate: due), isTrue);
    expect(cubit.state.invoiceCodeFor('pm_card_carlos', due), isNull);
  });

  testWidgets('campo do código: informa, recusa código errado, troca e apaga', (tester) async {
    final saved = <String?>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: BillCodeField(
          code: null,
          onSave: (line) async {
            saved.add(line);
            return true;
          },
        ),
      ),
    ));

    await tester.tap(find.byKey(const Key('bill_code_add')));
    await tester.pumpAndSettle();

    // Dígito verificador errado: não grava
    final good = _bankBarcode();
    final wrong = good.replaceRange(30, 31, good[30] == '1' ? '3' : '1');
    await tester.enterText(find.byKey(const Key('bill_code_input')), wrong);
    await tester.tap(find.byKey(const Key('bill_code_save')));
    await tester.pumpAndSettle();
    expect(saved, isEmpty);
    expect(find.textContaining('não confere'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('bill_code_input')), good);
    await tester.tap(find.byKey(const Key('bill_code_save')));
    await tester.pumpAndSettle();
    final line = BoletoCodeReader.read(good).digitableLine;
    expect(saved, [line]);
    expect(find.byKey(const Key('bill_code_copy')), findsOneWidget);
    expect(find.text(line), findsOneWidget);

    // Vazio apaga
    await tester.tap(find.byKey(const Key('bill_code_edit')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('bill_code_input')), '');
    await tester.tap(find.byKey(const Key('bill_code_save')));
    await tester.pumpAndSettle();
    expect(saved, [line, null]);
    expect(find.byKey(const Key('bill_code_add')), findsOneWidget);
  });

  testWidgets('fatura aberta tem atalho para importar e copiar o código', (tester) async {
    const card = PaymentMethod(
      id: 'pm_card_carlos',
      name: 'Nubank',
      type: PaymentMethodType.card,
      ownerMemberId: 'member_carlos',
      closingDay: 28,
      dueDay: 5,
    );
    final due = DateTime.now().add(const Duration(days: 10));
    final entry = CardInvoiceEntry(card: card, dueDate: due, purchases: [
      HouseExpense(
        id: 'compra',
        title: 'Mercado',
        amount: const Money(5000),
        date: DateTime.now(),
        dueDate: due,
        categoryId: 'cat',
        paymentMethodId: card.id,
        paidByMemberId: 'member_carlos',
        splitRule: const SplitRule.percentage(null),
        status: ExpenseStatus.pending,
      ),
    ]);
    var imported = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CardInvoiceGroupTile(
          invoice: entry,
          expanded: true,
          onToggle: () {},
          onImport: () => imported++,
          onRegisterPayment: () {},
          barcode: BoletoCodeReader.read(_bankBarcode()).digitableLine,
          children: const [],
        ),
      ),
    ));

    expect(find.byKey(Key('copy_invoice_code_${entry.key}')), findsOneWidget);
    await tester.tap(find.byKey(Key('import_invoice_${entry.key}')));
    expect(imported, 1);
    expect(find.text('Importar fatura do Nubank'), findsOneWidget);
  });
}
