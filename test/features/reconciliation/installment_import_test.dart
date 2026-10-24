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
import 'package:omni_lar/features/p2p/data/datasources/mock_p2p_datasource.dart';
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
