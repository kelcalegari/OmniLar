import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/domain/value_objects/financial_cycle.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/features/finance/data/datasources/mock_finance_datasource.dart';
import 'package:omni_lar/features/finance/domain/entities/house_expense.dart';
import 'package:omni_lar/features/finance/domain/entities/payment_method.dart';
import 'package:omni_lar/features/finance/domain/entities/split_rule.dart';
import 'package:omni_lar/features/finance/domain/services/pending_payment.dart';
import 'package:omni_lar/features/p2p/data/datasources/mock_p2p_datasource.dart';
import 'package:omni_lar/features/settlement/data/datasources/mock_settlement_datasource.dart';
import 'package:omni_lar/features/settlement/domain/entities/settlement_options.dart';
import 'package:omni_lar/features/settlement/domain/services/open_invoice_choices.dart';

const _house = PaymentMethod(id: 'pm_caixa', name: 'Caixa da Casa', type: PaymentMethodType.account);
const _pixHouse = PaymentMethod(id: 'pm_pix', name: 'Pix', type: PaymentMethodType.pix);
const _pixKelvynn = PaymentMethod(
  id: 'pm_pix_k',
  name: 'Pix Kelvynn',
  type: PaymentMethodType.pix,
  ownerMemberId: 'kelvynn',
);
// Meio de uma moradora da casa do modo demo
const _pixMarina = PaymentMethod(
  id: 'pm_pix_m',
  name: 'Pix Marina',
  type: PaymentMethodType.pix,
  ownerMemberId: 'member_marina',
);
const _card = PaymentMethod(
  id: 'pm_card',
  name: 'Nubank',
  type: PaymentMethodType.card,
  ownerMemberId: 'kelvynn',
  closingDay: 28,
  dueDay: 5,
);

HouseExpense _bill({
  String id = 'internet',
  int cents = 9990,
  DateTime? due,
  String method = 'pm_caixa',
  bool recurring = false,
  bool variable = false,
  String? barcode,
}) {
  final dueDate = due ?? DateTime(2026, 10, 25);
  return HouseExpense(
    id: id,
    title: 'Internet',
    amount: Money(cents),
    date: dueDate,
    dueDate: dueDate,
    categoryId: 'cat',
    paidByMemberId: 'cristiano',
    paymentMethodId: method,
    splitRule: const SplitRule.percentage(null),
    status: ExpenseStatus.pending,
    isRecurring: recurring,
    isVariable: variable,
    barcode: barcode,
  );
}

void main() {
  final paidOn = DateTime(2026, 10, 20, 12);

  group('Pagar uma conta pendente', () {
    test('com meio da casa: paga pela casa, sem reembolso', () {
      final paid = paidWith(_bill(), paidOn: paidOn, method: _pixHouse);

      expect(paid.isPaid, isTrue);
      expect(paid.paidAt, paidOn);
      expect(paid.paymentMethodId, 'pm_pix');
      expect(paid.paidOutOfPocket, isFalse);
    });

    test('com meio de um morador: ele pagou e é reembolsado', () {
      final paid = paidWith(_bill(), paidOn: paidOn, method: _pixKelvynn, amount: const Money(10500));

      expect(paid.paidByMemberId, 'kelvynn');
      expect(paid.paidOutOfPocket, isTrue);
      expect(paid.amount.cents, 10500);
    });

    test('com cartão: vira compra da fatura e fica pendente até a fatura ser paga', () {
      final paid = paidWith(_bill(), paidOn: paidOn, method: _card);

      expect(paid.isPending, isTrue);
      expect(paid.paymentMethodId, 'pm_card');
      // Compra de 20/10 num cartão que fecha dia 28 e vence dia 5: fatura de 05/11
      expect(paid.dueDate, DateTime(2026, 11, 5));
      expect(paid.paidOutOfPocket, isFalse);
    });

    test('conta recorrente paga com cartão recebe baixa direto', () {
      final paid = paidWith(_bill(recurring: true), paidOn: paidOn, method: _card);
      expect(paid.isPaid, isTrue);
      expect(paid.paidOutOfPocket, isTrue);
    });
  });

  group('Conta já prevista para o boleto lido', () {
    test('mesmo código, ou vencimento próximo com o mesmo valor ou conta variável/recorrente', () {
      final expenses = [
        _bill(id: 'mesmo_codigo', due: DateTime(2026, 12, 1), cents: 1, barcode: '8366 0000'),
        _bill(id: 'mesmo_valor', cents: 15090, due: DateTime(2026, 10, 27)),
        _bill(id: 'variavel', cents: 20000, due: DateTime(2026, 10, 23), variable: true),
        _bill(id: 'longe', cents: 15090, due: DateTime(2026, 11, 20)),
        _bill(id: 'outro_valor', cents: 5000, due: DateTime(2026, 10, 25)),
      ];
      final found = knownBillsFor(
        expenses,
        dueDate: DateTime(2026, 10, 25),
        amount: const Money(15090),
        barcode: '83660000',
      );

      expect(found.map((e) => e.id), ['mesmo_codigo', 'mesmo_valor', 'variavel']);
    });

    test('conta paga e compra de cartão em aberto não entram', () {
      final paid = _bill(id: 'paga', cents: 15090).copyWith(status: ExpenseStatus.paid);
      final cardPurchase = _bill(id: 'cartao', cents: 15090, method: 'pm_card');
      final found = knownBillsFor(
        [paid, cardPurchase],
        dueDate: DateTime(2026, 10, 25),
        amount: const Money(15090),
        paymentMethods: const [_card],
      );
      expect(found, isEmpty);
    });
  });

  group('Fechamento com conta pendente', () {
    late MockFinanceDataSource finance;
    late MockSettlementDataSource settlement;
    late FinancialCycle cycle;

    setUp(() async {
      finance = MockFinanceDataSource();
      settlement = MockSettlementDataSource(financeDataSource: finance, p2pDataSource: MockP2PDataSource());
      cycle = FinancialCycle.fromDate(date: DateTime.now(), cycleStartDay: 5);
      await finance.addPaymentMethod(_pixMarina);
      await finance.addExpense(
        _bill(id: 'boleto_teste', cents: 40000, due: cycle.startDate.add(const Duration(days: 3)))
            .copyWith(paidByMemberId: 'member_carlos'),
      );
    });

    test('sem mexer, a baixa usa o meio que a conta já tinha (aqui, o da casa)', () async {
      final methods = await finance.getPaymentMethods();
      final bills = openBillsOf(await finance.getExpensesForCycle(cycle), methods);
      final bill = bills.firstWhere((e) => e.id == 'boleto_teste');
      expect(defaultBillMethodId(bill, methods), 'pm_caixa');
      // Cartão não é opção para dar baixa em conta
      expect(billPaymentMethods(methods).any((m) => m.isCreditCard && m.closingDay != null), isFalse);
    });

    test('com o meio de um morador, ele é reembolsado; levada adiante, sai do acerto', () async {
      final byMember = await settlement.getSettlementSummary(
        cycle,
        options: const SettlementOptions(openBillChoices: {'boleto_teste': 'pm_pix_m'}),
      );
      final marina = byMember.auditTrails['member_marina']!.outOfPocketExpenses
          .where((e) => e.expenseId == 'boleto_teste');
      expect(marina, isNotEmpty);
      // Sem mexer (meio da casa), ninguém é reembolsado por ela
      final standardTrails = (await settlement.getSettlementSummary(cycle)).auditTrails.values;
      expect(standardTrails.expand((t) => t.outOfPocketExpenses).any((e) => e.expenseId == 'boleto_teste'), isFalse);

      final standard = await settlement.getSettlementSummary(cycle);
      final carried = await settlement.getSettlementSummary(
        cycle,
        options: const SettlementOptions(openBillChoices: {'boleto_teste': carryOverBill}),
      );
      expect(standard.totalHouseExpenses.cents - carried.totalHouseExpenses.cents, 40000);
    });
  });
}
