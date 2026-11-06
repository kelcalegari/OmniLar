import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/domain/value_objects/cycle_schedule.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/core/utils/uuid.dart';
import 'package:omni_lar/features/finance/data/datasources/mock_finance_datasource.dart';
import 'package:omni_lar/features/finance/domain/entities/card_invoice_breakdown.dart';
import 'package:omni_lar/features/finance/domain/entities/category.dart';
import 'package:omni_lar/features/finance/domain/entities/house_expense.dart';
import 'package:omni_lar/features/finance/domain/entities/house_member.dart';
import 'package:omni_lar/features/finance/domain/entities/payment_method.dart';
import 'package:omni_lar/features/finance/domain/entities/split_rule.dart';
import 'package:omni_lar/features/finance/presentation/widgets/card_invoice_breakdown_view.dart';
import 'package:omni_lar/features/p2p/data/datasources/mock_p2p_datasource.dart';
import 'package:omni_lar/features/reconciliation/data/mock_import_repository.dart';
import 'package:omni_lar/features/reconciliation/domain/entities/imported_statement_line.dart';
import 'package:omni_lar/features/reconciliation/domain/services/import_session.dart';
import 'package:omni_lar/features/reconciliation/domain/services/invoice_breakdown_lines.dart';
import 'package:omni_lar/features/reconciliation/domain/services/statement_parser.dart';

const _members = [
  HouseMember(id: 'kelvynn', name: 'Kelvynn Calegari', defaultSplitPercent: 60),
  HouseMember(id: 'cristiano', name: 'Cristiano', defaultSplitPercent: 40),
];

const _categories = [ExpenseCategory(id: 'cat_casa', name: 'Casa', icon: 'home', colorHex: '#10B981')];

const _card = PaymentMethod(
  id: 'pm_fatura_inteira',
  name: 'Cartão Inter',
  type: PaymentMethodType.card,
  ownerMemberId: 'kelvynn',
  closingDay: 5,
  dueDay: 12,
);

final _due = DateTime(2026, 11, 12);

ImportedStatementLine _line(
  String id,
  String description,
  int cents, {
  LineDestination destination = LineDestination.house,
  StatementLineKind kind = StatementLineKind.purchase,
  String? member,
}) {
  final date = DateTime(2026, 10, 20);
  return ImportedStatementLine(
    id: id,
    date: date,
    description: description,
    amount: Money(cents),
    kind: kind,
    destination: destination,
    assignedMemberId: member,
    categoryId: 'cat_casa',
    signature:
        '${StatementParser.signatureContent(date, kind == StatementLineKind.refund ? -cents : cents, description)}#1',
  );
}

void main() {
  group('CardInvoiceBreakdown', () {
    test('sem importação, a fatura é a parte da Casa', () {
      final breakdown = CardInvoiceBreakdown(lines: const [], houseExpenses: const {'a': Money(1000), 'b': Money(500)});
      expect(breakdown.hasImport, isFalse);
      expect(breakdown.total, const Money(1500));
    });

    test('soma Casa, empréstimo, pessoal, estorno e o que só está no app', () {
      final breakdown = CardInvoiceBreakdown(
        lines: const [
          InvoiceFileLine(amount: Money(288636), kind: InvoicePartKind.house, expenseId: 'e1', signature: 's1'),
          InvoiceFileLine(amount: Money(56531), kind: InvoicePartKind.loan, memberId: 'cristiano', signature: 's2'),
          InvoiceFileLine(amount: Money(3000), kind: InvoicePartKind.personal, memberId: 'kelvynn', signature: 's3'),
          InvoiceFileLine(amount: Money(1000), kind: InvoicePartKind.house, isRefund: true, signature: 's4'),
        ],
        houseExpenses: const {'e1': Money(288636), 'manual': Money(2000)},
      );
      expect(breakdown.fileTotal, const Money(288636 + 56531 + 3000 - 1000));
      expect(breakdown.total, const Money(288636 + 56531 + 3000 - 1000 + 2000));
      expect(breakdown.houseOutsideFile.keys, ['manual']);

      final parts = breakdown.parts;
      expect(parts.map((p) => (p.kind, p.memberId, p.amount.cents, p.outsideFile)), [
        (InvoicePartKind.house, null, 288636, false),
        (InvoicePartKind.loan, 'cristiano', 56531, false),
        (InvoicePartKind.personal, 'kelvynn', 3000, false),
        (null, null, -1000, false),
        (InvoicePartKind.house, null, 2000, true),
      ]);
      expect(breakdown.differenceFrom(Money(breakdown.total.cents)), const Money.zero());
    });

    test('a mesma compra em duas importações conta uma vez', () {
      final breakdown = CardInvoiceBreakdown(
        lines: const [
          InvoiceFileLine(amount: Money(7500), kind: InvoicePartKind.house, signature: 'barbearia#1'),
          InvoiceFileLine(amount: Money(7500), kind: InvoicePartKind.house, signature: 'barbearia#1'),
          InvoiceFileLine(amount: Money(7500), kind: InvoicePartKind.house, signature: 'barbearia#2'),
        ],
        houseExpenses: const {},
      );
      expect(breakdown.fileTotal, const Money(15000));
    });

    test('linha gravada no banco vira a parte certa', () {
      InvoiceFileLine? row(Map<String, dynamic> values) =>
          invoiceFileLineFromRow({'amount_cents': 1000, 'kind': 'purchase', ...values}, payerId: 'kelvynn');

      expect(
        row({'split_destination': 'house', 'decision': 'created', 'expense_id': 'e'})!.kind,
        InvoicePartKind.house,
      );
      expect(row({'split_destination': 'p2p_loan', 'decision': 'created', 'loan_id': 'l'})!.kind, InvoicePartKind.loan);
      final personal = row({'split_destination': 'personal', 'decision': 'ignored'})!;
      expect((personal.kind, personal.memberId), (InvoicePartKind.personal, 'kelvynn'));
      expect(row({'split_destination': 'house', 'decision': 'skipped'})!.kind, InvoicePartKind.skipped);
      expect(row({'split_destination': 'house', 'decision': 'ignored'})!.kind, InvoicePartKind.ignored);
      expect(row({'kind': 'payment', 'decision': 'ignored'}), isNull);
      expect(row({'kind': 'refund', 'decision': 'linked', 'expense_id': 'e'})!.isRefund, isTrue);
    });
  });

  test('a importação confirmada monta a fatura inteira por cartão e vencimento', () async {
    final finance = MockFinanceDataSource();
    final repository = MockImportRepository(finance: finance, p2p: MockP2PDataSource());

    // Compra da Casa lançada à mão no cartão, que não está no arquivo
    await finance.addExpense(
      HouseExpense(
        id: generateUuidV4(),
        title: 'Farmácia',
        amount: const Money(2000),
        date: DateTime(2026, 10, 25),
        dueDate: _due,
        categoryId: 'cat_casa',
        paidByMemberId: 'kelvynn',
        paymentMethodId: _card.id,
        splitRule: const SplitRule.singleResponsible('kelvynn'),
        status: ExpenseStatus.pending,
      ),
    );

    final session = ImportSession.start(
      source: _card,
      fileName: 'fatura.csv',
      lines: [
        _line('casa', 'KOCH HIPERMERCADO', 10000),
        _line('emprestimo', 'OUTBACK', 5000, destination: LineDestination.splitP2P, member: 'cristiano'),
        _line('pessoal', 'BARBEARIA', 3000, destination: LineDestination.cardOwnerPersonal),
        _line('estorno', 'ESTORNO LOJA', 1000, kind: StatementLineKind.refund),
        _line('pagamento', 'PAGAMENTO ON LINE', 345167, kind: StatementLineKind.payment),
      ],
      payerMemberId: 'kelvynn',
    ).withInvoiceDueDate(_due).withExpenses(const []);
    final plan = session.buildPlan(
      members: _members,
      categories: _categories,
      schedule: const CycleSchedule(7),
      now: DateTime(2026, 11, 6),
      newId: generateUuidV4,
    );
    await repository.confirmImport(session, plan);

    final breakdown = await repository.cardInvoiceBreakdown(paymentMethodId: _card.id, dueDate: _due);
    expect(breakdown.total, const Money(10000 + 5000 + 3000 - 1000 + 2000));
    expect(
      {for (final p in breakdown.parts) (p.kind, p.memberId, p.outsideFile): p.amount.cents},
      {
        (InvoicePartKind.house, null, false): 10000,
        (InvoicePartKind.loan, 'cristiano', false): 5000,
        (InvoicePartKind.personal, 'kelvynn', false): 3000,
        (null, null, false): -1000,
        (InvoicePartKind.house, null, true): 2000,
      },
    );

    // Outro vencimento não mistura
    final other = await repository.cardInvoiceBreakdown(paymentMethodId: _card.id, dueDate: DateTime(2026, 12, 12));
    expect(other.hasImport, isFalse);
  });

  testWidgets('mostra a fatura inteira e a diferença com o valor do banco', (tester) async {
    final breakdown = CardInvoiceBreakdown(
      lines: const [
        InvoiceFileLine(amount: Money(288636), kind: InvoicePartKind.house, expenseId: 'e1'),
        InvoiceFileLine(amount: Money(56531), kind: InvoicePartKind.loan, memberId: 'cristiano'),
      ],
      houseExpenses: const {'e1': Money(288636)},
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CardInvoiceBreakdownView(breakdown: breakdown, memberNames: const {'cristiano': 'Cristiano'}),
          ),
        ),
      ),
    );

    expect(find.text('Empréstimo a Cristiano'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('invoice_breakdown_total'))).data, contains('3.451,67'));

    await tester.enterText(find.byKey(const Key('invoice_bank_amount')), '3.451,67');
    await tester.pump();
    expect(find.text('Bate com o app.'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('invoice_bank_amount')), '3.691,72');
    await tester.pump();
    final message = tester.widget<Text>(find.byKey(const Key('invoice_bank_difference'))).data!;
    expect(message, contains('240,05'));
    expect(message, contains('mais'));
  });
}
