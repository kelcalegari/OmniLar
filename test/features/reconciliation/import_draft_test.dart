import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/di/service_locator.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/features/auth/presentation/cubit/auth_cubit.dart';
import 'package:omni_lar/features/finance/domain/entities/house_expense.dart';
import 'package:omni_lar/features/finance/domain/entities/payment_method.dart';
import 'package:omni_lar/features/finance/domain/entities/split_rule.dart';
import 'package:omni_lar/features/finance/presentation/cubit/finance_cubit.dart';
import 'package:omni_lar/features/p2p/presentation/cubit/p2p_cubit.dart';
import 'package:omni_lar/features/reconciliation/data/import_draft_store.dart';
import 'package:omni_lar/features/reconciliation/domain/entities/imported_statement_line.dart';
import 'package:omni_lar/features/reconciliation/domain/services/import_draft_codec.dart';
import 'package:omni_lar/features/reconciliation/domain/services/import_session.dart';
import 'package:omni_lar/features/reconciliation/presentation/pages/import_page.dart';

const _card = PaymentMethod(
  id: 'pm_nubank',
  name: 'Nubank',
  type: PaymentMethodType.card,
  ownerMemberId: 'kelvynn',
  closingDay: 28,
  dueDay: 10,
);

void main() {
  group('Rascunho da revisão', () {
    final lines = [
      ImportedStatementLine(
        id: 'mercado',
        date: DateTime(2026, 10, 12),
        description: 'PAO DE ACUCAR',
        amount: const Money(48560),
        signature: '2026-10-12|48560|pao de acucar#1',
        installmentNumber: 2,
        installmentsTotal: 3,
      ),
      ImportedStatementLine(
        id: 'farm',
        date: DateTime(2026, 10, 7),
        description: 'FARM RIO',
        amount: const Money(32000),
      ),
      ImportedStatementLine(
        id: 'estorno',
        date: DateTime(2026, 10, 9),
        description: 'ESTORNO FARM RIO',
        amount: const Money(5000),
        kind: StatementLineKind.refund,
        destination: LineDestination.ignored,
      ),
    ];
    final launched = HouseExpense(
      id: 'e_mercado',
      title: 'Mercado',
      amount: const Money(48560),
      date: DateTime(2026, 10, 11),
      dueDate: DateTime(2026, 11, 10),
      categoryId: 'cat',
      paidByMemberId: 'kelvynn',
      paymentMethodId: 'pm_caixa',
      splitRule: const SplitRule.percentage(null),
    );

    test('guarda e devolve as decisões, as divisões e os estornos', () {
      var session = ImportSession.start(source: _card, fileName: 'fatura.csv', lines: lines, payerMemberId: 'kelvynn')
          .withExpenses([launched])
          .withDecision('mercado', MatchDecision.accepted)
          .withRefundChoice('estorno', 'line:farm')
          .withInvoicePayment(DateTime(2026, 11, 8), byHouse: true);
      session = session
          .splitLine('farm', const Money(20000))
          .withLine(session.lines[1].copyWith(title: 'Vestido'));
      session = session.withLine(
        session.lines[2].copyWith(destination: LineDestination.splitP2P, assignedMemberId: 'cristiano'),
      );

      final restored = ImportDraftCodec.fromJson(ImportDraftCodec.toJson(session), _card)!;

      expect(restored.lines.map((l) => l.id), session.lines.map((l) => l.id));
      expect(restored.lines[0].installmentNumber, 2);
      expect(restored.lines[2].splitFrom, 'farm');
      expect(restored.lines[2].assignedMemberId, 'cristiano');
      expect(restored.invoiceDueDate, session.invoiceDueDate);
      expect(restored.invoicePaidByHouse, isTrue);
      expect(restored.decisions, {'mercado': MatchDecision.accepted});

      // As despesas parecidas são buscadas de novo, e a resposta "é a mesma" continua valendo
      final refreshed = restored.withExpenses([launched]);
      expect(refreshed.statusOf(refreshed.lines[0]), LineStatus.linked);
    });

    test('rascunho de outro cartão ou de outra versão não é retomado', () {
      final session = ImportSession.start(source: _card, fileName: 'f.csv', lines: lines, payerMemberId: 'kelvynn');
      final json = ImportDraftCodec.toJson(session);
      const other = PaymentMethod(id: 'pm_outro', name: 'Outro', type: PaymentMethodType.card);

      expect(ImportDraftCodec.fromJson(json, other), isNull);
      expect(ImportDraftCodec.fromJson({...json, 'version': 99}, _card), isNull);
    });

    test('o rascunho fica por cartão ou conta e some ao descartar', () async {
      final store = ImportDraftStore();
      await store.save('pm_1', 'fatura.csv', {'a': 1});

      expect((await store.load('pm_1'))!.fileName, 'fatura.csv');
      expect(await store.load('pm_2'), isNull);
      await store.clear('pm_1');
      expect(await store.load('pm_1'), isNull);
    });
  });

  group('Na tela', () {
    setUpAll(() async {
      if (!sl.isRegistered<AuthCubit>()) {
        await initServiceLocator();
      }
      await sl<AuthCubit>().signInDemo(memberId: 'member_carlos');
      await sl<FinanceCubit>().loadCycleData();
    });

    Widget page() => MultiBlocProvider(
          providers: [
            BlocProvider<FinanceCubit>.value(value: sl<FinanceCubit>()),
            BlocProvider<P2PCubit>.value(value: sl<P2PCubit>()),
          ],
          child: const MaterialApp(home: ImportPage(initialSourceId: 'pm_card_marina')),
        );

    testWidgets('sair no meio da revisão e voltar retoma de onde parou', (tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(page());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Usar fatura de exemplo'));
      await tester.pumpAndSettle();
      while (find.text('É a mesma').evaluate().isNotEmpty) {
        final row = find.ancestor(of: find.text('É a mesma').first, matching: find.byType(Wrap)).first;
        await tester.tap(find.descendant(of: row, matching: find.text('São diferentes')));
        await tester.pumpAndSettle();
      }

      // Marca tudo como ignorado e sai da página
      await tester.tap(find.textContaining('linhas para editar juntas'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('import_bulk_destination')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ignorar').last);
      await tester.pumpAndSettle();
      expect(find.text('Ignoradas (5)'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();

      // Volta: a revisão aparece para retomar
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();
      expect(find.textContaining('Revisão em andamento: fatura_exemplo.csv'), findsOneWidget);
      await tester.tap(find.byKey(const Key('import_resume_draft')));
      await tester.pumpAndSettle();
      expect(find.text('Ignoradas (5)'), findsOneWidget);

      // Descartar some com o aviso
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Descartar'));
      await tester.pumpAndSettle();
      expect(await tester.runAsync(() => sl<ImportDraftStore>().load('pm_card_marina')), isNull);
      expect(find.textContaining('Revisão em andamento'), findsNothing);
    });
  });
}
