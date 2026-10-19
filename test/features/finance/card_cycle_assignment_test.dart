import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/domain/value_objects/financial_cycle.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/features/finance/domain/entities/house_expense.dart';
import 'package:omni_lar/features/finance/domain/entities/payment_method.dart';
import 'package:omni_lar/features/finance/domain/entities/split_rule.dart';
import 'package:omni_lar/features/finance/domain/services/cycle_expense_filter.dart';

void main() {
  // Ciclos de 09/10 a 08/11 e de 09/11 a 08/12
  final october = FinancialCycle.fromDate(date: DateTime(2026, 10, 12), cycleStartDay: 9);
  final november = FinancialCycle.fromDate(date: DateTime(2026, 11, 12), cycleStartDay: 9);

  // Compra de 20/10 numa fatura que vence em 15/11 e segue aberta
  HouseExpense purchase({ExpenseStatus status = ExpenseStatus.pending, DateTime? paidAt}) => HouseExpense(
        id: 'c1',
        title: 'Compra',
        amount: const Money(10000),
        date: DateTime(2026, 10, 20),
        dueDate: DateTime(2026, 11, 15),
        categoryId: 'c',
        paidByMemberId: 'ana',
        paymentMethodId: 'card',
        splitRule: const SplitRule.percentage(null),
        status: status,
        paidAt: paidAt,
      );

  group('Ciclo da compra no cartão', () {
    test('padrão (vencimento da fatura) é o comportamento de sempre', () {
      final e = purchase();
      final now = DateTime(2026, 10, 25);
      expect(
        expenseBelongsToCycle(e, october, isCardPayment: true, now: now),
        expenseBelongsToCycle(e, october,
            isCardPayment: true, now: now, cardCycleAssignment: CardCycleAssignment.invoiceDue),
      );
      expect(expenseBelongsToCycle(e, october, isCardPayment: true, now: now), isFalse);
      expect(expenseBelongsToCycle(e, november, isCardPayment: true, now: DateTime(2026, 11, 10)), isTrue);
    });

    test('purchase_date: conta no ciclo da compra, com a fatura aberta', () {
      final e = purchase();
      final now = DateTime(2026, 11, 20);
      const byDate = CardCycleAssignment.purchaseDate;
      expect(expenseBelongsToCycle(e, october, isCardPayment: true, now: now, cardCycleAssignment: byDate), isTrue);
      expect(expenseBelongsToCycle(e, november, isCardPayment: true, now: now, cardCycleAssignment: byDate), isFalse);
    });

    test('purchase_date: pagar a fatura não muda o ciclo da compra', () {
      final e = purchase(status: ExpenseStatus.paid, paidAt: DateTime(2026, 11, 14));
      const byDate = CardCycleAssignment.purchaseDate;
      final now = DateTime(2026, 11, 20);
      expect(expenseBelongsToCycle(e, october, isCardPayment: true, now: now, cardCycleAssignment: byDate), isTrue);
      expect(expenseBelongsToCycle(e, november, isCardPayment: true, now: now, cardCycleAssignment: byDate), isFalse);
    });

    test('a escolha só vale para cartão e para despesa de fora de projeto', () {
      final e = purchase();
      const byDate = CardCycleAssignment.purchaseDate;
      final now = DateTime(2026, 11, 20);
      // Outra forma de pagamento segue a regra comum (vence em novembro)
      expect(expenseBelongsToCycle(e, october, isCardPayment: false, now: now, cardCycleAssignment: byDate), isFalse);
      expect(expenseBelongsToCycle(e, november, isCardPayment: false, now: now, cardCycleAssignment: byDate), isTrue);
      final project = HouseExpense(
        id: 'p',
        title: 'Obra',
        amount: const Money(100),
        date: DateTime(2026, 10, 20),
        dueDate: DateTime(2026, 11, 15),
        categoryId: 'c',
        paidByMemberId: 'ana',
        paymentMethodId: 'card',
        splitRule: const SplitRule.percentage(null),
        projectId: 'proj',
      );
      expect(expenseBelongsToCycle(project, october, isCardPayment: true, cardCycleAssignment: byDate), isFalse);
    });

    test('fromDb: ausente ou desconhecido vale o vencimento da fatura', () {
      expect(CardCycleAssignment.fromDb(null), CardCycleAssignment.invoiceDue);
      expect(CardCycleAssignment.fromDb('xyz'), CardCycleAssignment.invoiceDue);
      expect(CardCycleAssignment.fromDb('purchase_date'), CardCycleAssignment.purchaseDate);
      const pm = PaymentMethod(id: 'a', name: 'Nubank', type: PaymentMethodType.card);
      expect(pm.cycleAssignment, CardCycleAssignment.invoiceDue);
      expect(pm.copyWith(cycleAssignment: CardCycleAssignment.purchaseDate).cycleAssignment,
          CardCycleAssignment.purchaseDate);
    });
  });

  group('Migration 0104 (cartão)', () {
    final sql = File('supabase/migrations/20261018240000_0104_card_cycle_approval_tasks.sql').readAsStringSync();

    test('coluna com padrão invoice_due e espelho na trava de ciclo fechado', () {
      expect(sql, contains("add column if not exists cycle_assignment text not null default 'invoice_due'"));
      expect(sql, contains("check (cycle_assignment in ('invoice_due', 'purchase_date'))"));
      expect(sql, contains('function public.expense_counts_in_closed_cycle'));
      expect(sql, contains("v_assignment = 'purchase_date'"));
      expect(sql, isNot(contains('drop trigger')));
    });
  });
}
