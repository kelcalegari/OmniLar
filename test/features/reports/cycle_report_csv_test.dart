import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/domain/value_objects/financial_cycle.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/features/finance/domain/entities/category.dart';
import 'package:omni_lar/features/finance/domain/entities/house_expense.dart';
import 'package:omni_lar/features/finance/domain/entities/house_member.dart';
import 'package:omni_lar/features/finance/domain/entities/split_rule.dart';
import 'package:omni_lar/features/reports/domain/entities/cycle_preview.dart';
import 'package:omni_lar/features/reports/domain/entities/payment_due_entry.dart';
import 'package:omni_lar/features/reports/domain/services/cycle_report_csv.dart';

void main() {
  final cycle = FinancialCycle(
    start: DateTime(2026, 10, 10),
    end: DateTime(2026, 11, 9),
  );
  const members = [
    HouseMember(
      id: 'm_ana',
      name: 'Ana',
      role: 'owner',
      defaultSplitPercent: 50,
    ),
    HouseMember(
      id: 'm_bia',
      name: 'Bia',
      role: 'member',
      defaultSplitPercent: 50,
    ),
  ];
  const categories = [
    ExpenseCategory(id: 'cat', name: 'Casa', icon: 'home', colorHex: '#000000'),
  ];

  HouseExpense expense(
    String title,
    int cents, {
    ExpenseStatus status = ExpenseStatus.paid,
    bool outOfPocket = false,
  }) => HouseExpense(
    id: title,
    title: title,
    amount: Money(cents),
    date: DateTime(2026, 10, 12),
    categoryId: 'cat',
    paidByMemberId: 'm_ana',
    paymentMethodId: 'pm',
    splitRule: const SplitRule.percentage({'m_ana': 50, 'm_bia': 50}),
    status: status,
    paidOutOfPocket: outOfPocket,
  );

  test('nome do arquivo pelo início do ciclo', () {
    expect(CycleReportCsv.fileNameFor(cycle), 'omnilar_ciclo_2026-10-10.csv');
  });

  test('despesas, totais, prévia e calendário no mesmo arquivo', () {
    final csv = const CycleReportCsv().build(
      cycle: cycle,
      expenses: [
        expense('Mercado "grande"', 12345, outOfPocket: true),
        expense('Luz', 20000, status: ExpenseStatus.pending),
      ],
      categories: categories,
      members: members,
      preview: CyclePreview(
        cycle: cycle,
        isSettled: false,
        members: const [
          MemberCyclePreview(
            memberId: 'm_bia',
            memberName: 'Bia',
            contributionDue: Money(16172),
            contributionPaid: Money.zero(),
            outOfPocket: Money.zero(),
            contributionRefund: Money.zero(),
            p2pToPay: Money.zero(),
            p2pToReceive: Money.zero(),
            net: Money(-16172),
          ),
        ],
      ),
      calendar: PaymentCalendar(
        cycle: cycle,
        today: DateTime(2026, 10, 20),
        entries: [
          PaymentDueEntry(
            kind: PaymentDueKind.bill,
            date: DateTime(2026, 10, 15),
            title: 'Luz',
            amount: const Money(20000),
            payerId: null,
            payerName: 'Caixa da Casa',
            isOverdue: true,
            barcode: '8366000',
          ),
        ],
      ),
    );

    expect(csv.startsWith('﻿'), isTrue);
    expect(csv, contains('Período;10/10/2026 até 09/11/2026'));
    // Aspas internas dobradas e valor com vírgula decimal
    expect(
      csv,
      contains(
        '12/10/2026;"Mercado ""grande""";"Casa";123,45;"Ana";Paga;Avulsa',
      ),
    );
    expect(
      csv,
      contains('12/10/2026;"Luz";"Casa";200,00;"Em aberto";Pendente;Avulsa'),
    );
    expect(csv, contains('Total do ciclo (R\$);323,45'));
    expect(csv, contains('PRÉVIA DO FECHAMENTO'));
    expect(csv, contains('"Bia";161,72;0,00;0,00;0,00;0,00;0,00;-161,72'));
    expect(
      csv,
      contains(
        '15/10/2026;"Luz";"Caixa da Casa";"";200,00;"Atrasado";"8366000"',
      ),
    );
  });

  test('sem prévia nem calendário, só as despesas e o resumo', () {
    final csv = const CycleReportCsv().build(
      cycle: cycle,
      expenses: [expense('Aluguel', 150000)],
      categories: categories,
      members: members,
    );
    expect(csv, contains('"Caixa da Casa"'));
    expect(csv, isNot(contains('PRÉVIA')));
    expect(csv, isNot(contains('PRÓXIMOS PAGAMENTOS')));
  });
}
