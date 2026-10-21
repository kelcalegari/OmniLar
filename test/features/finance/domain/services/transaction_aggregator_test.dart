import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/features/finance/domain/entities/category.dart';
import 'package:omni_lar/features/finance/domain/entities/contribution.dart';
import 'package:omni_lar/features/finance/domain/entities/house_expense.dart';
import 'package:omni_lar/features/finance/domain/entities/house_inflow.dart';
import 'package:omni_lar/features/finance/domain/entities/house_member.dart';
import 'package:omni_lar/features/finance/domain/entities/house_transaction.dart';
import 'package:omni_lar/features/finance/domain/entities/payment_method.dart';
import 'package:omni_lar/features/finance/domain/entities/split_rule.dart';
import 'package:omni_lar/features/finance/domain/entities/third_party_receipt.dart';
import 'package:omni_lar/features/finance/domain/services/transaction_aggregator.dart';
import 'package:omni_lar/features/finance/domain/value_objects/transaction_filter.dart';
import 'package:omni_lar/features/p2p/domain/entities/p2p_installment.dart';
import 'package:omni_lar/features/p2p/domain/entities/p2p_loan.dart';

void main() {
  group('TransactionAggregator', () {
    const member1 = HouseMember(id: 'm1', name: 'Kelvyn');
    const member2 = HouseMember(id: 'm2', name: 'Cris');
    const categoryMercado = ExpenseCategory(id: 'c1', name: 'Supermercado', icon: 'cart', colorHex: '#4CAF50');
    const categoryLuz = ExpenseCategory(id: 'c2', name: 'Energia Elétrica', icon: 'bolt', colorHex: '#FF9800');
    const methodNubank = PaymentMethod(id: 'p1', name: 'Nubank', type: PaymentMethodType.card);

    final expense1 = HouseExpense(
      id: 'e1',
      title: 'Compras da Semana',
      amount: const Money(15000), // R$ 150,00
      date: DateTime(2026, 10, 15),
      categoryId: 'c1',
      paidByMemberId: 'm1',
      paymentMethodId: 'p1',
      splitRule: const SplitRule.percentage({'m1': 50, 'm2': 50}),
      status: ExpenseStatus.paid,
      notes: 'No Pão de Açúcar',
    );

    final expense2Pending = HouseExpense(
      id: 'e2',
      title: 'Conta de Luz',
      amount: const Money(8500), // R$ 85,00
      date: DateTime(2026, 10, 18),
      categoryId: 'c2',
      paidByMemberId: 'm2',
      paymentMethodId: 'p1',
      splitRule: const SplitRule.percentage({'m1': 50, 'm2': 50}),
      status: ExpenseStatus.pending,
    );

    final contribution1 = Contribution(
      id: 'cb1',
      memberId: 'm1',
      amount: const Money(50000), // R$ 500,00
      date: DateTime(2026, 10, 10),
      paymentMethodId: 'p1',
    );

    final inflow1 = HouseInflow(
      id: 'inf1',
      amount: const Money(12000), // R$ 120,00
      receivedOn: DateTime(2026, 10, 12),
      description: 'Reembolso Mercado Livre',
      source: HouseInflowSource.refund,
    );

    final receipt1 = ThirdPartyReceipt(
      id: 'rc1',
      payerName: 'Visitante Lucas',
      amount: const Money(3000), // R$ 30,00
      receivedOn: DateTime(2026, 10, 14),
      vaultId: 'v1',
      description: 'Marmitas almoço',
    );

    test('aggregate converts all entities into unified HouseTransaction list sorted descending by date', () {
      final list = TransactionAggregator.aggregate(
        expenses: [expense1, expense2Pending],
        contributions: [contribution1],
        inflows: [inflow1],
        receipts: [receipt1],
        categories: [categoryMercado, categoryLuz],
        members: [member1, member2],
        paymentMethods: [methodNubank],
      );

      expect(list.length, 5);

      // Verify date ordering (newest first: 18, 15, 14, 12, 10)
      expect(list[0].id, 'exp_e2');
      expect(list[0].isPending, isTrue);
      expect(list[0].categoryName, 'Energia Elétrica');

      expect(list[1].id, 'exp_e1');
      expect(list[1].isExpense, isTrue);
      expect(list[1].memberName, 'Kelvyn');

      expect(list[2].id, 'rec_rc1');
      expect(list[2].origin, TransactionOrigin.thirdPartyReceipt);
      expect(list[2].isInflow, isTrue);

      expect(list[3].id, 'inf_inf1');
      expect(list[3].origin, TransactionOrigin.houseInflow);
      expect(list[3].notes, 'Reembolso');

      expect(list[4].id, 'cont_cb1');
      expect(list[4].origin, TransactionOrigin.contribution);
      expect(list[4].title, 'Aporte de Kelvyn');
    });

    test('filter by TransactionType isolates inflows or expenses', () {
      final all = TransactionAggregator.aggregate(
        expenses: [expense1, expense2Pending],
        contributions: [contribution1],
        inflows: [inflow1],
        receipts: [receipt1],
        categories: [categoryMercado, categoryLuz],
        members: [member1, member2],
        paymentMethods: [methodNubank],
      );

      final expensesOnly = TransactionAggregator.filter(
        all,
        const TransactionFilter(type: TransactionType.expense),
      );
      expect(expensesOnly.length, 2);
      expect(expensesOnly.every((t) => t.isExpense), isTrue);

      final inflowsOnly = TransactionAggregator.filter(
        all,
        const TransactionFilter(type: TransactionType.inflow),
      );
      expect(inflowsOnly.length, 3);
      expect(inflowsOnly.every((t) => t.isInflow), isTrue);
    });

    test('filter by category, member, and pending flag works correctly', () {
      final all = TransactionAggregator.aggregate(
        expenses: [expense1, expense2Pending],
        contributions: [contribution1],
        inflows: [inflow1],
        receipts: [receipt1],
        categories: [categoryMercado, categoryLuz],
        members: [member1, member2],
        paymentMethods: [methodNubank],
      );

      // Filter category Mercado
      final categoryFilter = TransactionAggregator.filter(
        all,
        const TransactionFilter(categoryIds: {'c1'}),
      );
      expect(categoryFilter.length, 1);
      expect(categoryFilter.first.title, 'Compras da Semana');

      // Filter by Member Cris
      final memberFilter = TransactionAggregator.filter(
        all,
        const TransactionFilter(memberId: 'm2'),
      );
      expect(memberFilter.length, 1);
      expect(memberFilter.first.title, 'Conta de Luz');

      // Filter only pending
      final pendingFilter = TransactionAggregator.filter(
        all,
        const TransactionFilter(onlyPending: true),
      );
      expect(pendingFilter.length, 1);
      expect(pendingFilter.first.title, 'Conta de Luz');
    });

    test('filter by search query matches title, category, member or notes', () {
      final all = TransactionAggregator.aggregate(
        expenses: [expense1, expense2Pending],
        contributions: [contribution1],
        inflows: [inflow1],
        receipts: [receipt1],
        categories: [categoryMercado, categoryLuz],
        members: [member1, member2],
        paymentMethods: [methodNubank],
      );

      final searchMarmitas = TransactionAggregator.filter(
        all,
        const TransactionFilter(searchQuery: 'marmitas'),
      );
      expect(searchMarmitas.length, 1);
      expect(searchMarmitas.first.id, 'rec_rc1');

      final searchAcucar = TransactionAggregator.filter(
        all,
        const TransactionFilter(searchQuery: 'açúcar'),
      );
      expect(searchAcucar.length, 1);
      expect(searchAcucar.first.id, 'exp_e1');
    });

    test('computeMetrics calculates total inflows, expenses, and net balance in cents accurately', () {
      final all = TransactionAggregator.aggregate(
        expenses: [expense1, expense2Pending],
        contributions: [contribution1],
        inflows: [inflow1],
        receipts: [receipt1],
        categories: [categoryMercado, categoryLuz],
        members: [member1, member2],
        paymentMethods: [methodNubank],
      );

      final metrics = TransactionAggregator.calculateMetrics(all);

      // Inflows: 500.00 (contribution) + 120.00 (inflow) + 30.00 (receipt) = 650.00 (65000 cents)
      expect(metrics.totalInflows.cents, 65000);

      // Expenses: 150.00 + 85.00 = 235.00 (23500 cents)
      expect(metrics.totalExpenses.cents, 23500);

      // Net balance: 650.00 - 235.00 = +415.00 (41500 cents)
      expect(metrics.netBalance.cents, 41500);
      expect(metrics.count, 5);
    });

    test('aggregate includes paid loan installments as loanRepayment transactions', () {
      final loanWithHouse = P2PLoan(
        id: 'ln_house',
        title: 'Empréstimo Caixa',
        totalAmount: const Money(100000),
        lenderMemberId: P2PLoan.houseLenderId,
        borrowerMemberId: 'm1',
        installmentsCount: 2,
        createdAt: DateTime(2026, 10, 1),
        firstDueDate: DateTime(2026, 10, 16),
        status: LoanStatus.active,
        installments: [
          P2PInstallment(
            id: 'inst_paid_1',
            loanId: 'ln_house',
            number: 1,
            totalCount: 2,
            dueDate: DateTime(2026, 10, 16),
            amount: const Money(50000),
            paidAmount: const Money(50000), // R$ 500,00 pago
            paidAt: DateTime(2026, 10, 16),
          ),
          P2PInstallment(
            id: 'inst_unpaid_2',
            loanId: 'ln_house',
            number: 2,
            totalCount: 2,
            dueDate: DateTime(2026, 11, 16),
            amount: const Money(50000),
            paidAmount: const Money(0), // não pago, não deve virar transação
          ),
        ],
      );

      final p2pBetweenMembers = P2PLoan(
        id: 'ln_p2p',
        title: 'Empréstimo Celular',
        totalAmount: const Money(20000),
        lenderMemberId: 'm2',
        borrowerMemberId: 'm1',
        installmentsCount: 1,
        createdAt: DateTime(2026, 10, 1),
        firstDueDate: DateTime(2026, 10, 17),
        status: LoanStatus.active,
        installments: [
          P2PInstallment(
            id: 'inst_p2p_paid',
            loanId: 'ln_p2p',
            number: 1,
            totalCount: 1,
            dueDate: DateTime(2026, 10, 17),
            amount: const Money(20000),
            paidAmount: const Money(20000),
            paidAt: DateTime(2026, 10, 17),
          ),
        ],
      );

      final all = TransactionAggregator.aggregate(
        expenses: const [],
        contributions: const [],
        inflows: const [],
        receipts: const [],
        loans: [loanWithHouse, p2pBetweenMembers],
        categories: const [],
        members: [member1, member2],
        paymentMethods: const [],
      );

      // Deve ter apenas as 2 parcelas que foram pagas (a não paga é ignorada)
      expect(all.length, 2);

      // Amortização do Caixa da Casa entra como entrada no caixa (Inflow)
      final housePaymentTx = all.firstWhere((t) => t.id == 'loan_pay_inst_paid_1');
      expect(housePaymentTx.origin, TransactionOrigin.loanRepayment);
      expect(housePaymentTx.type, TransactionType.inflow);
      expect(housePaymentTx.amount.cents, 50000);
      expect(housePaymentTx.memberName, 'Kelvyn');
      expect(housePaymentTx.notes, contains('Caixa da Casa'));

      // Amortização entre membros entra como despesa/saída do devedor
      final p2pPaymentTx = all.firstWhere((t) => t.id == 'loan_pay_inst_p2p_paid');
      expect(p2pPaymentTx.origin, TransactionOrigin.loanRepayment);
      expect(p2pPaymentTx.type, TransactionType.expense);
      expect(p2pPaymentTx.amount.cents, 20000);
      expect(p2pPaymentTx.notes, contains('Cris'));
    });
  });
}
