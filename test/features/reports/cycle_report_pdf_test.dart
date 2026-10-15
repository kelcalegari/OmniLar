import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/domain/value_objects/financial_cycle.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/features/finance/domain/entities/category.dart';
import 'package:omni_lar/features/finance/domain/entities/contribution.dart';
import 'package:omni_lar/features/finance/domain/entities/house_expense.dart';
import 'package:omni_lar/features/finance/domain/entities/house_member.dart';
import 'package:omni_lar/features/finance/domain/entities/split_rule.dart';
import 'package:omni_lar/features/reports/domain/entities/cycle_insights.dart';
import 'package:omni_lar/features/reports/domain/entities/cycle_preview.dart';
import 'package:omni_lar/features/reports/domain/services/cycle_report_pdf.dart';

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
    ExpenseCategory(
      id: 'cat_casa',
      name: 'Moradia — Aluguel',
      icon: 'home',
      colorHex: '#000000',
    ),
    ExpenseCategory(
      id: 'cat_mercado',
      name: 'Alimentação',
      icon: 'cart',
      colorHex: '#000000',
    ),
  ];

  HouseExpense expense(
    String title,
    int cents,
    String category, {
    bool pending = false,
  }) => HouseExpense(
    id: title,
    title: title,
    amount: Money(cents),
    date: DateTime(2026, 10, 12),
    categoryId: category,
    paidByMemberId: 'm_ana',
    paymentMethodId: 'pm_conta',
    splitRule: const SplitRule.percentage({'m_ana': 50, 'm_bia': 50}),
    status: pending ? ExpenseStatus.pending : ExpenseStatus.paid,
  );

  test(
    'gera um PDF com a prestação de contas, mesmo com caracteres fora do latim',
    () async {
      final bytes = await const CycleReportPdf().build(
        houseName: 'Nossa Casa “da praia” 🏠',
        cycle: cycle,
        expenses: [
          for (var i = 0; i < 60; i++)
            expense('Compra $i — mercado', 1000 + i, 'cat_mercado'),
          expense('Aluguel', 150000, 'cat_casa', pending: true),
        ],
        categories: categories,
        members: members,
        contributions: [
          Contribution(
            id: 'c1',
            memberId: 'm_ana',
            amount: const Money(100000),
            date: DateTime(2026, 10, 11),
            paymentMethodId: 'pm_conta',
          ),
        ],
        preview: CyclePreview(
          cycle: cycle,
          isSettled: false,
          members: const [
            MemberCyclePreview(
              memberId: 'm_bia',
              memberName: 'Bia',
              contributionDue: Money(110000),
              contributionPaid: Money.zero(),
              outOfPocket: Money.zero(),
              contributionRefund: Money.zero(),
              p2pToPay: Money(5000),
              p2pToReceive: Money.zero(),
              net: Money(-115000),
            ),
          ],
        ),
        insights: const CycleInsights(
          hasPrevious: true,
          previousTotal: Money(90000),
          previousByCategory: {'cat_mercado': 90000},
          byPayer: [
            PayerShare(
              memberId: null,
              name: 'Caixa da Casa',
              amount: Money(213770),
            ),
          ],
          loanPositions: [
            LoanPosition(
              memberId: 'm_bia',
              name: 'Bia',
              toReceive: Money.zero(),
              toPay: Money(5000),
              alreadyPaid: Money.zero(),
              overdueInstallments: 1,
            ),
          ],
        ),
        generatedAt: DateTime(2026, 10, 20),
      );

      expect(latin1.decode(bytes.sublist(0, 5)), '%PDF-');
      expect(bytes.length, greaterThan(2000));

      // Para conferir o arquivo à mão: OMNILAR_PDF_OUT=caminho/arquivo.pdf
      final out = Platform.environment['OMNILAR_PDF_OUT'];
      if (out != null) File(out).writeAsBytesSync(bytes);
    },
  );

  test('nome do arquivo pelo início do ciclo', () {
    expect(
      CycleReportPdf.fileNameFor(cycle),
      'omnilar_prestacao_de_contas_2026-10-10.pdf',
    );
  });
}
