import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/domain/value_objects/cycle_schedule.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/features/finance/domain/entities/house_expense.dart';
import 'package:omni_lar/features/finance/domain/entities/house_member.dart';
import 'package:omni_lar/features/finance/domain/entities/payment_method.dart';
import 'package:omni_lar/features/finance/domain/entities/split_rule.dart';
import 'package:omni_lar/features/reconciliation/domain/entities/imported_statement_line.dart';
import 'package:omni_lar/features/reconciliation/domain/services/import_session.dart';

const _card = PaymentMethod(
  id: 'pm_nubank',
  name: 'Nubank',
  type: PaymentMethodType.card,
  ownerMemberId: 'kelvynn',
  closingDay: 28,
  dueDay: 10,
);

const _members = [
  HouseMember(id: 'kelvynn', name: 'Kelvynn', defaultSplitPercent: 60),
  HouseMember(id: 'cristiano', name: 'Cristiano', defaultSplitPercent: 40),
];

ImportedStatementLine _line(String id, int day, String description, int cents,
        {StatementLineKind kind = StatementLineKind.purchase}) =>
    ImportedStatementLine(
      id: id,
      date: DateTime(2026, 10, day),
      description: description,
      amount: Money(cents),
      kind: kind,
      destination: kind == StatementLineKind.purchase ? LineDestination.house : LineDestination.ignored,
    );

HouseExpense _expense(String id, String title, int cents, DateTime date, {DateTime? settledAt}) => HouseExpense(
      id: id,
      title: title,
      amount: Money(cents),
      date: date,
      dueDate: DateTime(2026, 10, 10),
      categoryId: 'cat',
      paidByMemberId: 'kelvynn',
      paymentMethodId: _card.id,
      splitRule: const SplitRule.percentage({'kelvynn': 60, 'cristiano': 40}),
      status: ExpenseStatus.pending,
      settledAt: settledAt,
    );

void main() {
  final lines = [
    _line('loja', 3, 'LOJA X CAMISETAS', 25000),
    _line('mercado', 4, 'MERCADO', 12000),
    _line('estorno_loja', 8, 'ESTORNO LOJA X CAMISETAS', 5000, kind: StatementLineKind.refund),
    _line('estorno_antigo', 9, 'ESTORNO MAGAZINE', 30000, kind: StatementLineKind.refund),
  ];
  // Compra de outra fatura, já lançada no app
  final magazine = _expense('e_magazine', 'Magazine', 30000, DateTime(2026, 9, 20));

  ImportSession start({List<HouseExpense> expenses = const []}) => ImportSession.start(
        source: _card,
        fileName: 'fatura.csv',
        lines: lines,
        payerMemberId: 'kelvynn',
      ).withExpenses(expenses);

  test('o estorno oferece as compras desta fatura e as já lançadas que ele pode abater', () {
    final session = start(expenses: [magazine]);

    final forLoja = session.refundOptionsOf(lines[2]);
    // A loja (mesma descrição) vem primeiro; o mercado também cabe os R$ 50,00
    expect(forLoja.first.lineId, 'loja');
    expect(forLoja.first.suggested, isTrue);
    expect(forLoja.map((o) => o.lineId), containsAll(['loja', 'mercado']));
    // A despesa de R$ 300,00 também poderia receber o estorno de R$ 50,00
    expect(forLoja.any((o) => o.expense?.id == 'e_magazine'), isTrue);

    final forMagazine = session.refundOptionsOf(lines[3]);
    // Nenhuma compra desta fatura cabe R$ 300,00; a despesa já lançada, sim, e por inteiro
    expect(forMagazine.single.expense!.id, 'e_magazine');
    expect(forMagazine.single.label, startsWith('Excluir "Magazine"'));
    expect(forMagazine.single.coversWholeExpense(lines[3].amount), isTrue);
  });

  test('abater de uma compra desta fatura lança só o que sobrou', () {
    final session = start().withRefundChoice('estorno_loja', 'line:loja');

    expect(session.effectiveAmountOf(lines[0]).cents, 20000);
    expect(session.totals.house.cents, 20000 + 12000);

    final plan = session.buildPlan(members: _members, categories: const [], schedule: const CycleSchedule(5));
    expect(plan.newExpenses.map((e) => e.amount.cents), [20000, 12000]);
    expect(plan.lineRecords.firstWhere((r) => r.line.id == 'estorno_loja').outcome, LineOutcome.linked);
    // Um segundo estorno não pode abater mais do que sobrou
    expect(session.refundOptionsOf(lines[3]).any((o) => o.lineId == 'loja'), isFalse);
  });

  test('estorno do valor inteiro de uma compra desta fatura: ela não é lançada', () {
    final refundAll = [
      _line('loja', 3, 'LOJA X', 25000),
      _line('estorno', 8, 'ESTORNO LOJA X', 25000, kind: StatementLineKind.refund),
    ];
    final session = ImportSession.start(
      source: _card,
      fileName: 'fatura.csv',
      lines: refundAll,
      payerMemberId: 'kelvynn',
    ).withRefundChoice('estorno', 'line:loja');

    final plan = session.buildPlan(members: _members, categories: const [], schedule: const CycleSchedule(5));
    expect(plan.newExpenses, isEmpty);
    expect(plan.lineRecords.firstWhere((r) => r.line.id == 'loja').outcome, LineOutcome.ignored);
  });

  test('abater de uma despesa já lançada: o valor dela diminui; se cobrir tudo, ela é excluída', () {
    final partial = start(expenses: [magazine]).withRefundChoice('estorno_loja', 'expense:e_magazine');
    var plan = partial.buildPlan(members: _members, categories: const [], schedule: const CycleSchedule(5));
    expect(plan.expenseUpdates.single.amount.cents, 25000);
    expect(plan.expenseDeletions, isEmpty);
    // As duas compras desta fatura continuam inteiras
    expect(plan.newExpenses.map((e) => e.amount.cents), [25000, 12000]);

    final whole = start(expenses: [magazine]).withRefundChoice('estorno_antigo', 'expense:e_magazine');
    plan = whole.buildPlan(members: _members, categories: const [], schedule: const CycleSchedule(5));
    expect(plan.expenseUpdates, isEmpty);
    expect(plan.expenseDeletions.single.id, 'e_magazine');
    expect(plan.lineRecords.firstWhere((r) => r.line.id == 'estorno_antigo').expenseId, 'e_magazine');
  });

  test('despesa já acertada em fechamento não recebe estorno', () {
    final settled = _expense('e_settled', 'Magazine', 30000, DateTime(2026, 9, 20), settledAt: DateTime(2026, 10, 5));
    expect(start(expenses: [settled]).refundOptionsOf(lines[3]), isEmpty);
  });

  test('dividir a compra desfaz o estorno que apontava para ela', () {
    final session = start().withRefundChoice('estorno_loja', 'line:loja').splitLine('loja', const Money(10000));
    expect(session.chosenRefund(lines[2]), isNull);
    expect(session.totals.house.cents, 25000 + 12000);
  });
}
