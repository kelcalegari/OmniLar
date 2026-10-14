import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/domain/value_objects/financial_cycle.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/features/finance/data/datasources/mock_finance_datasource.dart';
import 'package:omni_lar/features/finance/domain/entities/house_expense.dart';
import 'package:omni_lar/features/finance/domain/entities/payment_method.dart';
import 'package:omni_lar/features/finance/domain/entities/split_rule.dart';
import 'package:omni_lar/features/finance/domain/services/cycle_expense_filter.dart';
import 'package:omni_lar/features/finance/domain/services/cycle_expense_grouping.dart';
import 'package:omni_lar/features/finance/domain/services/expense_launch_defaults.dart';
import 'package:omni_lar/features/p2p/data/datasources/mock_p2p_datasource.dart';
import 'package:omni_lar/features/settlement/data/datasources/mock_settlement_datasource.dart';
import 'package:omni_lar/features/settlement/domain/entities/settlement_options.dart';
import 'package:omni_lar/features/settlement/domain/services/open_invoice_choices.dart';

void main() {
  const card = PaymentMethod(
    id: 'pm_card_carlos',
    name: 'Nubank Carlos',
    type: PaymentMethodType.card,
    ownerMemberId: 'member_carlos',
    closingDay: 28,
    dueDay: 5,
  );
  const houseCard = PaymentMethod(
    id: 'pm_card_casa',
    name: 'Cartão da Casa',
    type: PaymentMethodType.card,
    closingDay: 9,
    dueDay: 15,
  );

  group('Compra no cartão espera a fatura', () {
    test('cartão com fechamento e vencimento nasce pendente e sem pagador', () {
      expect(ExpenseLaunchDefaults.waitsForInvoice(card), isTrue);
      expect(ExpenseLaunchDefaults.launchStatus(card), ExpenseStatus.pending);
      expect(ExpenseLaunchDefaults.launchPaidOutOfPocket(card), isFalse);
    });

    test('despesa de projeto, cartão sem vencimento e outras formas nascem pagas', () {
      expect(ExpenseLaunchDefaults.launchStatus(card, projectId: 'viagem'), ExpenseStatus.paid);
      expect(
        ExpenseLaunchDefaults.launchStatus(
          const PaymentMethod(id: 'c', name: 'Cartão', type: PaymentMethodType.card),
        ),
        ExpenseStatus.paid,
      );
      const vr = PaymentMethod(
        id: 'vr',
        name: 'VR',
        type: PaymentMethodType.vr,
        ownerMemberId: 'member_marina',
      );
      expect(ExpenseLaunchDefaults.launchStatus(vr), ExpenseStatus.paid);
      expect(ExpenseLaunchDefaults.launchPaidOutOfPocket(vr), isTrue);
    });
  });

  group('Pagamento da fatura com a origem do dinheiro', () {
    late MockFinanceDataSource finance;
    final due = DateTime(2026, 11, 5);

    HouseExpense purchase(String id, int cents) => HouseExpense(
          id: id,
          title: id,
          amount: Money(cents),
          date: DateTime(2026, 10, 20),
          dueDate: due,
          categoryId: 'cat_mercado',
          paidByMemberId: 'member_carlos',
          paymentMethodId: card.id,
          splitRule: const SplitRule.percentage({'member_carlos': 60, 'member_marina': 40}),
          status: ExpenseStatus.pending,
        );

    /// As duas compras, onde quer que contem: no ciclo do vencimento ou, depois
    /// de pagas, no ciclo do pagamento.
    Future<List<HouseExpense>> invoice() async {
      final found = <String, HouseExpense>{};
      for (final date in [due, DateTime(2026, 11, 4)]) {
        final cycle = FinancialCycle.fromDate(date: date, cycleStartDay: 5);
        for (final e in await finance.getExpensesForCycle(cycle)) {
          if (e.id == 'a' || e.id == 'b') found[e.id] = e;
        }
      }
      expect(found, hasLength(2));
      return found.values.toList();
    }

    setUp(() async {
      finance = MockFinanceDataSource();
      await finance.addExpense(purchase('a', 10000));
      await finance.addExpense(purchase('b', 20000));
    });

    test('pela titular: as compras viram pagas na data e ela é reembolsada', () async {
      final paidAt = DateTime(2026, 11, 4, 12);
      await finance.payCardInvoice(paymentMethodId: card.id, invoiceDueDate: due, paidAt: paidAt);

      final expenses = await invoice();
      expect(expenses, hasLength(2));
      expect(expenses.every((e) => e.isPaid && e.paidAt == paidAt && e.paidOutOfPocket), isTrue);
    });

    test('pelo Caixa: pagas, sem reembolso; desfazer volta para a fatura em aberto', () async {
      await finance.payCardInvoice(
        paymentMethodId: card.id,
        invoiceDueDate: due,
        paidAt: DateTime(2026, 11, 4),
        paidByHouse: true,
      );
      var expenses = await invoice();
      expect(expenses.every((e) => e.isPaid && !e.paidOutOfPocket), isTrue);

      await finance.undoCardInvoicePayment(paymentMethodId: card.id, invoiceDueDate: due);
      expenses = await invoice();
      expect(expenses.every((e) => e.isPending && e.paidAt == null && !e.paidOutOfPocket), isTrue);
    });
  });

  group('Fechamento com fatura em aberto', () {
    late MockFinanceDataSource finance;
    late MockSettlementDataSource settlement;
    late FinancialCycle cycle;
    late DateTime due;

    setUp(() async {
      finance = MockFinanceDataSource();
      settlement = MockSettlementDataSource(
        financeDataSource: finance,
        p2pDataSource: MockP2PDataSource(),
      );
      cycle = FinancialCycle.fromDate(date: DateTime.now(), cycleStartDay: 5);
      due = cycle.startDate.add(const Duration(days: 3));
      // Fatura do cartão da Carlos que vence neste ciclo, ainda sem pagamento
      for (final (id, cents) in [('fatura_1', 30000), ('fatura_2', 20000)]) {
        await finance.addExpense(
          HouseExpense(
            id: id,
            title: id,
            amount: Money(cents),
            date: cycle.startDate.subtract(const Duration(days: 10)),
            dueDate: due,
            categoryId: 'cat_mercado',
            paidByMemberId: 'member_carlos',
            paymentMethodId: card.id,
            splitRule: const SplitRule.percentage({'member_carlos': 60, 'member_marina': 40}),
            status: ExpenseStatus.pending,
          ),
        );
      }
    });

    String key() => cardInvoiceKey(card.id, due);

    test('a fatura em aberto aparece para o fechamento decidir', () async {
      final invoices = openInvoicesOf(
        await finance.getExpensesForCycle(cycle),
        await finance.getPaymentMethods(),
      );
      final invoice = invoices.singleWhere((i) => i.key == key());
      expect(invoice.total.cents, 50000);
      expect(defaultOpenInvoiceChoice(invoice.card), OpenInvoiceChoice.paidByHolder);
      expect(defaultOpenInvoiceChoice(houseCard), OpenInvoiceChoice.paidByHouse);
    });

    test('sem mexer, entra como paga pela titular: ela é reembolsada', () async {
      final summary = await settlement.getSettlementSummary(cycle);
      final carlos = summary.auditTrails['member_carlos']!;
      expect(carlos.outOfPocketExpenses.map((e) => e.expenseId), containsAll(['fatura_1', 'fatura_2']));
    });

    test('paga pelo Caixa: entra no ciclo, mas sem reembolso', () async {
      final summary = await settlement.getSettlementSummary(
        cycle,
        options: SettlementOptions(openInvoiceChoices: {key(): OpenInvoiceChoice.paidByHouse}),
      );
      final carlos = summary.auditTrails['member_carlos']!;
      expect(carlos.outOfPocketExpenses.map((e) => e.expenseId), isNot(contains('fatura_1')));
    });

    test('levada para o próximo ciclo: fica fora do acerto e continua em aberto', () async {
      final withInvoice = await settlement.getSettlementSummary(cycle);
      final options = SettlementOptions(openInvoiceChoices: {key(): OpenInvoiceChoice.carryOver});
      final carried = await settlement.getSettlementSummary(cycle, options: options);
      expect(withInvoice.totalHouseExpenses.cents - carried.totalHouseExpenses.cents, 50000);

      await settlement.confirmSettlement(carried, options: options);

      // O fechamento não deu baixa nem acertou a fatura
      final stillOpen = (await finance.getExpensesForCycle(cycle))
          .where((e) => e.id == 'fatura_1' || e.id == 'fatura_2')
          .toList();
      expect(stillOpen, hasLength(2));
      expect(stillOpen.every((e) => e.isPending && e.settledAt == null), isTrue);

      // Quando o próximo ciclo começar, ela pesa nele como conta vencida
      final next = FinancialCycle.fromDate(date: cycle.endDate.add(const Duration(days: 1)), cycleStartDay: 5);
      expect(
        stillOpen.every((e) => expenseBelongsToCycle(
              e,
              next,
              isCardPayment: true,
              now: next.startDate.add(const Duration(days: 1)),
            )),
        isTrue,
      );
    });
  });
}
