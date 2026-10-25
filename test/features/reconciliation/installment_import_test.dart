import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/domain/value_objects/cycle_schedule.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/core/errors/failures.dart';
import 'package:omni_lar/core/utils/uuid.dart';
import 'package:omni_lar/features/finance/data/datasources/mock_finance_datasource.dart';
import 'package:omni_lar/features/finance/domain/entities/category.dart';
import 'package:omni_lar/features/finance/domain/entities/house_expense.dart';
import 'package:omni_lar/features/finance/domain/entities/house_member.dart';
import 'package:omni_lar/features/finance/domain/entities/payment_method.dart';
import 'package:omni_lar/features/finance/domain/entities/split_rule.dart';
import 'package:omni_lar/features/p2p/data/datasources/mock_p2p_datasource.dart';
import 'package:omni_lar/features/p2p/domain/entities/p2p_loan.dart';
import 'package:omni_lar/features/reports/domain/services/upcoming_cycles_builder.dart';
import 'package:omni_lar/features/reconciliation/data/mock_import_repository.dart';
import 'package:omni_lar/features/reconciliation/domain/entities/imported_statement_line.dart';
import 'package:omni_lar/features/reconciliation/domain/entities/installment_plan.dart';
import 'package:omni_lar/features/reconciliation/domain/services/import_session.dart';
import 'package:omni_lar/features/reconciliation/domain/services/installment_matcher.dart';
import 'package:omni_lar/features/reconciliation/domain/services/statement_parser.dart';
import 'package:omni_lar/features/reconciliation/domain/services/statement_text.dart';

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

/// Linha como o leitor de CSV entrega: assinatura e parcela da descrição.
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

/// Estorno como o leitor de CSV entrega (crédito na fatura).
ImportedStatementLine _refund(String id, DateTime date, String description, int cents) =>
    ImportedStatementLine(
      id: id,
      date: date,
      description: description,
      amount: Money(cents),
      kind: StatementLineKind.refund,
      signature: '${StatementParser.signatureContent(date, -cents, description)}#1',
    );

final _purchase = DateTime(2026, 8, 20);
final _october = DateTime(2026, 10, 14);
final _november = DateTime(2026, 11, 14);

void main() {
  const schedule = CycleSchedule(1);
  late MockImportRepository repository;

  setUp(() {
    repository = MockImportRepository(finance: MockFinanceDataSource(), p2p: MockP2PDataSource());
  });

  /// Revisão como a tela monta: o que já foi importado e as compras parceladas.
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

  Future<ImportPlan> confirm(ImportSession session) async {
    final result = plan(session);
    await repository.confirmImport(session, result);
    return result;
  }

  ImportedStatementLine lineOf(ImportSession session, String id) =>
      session.lines.firstWhere((l) => l.id == id);

  group('primeira fatura da compra parcelada', () {
    test('lança a parcela do mês e deixa as seguintes previstas, uma por fatura', () async {
      final session = await review(_card(), _october, [
        _line('a', _purchase, 'MAGALU 03/10', 10000),
        _line('b', DateTime(2026, 10, 2), 'PADARIA', 5000),
      ]);
      expect(session.forecastsCreatedBy(lineOf(session, 'a')), 7);

      final result = plan(session);
      final magalu = result.newExpenses.where((e) => e.title.startsWith('Magalu')).toList();
      expect(magalu.map((e) => e.title), [
        'Magalu (3/10)',
        for (var n = 4; n <= 10; n++) 'Magalu ($n/10)',
      ]);
      final forecasts = magalu.skip(1).toList();
      expect(forecasts.every((e) => e.status == ExpenseStatus.pending && e.amount.cents == 10000), isTrue);
      expect(forecasts.first.dueDate, _november);
      expect(forecasts.last.dueDate, DateTime(2027, 5, 14));

      final installment = result.installmentPlans.single;
      expect(installment.total, 10);
      expect(installment.anchorNumber, 3);
      expect(result.installmentLinks.where((l) => l.isForecast), hasLength(7));
      expect(result.installmentLinks.where((l) => !l.isForecast).single.number, 3);
      expect(
        result.lineRecords.firstWhere((r) => r.line.id == 'a').installmentPlanId,
        installment.id,
      );
    });

    test('sem prever: o plano nasce, mas só a parcela do mês é lançada', () async {
      final session = (await review(_card(), _october, [
        _line('a', _purchase, 'MAGALU 03/10', 10000),
      ]))
          .withForecastInstallments(false);
      final result = plan(session);
      expect(result.newExpenses, hasLength(1));
      expect(result.installmentPlans, hasLength(1));
    });
  });

  group('fatura seguinte', () {
    test('a parcela prevista é confirmada, e não lançada de novo', () async {
      await confirm(await review(_card(), _october, [_line('a', _purchase, 'MAGALU 03/10', 10000)]));

      final next = await review(_card(), _november, [_line('a', _purchase, 'MAGALU 04/10', 10000)]);
      final line = lineOf(next, 'a');
      expect(next.statusOf(line), LineStatus.linked);
      expect(next.confirmedForecastOf(line)!.title, 'Magalu (4/10)');

      final result = plan(next);
      expect(result.newExpenses, isEmpty);
      final update = result.expenseUpdates.single;
      expect(update.dueDate, _november);
      expect(result.installmentLinks.single.isForecast, isFalse);
    });

    test('banco que avança a data a cada parcela e centavos de diferença também casam', () async {
      await confirm(await review(_card(), _october, [_line('a', _purchase, 'MAGALU 03/10', 10000)]));

      final next = await review(_card(), _november, [
        _line('a', DateTime(2026, 9, 20), 'MAGALU 04/10', 10003),
      ]);
      expect(next.statusOf(lineOf(next, 'a')), LineStatus.linked);
      expect(plan(next).expenseUpdates.single.amount.cents, 10003);
    });

    test('a mesma fatura lida de outro jeito (outra assinatura) não lança de novo', () async {
      await confirm(await review(_card(), _october, [_line('a', _purchase, 'MAGALU 03/10', 10000)]));

      final again = await review(_card(), _october, [_line('x', _purchase, 'Magalu parcela 3 de 10', 10000)]);
      expect(again.statusOf(lineOf(again, 'x')), LineStatus.alreadyImported);
      expect(plan(again).newExpenses, isEmpty);
    });

    test('duas compras iguais no mesmo lugar confirmam cada uma a sua prevista', () async {
      await confirm(await review(_card(), _october, [
        _line('a', _purchase, 'MAGALU 03/10', 10000),
        _line('b', _purchase, 'MAGALU 03/10', 10000),
      ]));
      final plans = await repository.installmentPlans('pm_magalu');
      expect(plans, hasLength(2));

      final next = await review(_card(), _november, [
        _line('a', _purchase, 'MAGALU 04/10', 10000),
        _line('b', _purchase, 'MAGALU 04/10', 10000),
      ]);
      final confirmed = {
        for (final id in ['a', 'b']) next.confirmedForecastOf(lineOf(next, id))!.id,
      };
      expect(confirmed, hasLength(2));
      expect(plan(next).newExpenses, isEmpty);
    });

    test('loja diferente com o mesmo valor e parcela não casa', () async {
      await confirm(await review(_card(), _october, [_line('a', _purchase, 'MAGALU 03/10', 10000)]));
      final next = await review(_card(), _november, [_line('a', _purchase, 'CASAS BAHIA 04/10', 10000)]);
      expect(next.installmentMatchOf(lineOf(next, 'a'))!.kind, InstallmentMatchKind.newPlan);
    });

    test('a primeira fatura não mostrou a parcela 4: a seguinte a lança e liga ao plano', () async {
      await confirm(
        (await review(_card(), _october, [_line('a', _purchase, 'MAGALU 03/10', 10000)]))
            .withForecastInstallments(false),
      );
      final next = await review(_card(), _november, [_line('a', _purchase, 'MAGALU 04/10', 10000)]);
      final line = lineOf(next, 'a');
      expect(next.installmentMatchOf(line)!.kind, InstallmentMatchKind.continues);
      expect(next.statusOf(line), LineStatus.newLine);

      final result = plan(next);
      expect(result.newExpenses.single.title, 'Magalu (4/10)');
      expect(result.installmentLinks.single.number, 4);
    });
  });

  group('dono do cartão e dono da parcela', () {
    test('cartão de morador e parcela da Casa: previstas no cartão dele, sem "pago do bolso"', () async {
      final result = plan(await review(_card(owner: 'kelvynn'), _october, [
        _line('a', _purchase, 'MAGALU 03/10', 10000),
      ]));
      final forecasts = result.newExpenses.skip(1);
      expect(forecasts, hasLength(7));
      expect(forecasts.every((e) => e.paymentMethodId == 'pm_magalu' && !e.paidOutOfPocket), isTrue);
    });

    for (final owner in [null, 'kelvynn']) {
      final label = owner == null ? 'cartão da Casa' : 'cartão de morador';
      test('$label e parcela de um morador: sem previstas, e a próxima vem para o mesmo devedor', () async {
        final card = _card(owner: owner);
        var first = await review(card, _october, [_line('a', _purchase, 'MAGALU 03/10', 10000)]);
        first = first.withLine(
          lineOf(first, 'a').copyWith(destination: LineDestination.splitP2P, assignedMemberId: 'cristiano'),
        );
        expect(first.forecastsCreatedBy(lineOf(first, 'a')), 0);
        final created = await confirm(first);
        expect(created.newExpenses, isEmpty);
        expect(created.loans.single.borrowerMemberId, 'cristiano');
        expect(created.installmentPlans.single.assignedMemberId, 'cristiano');

        final next = await review(card, _november, [_line('a', _purchase, 'MAGALU 04/10', 10000)]);
        final line = lineOf(next, 'a');
        expect(line.destination, LineDestination.splitP2P);
        expect(line.assignedMemberId, 'cristiano');
        final result = await confirm(next);
        expect(result.loans.single.borrowerMemberId, 'cristiano');

        // A mesma fatura de novo: a parcela já foi tratada
        final again = await review(card, _november, [_line('x', _purchase, 'Magalu 4/10', 10000)]);
        expect(again.statusOf(lineOf(again, 'x')), LineStatus.alreadyImported);
      });
    }

    test('parcela prevista da Casa que vem para um morador: ela e as seguintes deixam de ser despesa', () async {
      await confirm(await review(_card(), _october, [_line('a', _purchase, 'MAGALU 03/10', 10000)]));
      var next = await review(_card(), _november, [_line('a', _purchase, 'MAGALU 04/10', 10000)]);
      final forecast = next.confirmedForecastOf(lineOf(next, 'a'))!;
      next = next.withLine(
        lineOf(next, 'a').copyWith(destination: LineDestination.splitP2P, assignedMemberId: 'cristiano'),
      );
      expect(next.statusOf(lineOf(next, 'a')), LineStatus.newLine);

      final result = plan(next);
      // Esta prevista e as seis seguintes deixam de ser da Casa
      expect(result.forecastDeletions, hasLength(7));
      expect(result.forecastDeletions.first, forecast.id);
      expect(result.loans.single.totalAmount.cents, 10000);
      expect(result.installmentPlans.single.destination, LineDestination.splitP2P);
    });

    test('parcela dividida: as previstas ficam só com a parte da Casa', () async {
      var session = await review(_card(), _october, [_line('a', _purchase, 'MAGALU 03/10', 10000)]);
      session = session.splitLine('a', const Money(6000));
      final parts = session.partsOf('a');
      session = session.withLine(
        parts[1].copyWith(destination: LineDestination.splitP2P, assignedMemberId: 'cristiano'),
      );

      final result = plan(session);
      final forecasts = result.newExpenses.where((e) => e.status == ExpenseStatus.pending).skip(1);
      expect(forecasts, hasLength(7));
      expect(forecasts.every((e) => e.amount.cents == 6000), isTrue);
      expect(result.installmentPlans.single.installmentAmount.cents, 10000);
    });
  });

  group('consistência com o resto do app', () {
    test('data da compra original: as previstas caem cada uma no período da sua fatura', () async {
      final result = plan(await review(_card(), _october, [_line('a', _purchase, 'MAGALU 03/10', 10000)]));
      final forecasts = result.newExpenses.skip(1).toList();
      // Fechamento dia 9: a parcela 4 é da fatura de 14/11, comprada até 08/11
      expect(forecasts.first.date, DateTime(2026, 11, 8, 12));
      expect(forecasts.last.date, DateTime(2027, 5, 8, 12));
    });

    test('data dentro da fatura: as previstas avançam um mês a partir dela', () async {
      final result = plan(await review(_card(), _october, [
        _line('a', DateTime(2026, 10, 2), 'MAGALU 03/10', 10000),
      ]));
      expect(result.newExpenses[1].date, DateTime(2026, 11, 2));
    });

    test('prevista já paga no app: a fatura confirma sem mexer em quem pagou', () async {
      final paid = HouseExpense(
        id: 'prevista_4',
        title: 'Magalu (4/10)',
        amount: const Money(10000),
        date: DateTime(2026, 11, 8),
        dueDate: _november,
        categoryId: 'cat_casa',
        paidByMemberId: 'kelvynn',
        paymentMethodId: 'pm_magalu',
        splitRule: const SplitRule.percentage(null),
        paidAt: DateTime(2026, 11, 10),
        paidOutOfPocket: true,
      );
      final installment = InstallmentPlan(
        id: 'p',
        paymentMethodId: 'pm_magalu',
        merchantKey: InstallmentMatcher.merchantKeyOf('MAGALU 03/10'),
        title: 'Magalu',
        total: 10,
        installmentAmount: const Money(10000),
        anchorNumber: 3,
        anchorLineDate: _purchase,
        anchorDueDate: _october,
        parcels: {4: InstallmentParcel(expense: paid, isForecast: true)},
        importedNumbers: const {3},
      );
      final session = ImportSession.start(
        source: _card(owner: 'kelvynn'),
        fileName: 'fatura.csv',
        lines: [_line('a', _purchase, 'MAGALU 04/10', 10000)],
        payerMemberId: 'kelvynn',
      ).withInvoiceDueDate(_november).withInstallmentPlans(
        [installment],
        memberIds: {'kelvynn', 'cristiano'},
        categoryIds: {'cat_casa'},
      );
      expect(session.statusOf(session.lines.single), LineStatus.linked);
      final result = plan(session);
      expect(result.expenseUpdates, isEmpty);
      expect(result.installmentLinks.single.expenseId, 'prevista_4');

      // Valor diferente: só o valor muda
      final differs = ImportSession.start(
        source: _card(owner: 'kelvynn'),
        fileName: 'fatura.csv',
        lines: [_line('a', _purchase, 'MAGALU 04/10', 10050)],
        payerMemberId: 'kelvynn',
      ).withInvoiceDueDate(_november).withInstallmentPlans(
        [installment],
        memberIds: {'kelvynn', 'cristiano'},
        categoryIds: {'cat_casa'},
      );
      final update = plan(differs).expenseUpdates.single;
      expect(update.amount.cents, 10050);
      expect(update.paidOutOfPocket, isTrue);
    });

    test('compra lançada à mão que a fatura casa vira a parcela, com as previstas', () async {
      final manual = HouseExpense(
        id: 'manual',
        title: 'Magalu',
        amount: const Money(10000),
        date: DateTime(2026, 10, 2),
        dueDate: _october,
        categoryId: 'cat_casa',
        paidByMemberId: 'kelvynn',
        paymentMethodId: 'pm_magalu',
        splitRule: const SplitRule.percentage(null),
        status: ExpenseStatus.pending,
      );
      final session = (await review(_card(), _october, [
        _line('a', DateTime(2026, 10, 2), 'MAGALU 01/10', 10000),
      ]))
          .withExpenses([manual]);
      expect(session.statusOf(session.lines.single), LineStatus.linked);
      expect(session.forecastsCreatedBy(session.lines.single), 9);

      final result = plan(session);
      expect(result.installmentLinks.where((l) => !l.isForecast).single.expenseId, 'manual');
      expect(result.newExpenses, hasLength(9));
    });
  });

  group('desfazer', () {
    test('não desfaz a fatura que criou o plano enquanto a seguinte o usa', () async {
      await confirm(await review(_card(), _october, [_line('a', _purchase, 'MAGALU 03/10', 10000)]));
      await confirm(await review(_card(), _november, [_line('a', _purchase, 'MAGALU 04/10', 10000)]));
      final history = await repository.getHistory();
      final novemberBatch = history.first;
      final octoberBatch = history.last;

      await expectLater(repository.undoImport(octoberBatch.id), throwsA(isA<ValidationFailure>()));

      await repository.undoImport(novemberBatch.id);
      final plans = await repository.installmentPlans('pm_magalu');
      expect(plans.single.forecastOf(4), isNotNull);

      await repository.undoImport(octoberBatch.id);
      expect(await repository.installmentPlans('pm_magalu'), isEmpty);
    });

    test('só desfaz a fatura mais recente da compra, e desfazer traz de volta as previstas', () async {
      await confirm(await review(_card(), _october, [_line('a', _purchase, 'MAGALU 03/10', 10000)]));
      var november = await review(_card(), _november, [_line('a', _purchase, 'MAGALU 04/10', 10000)]);
      november = november.withLine(
        lineOf(november, 'a').copyWith(destination: LineDestination.splitP2P, assignedMemberId: 'cristiano'),
      );
      await confirm(november);
      await confirm(await review(_card(), DateTime(2026, 12, 14), [_line('a', _purchase, 'MAGALU 05/10', 10000)]));
      final history = await repository.getHistory();
      expect((await repository.installmentPlans('pm_magalu')).single.forecastOf(6), isNull);

      await expectLater(repository.undoImport(history[1].id), throwsA(isA<ValidationFailure>()));
      await repository.undoImport(history[0].id);
      await repository.undoImport(history[1].id);

      final restored = (await repository.installmentPlans('pm_magalu')).single;
      expect(restored.destination, LineDestination.house);
      expect([for (var n = 4; n <= 10; n++) restored.forecastOf(n) != null], everyElement(isTrue));
    });
  });

  /// Primeira fatura com a parcela 3/10 para [debtor] (empréstimo), ou da Casa.
  Future<void> firstInvoice(PaymentMethod card, {String? debtor}) async {
    var first = await review(card, _october, [_line('a', _purchase, 'MAGALU 03/10', 10000)]);
    if (debtor != null) {
      first = first.withLine(
        lineOf(first, 'a').copyWith(destination: LineDestination.splitP2P, assignedMemberId: debtor),
      );
    }
    await confirm(first);
  }

  group('aceite único do parcelamento', () {
    test('o empréstimo da primeira fatura aponta para o plano novo, ainda não aceito', () async {
      var first = await review(_card(), _october, [_line('a', _purchase, 'MAGALU 03/10', 10000)]);
      first = first.withLine(
        lineOf(first, 'a').copyWith(destination: LineDestination.splitP2P, assignedMemberId: 'cristiano'),
      );
      final result = plan(first);
      final installment = result.installmentPlans.single;
      expect(result.loans.single.installmentPlanIds, [installment.id]);
      expect(installment.isAccepted, isFalse);
      expect(result.loans.single.title, isNot(contains('aceitos')));
    });

    test('parcelamento aceito: a parcela seguinte vai num empréstimo próprio, que nasce aceito', () async {
      await firstInvoice(_card(), debtor: 'cristiano');
      final planId = (await repository.installmentPlans('pm_magalu')).single.id;
      await repository.acceptInstallmentPlan(planId);

      final next = await review(_card(), _november, [
        _line('a', _purchase, 'MAGALU 04/10', 10000),
        _line('b', DateTime(2026, 10, 30), 'PADARIA', 3000),
      ]);
      final withBakery = next.withLine(
        lineOf(next, 'b').copyWith(destination: LineDestination.splitP2P, assignedMemberId: 'cristiano'),
      );
      expect(next.installmentMatchOf(lineOf(next, 'a'))!.plan!.isAccepted, isTrue);

      final result = plan(withBakery);
      expect(result.loans, hasLength(2));
      final accepted = result.loans.firstWhere((l) => l.installmentPlanIds.isNotEmpty);
      expect(accepted.title, contains('parcelamentos aceitos'));
      expect(accepted.installmentPlanIds, [planId]);
      expect(accepted.totalAmount.cents, 10000);
      final other = result.loans.firstWhere((l) => l.installmentPlanIds.isEmpty);
      expect(other.totalAmount.cents, 3000);
    });

    test('outro devedor: o aceite de quem devia antes não vale', () async {
      await firstInvoice(_card(), debtor: 'cristiano');
      final planId = (await repository.installmentPlans('pm_magalu')).single.id;
      await repository.acceptInstallmentPlan(planId);

      var next = await review(_card(), _november, [_line('a', _purchase, 'MAGALU 04/10', 10000)]);
      next = next.withLine(lineOf(next, 'a').copyWith(assignedMemberId: 'kelvynn'));
      final result = await confirm(next);
      expect(result.loans.single.title, isNot(contains('aceitos')));
      final stored = (await repository.installmentPlans('pm_magalu')).single;
      expect(stored.assignedMemberId, 'kelvynn');
      expect(stored.isAccepted, isFalse);
    });
  });

  group('estorno da compra parcelada', () {
    test('cancelar a compra apaga as previstas, zera a parcela do mês e encerra o plano', () async {
      await firstInvoice(_card());
      var next = await review(_card(), _november, [
        _line('a', _purchase, 'MAGALU 04/10', 10000),
        _refund('r', DateTime(2026, 10, 25), 'ESTORNO MAGALU', 70000),
      ]);
      final refund = lineOf(next, 'r');
      final option = next.refundOptionsOf(refund).firstWhere((o) => o.plan != null);
      expect(option.suggested, isTrue);
      expect(option.lineId, 'a');
      next = next.withRefundChoice('r', option.key);
      expect(next.effectiveAmountOf(lineOf(next, 'a')).isZero, isTrue);

      final result = plan(next);
      // A 4 (desta fatura) e as previstas 5 a 10
      expect(result.forecastDeletions, hasLength(7));
      expect(result.expenseUpdates, isEmpty);
      expect(result.installmentLinks, isEmpty);
      expect(result.installmentPlans.single.status, InstallmentPlanStatus.cancelled);
      expect(result.lineRecords.firstWhere((r) => r.line.id == 'r').installmentPlanId, option.plan!.id);

      await repository.confirmImport(next, result);
      final cancelled = (await repository.installmentPlans('pm_magalu')).single;
      expect(cancelled.status, InstallmentPlanStatus.cancelled);
      expect([for (var n = 4; n <= 10; n++) cancelled.forecastOf(n)], everyElement(isNull));
      expect(await repository.houseInstallmentPlans(), isEmpty);

      // Desfazer devolve a compra e as previstas
      await repository.undoImport((await repository.getHistory()).first.id);
      final restored = (await repository.installmentPlans('pm_magalu')).single;
      expect(restored.status, InstallmentPlanStatus.active);
      expect([for (var n = 4; n <= 10; n++) restored.forecastOf(n) != null], everyElement(isTrue));
    });

    test('estorno menor que a parcela do mês: ela fica com o resto e as seguintes saem', () async {
      await firstInvoice(_card());
      var next = await review(_card(), _november, [
        _line('a', _purchase, 'MAGALU 04/10', 10000),
        _refund('r', DateTime(2026, 10, 25), 'ESTORNO MAGALU', 4000),
      ]);
      final option = next.refundOptionsOf(lineOf(next, 'r')).firstWhere((o) => o.plan != null);
      next = next.withRefundChoice('r', option.key);
      final result = plan(next);
      expect(result.expenseUpdates.single.amount.cents, 6000);
      expect(result.installmentLinks.single.number, 4);
      expect(result.forecastDeletions, hasLength(6));
    });

    test('estorno de uma parcela já lançada abate só dela', () async {
      await firstInvoice(_card());
      final next = await review(_card(), _november, [
        _line('a', _purchase, 'MAGALU 04/10', 10000),
        _refund('r', DateTime(2026, 10, 25), 'ESTORNO MAGALU 03/10', 10000),
      ]);
      final parcel3 = (await repository.installmentPlans('pm_magalu')).single.parcels[3]!.expense;
      final options = next.refundOptionsOf(lineOf(next, 'r'));
      final option = options.firstWhere((o) => o.expense?.id == parcel3.id);
      expect(option.suggested, isTrue);
      expect(option.label, contains('parcela 3/10'));

      final result = plan(next.withRefundChoice('r', option.key));
      expect(result.expenseDeletions.single.id, parcel3.id);
      expect(result.forecastDeletions, isEmpty);
      expect(result.installmentPlans, isEmpty);
    });

    test('compra de morador: cancelar encerra o plano, sem previstas para apagar', () async {
      await firstInvoice(_card(), debtor: 'cristiano');
      final next = await review(_card(), _november, [
        _refund('r', DateTime(2026, 10, 25), 'ESTORNO MAGALU', 70000),
      ]);
      final option = next.refundOptionsOf(lineOf(next, 'r')).single;
      expect(option.label, contains('as próximas parcelas não vêm mais'));
      final result = plan(next.withRefundChoice('r', option.key));
      expect(result.isEmpty, isFalse);
      expect(result.installmentPlans.single.status, InstallmentPlanStatus.cancelled);
    });
  });

  group('antecipação', () {
    test('uma linha só com o que faltava, com desconto: quita as previstas e encerra a compra', () async {
      await firstInvoice(_card());
      final next = await review(_card(), _november, [
        _line('a', _purchase, 'MAGALU 04/10', 10000),
        _line('b', DateTime(2026, 10, 28), 'ANTECIPACAO MAGALU', 54000),
      ]);
      final line = lineOf(next, 'b');
      final option = next.prepaymentOptionsOf(line).single;
      expect(option.numbers, [5, 6, 7, 8, 9, 10]);
      expect(option.remaining.cents, 60000);
      expect(next.chosenPrepayment(line), isNotNull);

      final result = plan(next);
      expect(result.newExpenses.single.title, 'Magalu (antecipação 5 a 10/10)');
      expect(result.newExpenses.single.amount.cents, 54000);
      expect(result.forecastDeletions, hasLength(6));
      expect(result.installmentLinks.single.number, 4);
      expect(result.installmentPlans.single.status, InstallmentPlanStatus.finished);

      await repository.confirmImport(next, result);
      expect(await repository.houseInstallmentPlans(), isEmpty);
    });

    test('sem a palavra antecipação e com valor que não bate: só sugere, e o usuário decide', () async {
      await firstInvoice(_card());
      var next = await review(_card(), _november, [
        _line('a', _purchase, 'MAGALU 04/10', 10000),
        _line('b', DateTime(2026, 10, 28), 'MAGALU', 50000),
      ]);
      final line = lineOf(next, 'b');
      expect(next.prepaymentOptionsOf(line), hasLength(1));
      expect(next.chosenPrepayment(line), isNull);
      expect(plan(next).forecastDeletions, isEmpty);

      next = next.withPrepaymentChoice('b', next.prepaymentOptionsOf(line).single.plan.id);
      expect(plan(next).forecastDeletions, hasLength(6));
      next = next.withPrepaymentChoice('b', null);
      expect(plan(next).forecastDeletions, isEmpty);
    });

    test('"05/10 A 10/10" no fim da descrição não vira compra parcelada nova', () async {
      await firstInvoice(_card());
      final next = await review(_card(), _november, [
        _line('a', _purchase, 'MAGALU 04/10', 10000),
        _line('b', DateTime(2026, 10, 28), 'ANTECIPACAO MAGALU 05/10 A 10/10', 60000),
      ]);
      final line = lineOf(next, 'b');
      expect(next.chosenPrepayment(line), isNotNull);
      expect(next.installmentMatchOf(line), isNull);
      expect(next.forecastsCreatedBy(line), 0);
      final result = plan(next);
      expect(result.installmentPlans.single.status, InstallmentPlanStatus.finished);
      expect(result.newExpenses.single.title, 'Magalu (antecipação 5 a 10/10)');
    });

    test('parcelas antecipadas linha a linha: cada uma confirma a sua prevista nesta fatura', () async {
      await firstInvoice(_card());
      final next = await review(_card(), _november, [
        for (var n = 4; n <= 10; n++) _line('p$n', _purchase, 'MAGALU ${n.toString().padLeft(2, '0')}/10', 10000),
      ]);
      final result = plan(next);
      expect(result.newExpenses, isEmpty);
      expect(result.expenseUpdates, hasLength(7));
      expect(result.expenseUpdates.every((e) => e.dueDate == _november), isTrue);
    });
  });

  group('projeção em Próximos ciclos', () {
    test('a parcela do morador aparece em cada ciclo em que ainda vai ser cobrada', () async {
      await firstInvoice(_card(), debtor: 'cristiano');
      final plans = await repository.houseInstallmentPlans();
      final forecast = const UpcomingCyclesBuilder().build(
        schedule: schedule,
        expensesByCycle: const {},
        loans: const [],
        members: _members,
        paymentMethods: [_card()],
        today: DateTime(2026, 10, 20),
        installmentPlans: plans,
      );
      for (final cycle in forecast.cycles) {
        final entry = cycle.projected.single;
        expect(entry.payerId, 'cristiano');
        expect(entry.receiverId, isNull, reason: 'cartão da Casa: deve ao Caixa');
        expect(cycle.preview.memberById('cristiano')!.p2pToPay.cents, 10000);
      }
      expect(forecast.cycles.first.projected.single.title, 'Magalu 4/10');
      final projection = forecast.installments.single;
      expect(projection.remainingCount, 7);
      expect(projection.remaining.cents, 70000);
      expect(projection.lastDueDate, DateTime(2027, 5, 14));
      expect(projection.accepted, isFalse);
      expect(forecast.payoffs, isEmpty);
    });

    test('cartão de morador: a parcela é devida ao dono; da Casa não projeta (já é prevista)', () async {
      await firstInvoice(_card(owner: 'kelvynn'), debtor: 'cristiano');
      final forecast = const UpcomingCyclesBuilder().build(
        schedule: schedule,
        expensesByCycle: const {},
        loans: const <P2PLoan>[],
        members: _members,
        paymentMethods: [_card(owner: 'kelvynn')],
        today: DateTime(2026, 10, 20),
        installmentPlans: await repository.houseInstallmentPlans(),
      );
      expect(forecast.cycles.first.projected.single.receiverId, 'kelvynn');
      expect(forecast.cycles.first.preview.memberById('kelvynn')!.p2pToReceive.cents, 10000);

      final house = MockImportRepository(finance: MockFinanceDataSource(), p2p: MockP2PDataSource());
      repository = house;
      await firstInvoice(_card());
      final none = const UpcomingCyclesBuilder().build(
        schedule: schedule,
        expensesByCycle: const {},
        loans: const <P2PLoan>[],
        members: _members,
        paymentMethods: [_card()],
        today: DateTime(2026, 10, 20),
        installmentPlans: await house.houseInstallmentPlans(),
      );
      expect(none.installments, isEmpty);
    });

    test('a parcela que a fatura já trouxe sai da projeção', () async {
      await firstInvoice(_card(), debtor: 'cristiano');
      await confirm(await review(_card(), _november, [_line('a', _purchase, 'MAGALU 04/10', 10000)]));
      final forecast = const UpcomingCyclesBuilder().build(
        schedule: schedule,
        expensesByCycle: const {},
        loans: const <P2PLoan>[],
        members: _members,
        paymentMethods: [_card()],
        today: DateTime(2026, 10, 20),
        installmentPlans: await repository.houseInstallmentPlans(),
      );
      expect(forecast.cycles.first.projected, isEmpty);
      expect(forecast.cycles[1].projected.single.title, 'Magalu 5/10');
      expect(forecast.installments.single.remainingCount, 6);
    });
  });

  group('casamento', () {
    test('valor muito diferente não é a mesma compra', () {
      final installment = InstallmentPlan(
        id: 'p',
        paymentMethodId: 'pm_magalu',
        merchantKey: InstallmentMatcher.merchantKeyOf('MAGALU 03/10'),
        title: 'Magalu',
        total: 10,
        installmentAmount: const Money(10000),
        anchorNumber: 3,
        anchorLineDate: _purchase,
        anchorDueDate: _october,
      );
      final matches = InstallmentMatcher.match(
        lines: [_line('a', _purchase, 'MAGALU 04/10', 12000)],
        plans: [installment],
        invoiceDueDate: _november,
      );
      expect(matches['a']!.kind, InstallmentMatchKind.newPlan);
    });

    test('addMonths fica no último dia do mês quando o dia não existe', () {
      expect(addMonths(DateTime(2026, 1, 31), 1), DateTime(2026, 2, 28));
      expect(addMonths(DateTime(2026, 11, 14), 3), DateTime(2027, 2, 14));
    });
  });
}
