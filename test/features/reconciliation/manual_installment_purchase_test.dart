import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/domain/value_objects/cycle_schedule.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/core/utils/uuid.dart';
import 'package:omni_lar/features/finance/data/datasources/mock_finance_datasource.dart';
import 'package:omni_lar/features/finance/domain/entities/category.dart';
import 'package:omni_lar/features/finance/domain/entities/house_expense.dart';
import 'package:omni_lar/features/finance/domain/entities/house_member.dart';
import 'package:omni_lar/features/finance/domain/entities/payment_method.dart';
import 'package:omni_lar/features/finance/domain/entities/split_rule.dart';
import 'package:omni_lar/features/p2p/data/datasources/mock_p2p_datasource.dart';
import 'package:omni_lar/features/p2p/domain/entities/p2p_loan.dart';
import 'package:omni_lar/features/reconciliation/data/mock_import_repository.dart';
import 'package:omni_lar/features/reconciliation/domain/entities/imported_statement_line.dart';
import 'package:omni_lar/features/reconciliation/domain/entities/installment_plan.dart';
import 'package:omni_lar/features/reconciliation/domain/services/import_session.dart';
import 'package:omni_lar/features/reconciliation/domain/services/installment_matcher.dart';
import 'package:omni_lar/features/reconciliation/domain/services/installment_purchase.dart';
import 'package:omni_lar/features/reconciliation/domain/services/statement_parser.dart';
import 'package:omni_lar/features/reconciliation/domain/services/statement_text.dart';
import 'package:omni_lar/features/reports/domain/services/upcoming_cycles_builder.dart';

const _members = [
  HouseMember(id: 'kelvynn', name: 'Kelvynn Calegari', defaultSplitPercent: 60),
  HouseMember(id: 'cristiano', name: 'Cristiano', defaultSplitPercent: 40),
];

const _categories = [
  ExpenseCategory(id: 'cat_casa', name: 'Casa', icon: 'home', colorHex: '#10B981'),
];

PaymentMethod _card({String? owner}) => PaymentMethod(
      id: 'pm_magalu',
      name: 'Cartão Magalu',
      type: PaymentMethodType.card,
      ownerMemberId: owner,
      closingDay: 9,
      dueDay: 14,
    );

ImportedStatementLine _line(String id, DateTime date, String description, int cents) {
  final installment = StatementText.installmentOf(description);
  return ImportedStatementLine(
    id: id,
    date: date,
    description: description,
    amount: Money(cents),
    signature: '${StatementParser.signatureContent(date, cents, description)}#1',
    categoryId: 'cat_casa',
    installmentNumber: installment?.number,
    installmentsTotal: installment?.total,
  );
}

// Compra antes do fechamento (dia 9): a 1ª parcela vem na fatura de 14/10
final _purchase = DateTime(2026, 10, 5);
final _october = DateTime(2026, 10, 14);
final _november = DateTime(2026, 11, 14);

InstallmentPurchase _build({
  String title = 'Geladeira',
  int cents = 100000,
  int count = 10,
  DateTime? date,
  PaymentMethod? card,
  String? debtor,
  int firstNumber = 1,
}) =>
    InstallmentPurchase.build(
      title: title,
      total: Money(cents),
      count: count,
      purchaseDate: date ?? _purchase,
      card: card ?? _card(),
      categoryId: 'cat_casa',
      paidByMemberId: 'kelvynn',
      splitRule: const SplitRule.percentage({'kelvynn': 60, 'cristiano': 40}),
      firstNumber: firstNumber,
      debtorMemberId: debtor,
      debtorName: debtor == null ? null : 'Cristiano',
      now: DateTime(2026, 10, 5),
    );

void main() {
  const schedule = CycleSchedule(1);
  late MockImportRepository repository;

  setUp(() {
    repository = MockImportRepository(finance: MockFinanceDataSource(), p2p: MockP2PDataSource());
  });

  Future<ImportSession> review(
    PaymentMethod card,
    DateTime dueDate,
    List<ImportedStatementLine> lines,
  ) async {
    final session = ImportSession.start(
      source: card,
      fileName: 'fatura.csv',
      lines: lines,
      payerMemberId: 'kelvynn',
    ).withInvoiceDueDate(dueDate);
    return session
        .withImportedSignatures(await repository.importedSignatures(card.id))
        .withInstallmentPlans(
          await repository.installmentPlans(card.id),
          memberIds: {for (final m in _members) m.id},
          categoryIds: {for (final c in _categories) c.id},
        )
        .withExpenses(const []);
  }

  ImportPlan plan(ImportSession session) => session.buildPlan(
        members: _members,
        categories: _categories,
        schedule: schedule,
        now: DateTime(2026, 10, 20),
        newId: generateUuidV4,
      );

  ImportedStatementLine lineOf(ImportSession session, String id) =>
      session.lines.firstWhere((l) => l.id == id);

  group('montar a compra parcelada', () {
    test('da Casa: uma parcela prevista por fatura, o centavo que sobra nas primeiras', () {
      final purchase = _build(cents: 100003);
      expect(purchase.loans, isEmpty);
      expect(purchase.expenses.map((e) => e.title), [
        for (var n = 1; n <= 10; n++) 'Geladeira ($n/10)',
      ]);
      expect(purchase.expenses.map((e) => e.amount.cents).take(4), [10001, 10001, 10001, 10000]);
      expect(purchase.expenses.fold<int>(0, (acc, e) => acc + e.amount.cents), 100003);
      expect(purchase.expenses.first.dueDate, _october);
      expect(purchase.expenses[1].dueDate, _november);
      expect(purchase.expenses.last.dueDate, DateTime(2027, 7, 14));
      expect(
        purchase.expenses.every((e) => e.status == ExpenseStatus.pending && !e.paidOutOfPocket),
        isTrue,
      );

      final installment = purchase.plan;
      expect(installment.origin, InstallmentPlanOrigin.manual);
      expect(installment.destination, LineDestination.house);
      expect(installment.anchorNumber, 1);
      expect(installment.anchorDueDate, _october);
      expect(installment.total, 10);
    });

    test('do morador no cartão de outro morador: um empréstimo do dono em N parcelas', () {
      final purchase = _build(card: _card(owner: 'kelvynn'), debtor: 'cristiano');
      expect(purchase.expenses, isEmpty);
      final loan = purchase.loans.single;
      expect(loan.lenderMemberId, 'kelvynn');
      expect(loan.borrowerMemberId, 'cristiano');
      expect(loan.installmentsCount, 10);
      expect(loan.totalAmount.cents, 100000);
      expect(loan.firstDueDate, _october);
      expect(loan.houseFunding, isNull);
      expect(loan.installmentPlanIds, [purchase.plan.id]);
      expect(purchase.plan.destination, LineDestination.splitP2P);
      expect(purchase.plan.assignedMemberId, 'cristiano');
      expect(purchase.plan.coveredByLoans, isTrue);
    });

    test('do morador no cartão da Casa: um empréstimo do Caixa por fatura', () {
      final purchase = _build(debtor: 'cristiano');
      expect(purchase.loans, hasLength(10));
      expect(purchase.loans.every((l) => l.isHouseLender && l.installmentsCount == 1), isTrue);
      expect(purchase.loans.every((l) => l.houseFunding == HouseLoanFunding.cycle), isTrue);
      expect(purchase.loans.first.fundedOn, _october);
      expect(purchase.loans[1].fundedOn, _november);
      expect(purchase.loans[1].firstDueDate, _november);
      expect(purchase.loans.first.title, 'Geladeira (1/10) — Cristiano');
    });

    test('compra já em andamento: só as parcelas que faltam, na fatura de cada uma', () {
      // Compra de agosto em 3x: a 1/3 já veio em setembro, a próxima é a 2/3
      final purchase = _build(cents: 30000, count: 3, date: DateTime(2026, 8, 20), firstNumber: 2);
      expect(purchase.firstNumber, 2);
      expect(purchase.expenses.map((e) => e.title), ['Geladeira (2/3)', 'Geladeira (3/3)']);
      expect(purchase.expenses.map((e) => e.dueDate), [_october, _november]);
      expect(purchase.plan.anchorNumber, 2);
      expect(purchase.plan.anchorDueDate, _october);
      expect(purchase.plan.anchorLineDate, DateTime(2026, 8, 20));
    });

    test('compra do morador já em andamento: o empréstimo é do que falta', () {
      final purchase = _build(
        cents: 30000,
        count: 3,
        date: DateTime(2026, 8, 20),
        firstNumber: 2,
        card: _card(owner: 'kelvynn'),
        debtor: 'cristiano',
      );
      final loan = purchase.loans.single;
      expect(loan.totalAmount.cents, 20000);
      expect(loan.installmentsCount, 2);
      expect(loan.firstDueDate, _october);
    });

    test('cartão sem fechamento e vencimento não parcela', () {
      expect(
        () => _build(
          card: const PaymentMethod(id: 'pm_x', name: 'Cartão X', type: PaymentMethodType.card),
        ),
        throwsArgumentError,
      );
    });
  });

  group('a fatura confirma a compra lançada à mão', () {
    test('mesmo com o nome do banco diferente do digitado', () async {
      await repository.createInstallmentPurchase(_build());

      final first = await review(_card(), _october, [
        _line('a', _purchase, 'MAGAZINE LUIZA 01/10', 10000),
      ]);
      final line = lineOf(first, 'a');
      expect(first.statusOf(line), LineStatus.linked);
      expect(first.confirmedForecastOf(line)!.title, 'Geladeira (1/10)');
      final result = plan(first);
      expect(result.newExpenses, isEmpty);
      expect(result.installmentLinks.single.isForecast, isFalse);
      await repository.confirmImport(first, result);

      final next = await review(_card(), _november, [
        _line('a', _purchase, 'MAGAZINE LUIZA 02/10', 10000),
      ]);
      expect(next.confirmedForecastOf(lineOf(next, 'a'))!.title, 'Geladeira (2/10)');
      expect(plan(next).newExpenses, isEmpty);
    });

    test('compra já em andamento: a fatura confirma a parcela que veio', () async {
      final august = DateTime(2026, 8, 20);
      await repository.createInstallmentPurchase(
        _build(cents: 30000, count: 3, date: august, firstNumber: 2),
      );
      final session = await review(_card(), _october, [
        _line('a', august, 'MAGAZINE LUIZA 02/03', 10000),
      ]);
      expect(session.confirmedForecastOf(lineOf(session, 'a'))!.title, 'Geladeira (2/3)');
      expect(plan(session).newExpenses, isEmpty);
    });

    test('duas compras iguais em lojas diferentes: o nome desempata', () async {
      await repository.createInstallmentPurchase(_build(title: 'Magalu'));
      await repository.createInstallmentPurchase(_build(title: 'Casas Bahia'));

      final session = await review(_card(), _october, [
        _line('a', _purchase, 'CASAS BAHIA 01/10', 10000),
        _line('b', _purchase, 'MAGALU 01/10', 10000),
      ]);
      expect(session.confirmedForecastOf(lineOf(session, 'a'))!.title, 'Casas Bahia (1/10)');
      expect(session.confirmedForecastOf(lineOf(session, 'b'))!.title, 'Magalu (1/10)');
    });

    test('outro nome e outra data não é a compra lançada à mão', () async {
      await repository.createInstallmentPurchase(_build());
      final session = await review(_card(), _november, [
        _line('a', DateTime(2026, 10, 25), 'MAGAZINE LUIZA 01/10', 10000),
      ]);
      expect(
        session.installmentMatchOf(lineOf(session, 'a'))!.kind,
        InstallmentMatchKind.newPlan,
      );
    });

    test('outro número de parcelas não casa', () async {
      await repository.createInstallmentPurchase(_build());
      final session = await review(_card(), _october, [
        _line('a', _purchase, 'MAGAZINE LUIZA 01/12', 10000),
      ]);
      expect(
        session.installmentMatchOf(lineOf(session, 'a'))!.kind,
        InstallmentMatchKind.newPlan,
      );
    });

    test('do morador: a parcela já tem empréstimo e a fatura não lança outro', () async {
      final card = _card(owner: 'kelvynn');
      await repository.createInstallmentPurchase(_build(card: card, debtor: 'cristiano'));

      final session = await review(card, _october, [
        _line('a', _purchase, 'MAGAZINE LUIZA 01/10', 10000),
      ]);
      expect(session.statusOf(lineOf(session, 'a')), LineStatus.alreadyImported);
      final result = plan(session);
      expect(result.loans, isEmpty);
      expect(result.newExpenses, isEmpty);
    });
  });

  test('Próximos ciclos não projeta de novo o empréstimo da compra do morador', () async {
    await repository.createInstallmentPurchase(_build(debtor: 'cristiano'));
    final forecast = const UpcomingCyclesBuilder().build(
      schedule: schedule,
      expensesByCycle: const {},
      loans: const <P2PLoan>[],
      members: _members,
      paymentMethods: [_card()],
      today: DateTime(2026, 10, 20),
      installmentPlans: await repository.houseInstallmentPlans(),
    );
    expect(forecast.installments, isEmpty);
  });
}
