import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/di/service_locator.dart';
import 'package:omni_lar/core/domain/value_objects/cycle_schedule.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/features/auth/presentation/cubit/auth_cubit.dart';
import 'package:omni_lar/features/finance/domain/entities/house_member.dart';
import 'package:omni_lar/features/finance/domain/entities/payment_method.dart';
import 'package:omni_lar/features/finance/presentation/cubit/finance_cubit.dart';
import 'package:omni_lar/features/p2p/presentation/cubit/p2p_cubit.dart';
import 'package:omni_lar/features/reconciliation/domain/entities/imported_statement_line.dart';
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

const _members = [
  HouseMember(id: 'kelvynn', name: 'Kelvynn', defaultSplitPercent: 60),
  HouseMember(id: 'cristiano', name: 'Cristiano', defaultSplitPercent: 40),
];

ImportSession _session() => ImportSession.start(
      source: _card,
      fileName: 'fatura.csv',
      lines: [
        ImportedStatementLine(
          id: 'line_0',
          date: DateTime(2026, 10, 3),
          description: 'SUPERMERCADO EXTRA',
          amount: const Money(30000),
          signature: '2026-10-03|30000|supermercado extra#1',
        ),
        ImportedStatementLine(
          id: 'line_1',
          date: DateTime(2026, 10, 4),
          description: 'PADARIA',
          amount: const Money(2500),
        ),
      ],
      payerMemberId: 'kelvynn',
    );

void main() {
  group('Dividir linha', () {
    test('a compra vira duas partes que somam o valor da linha, no mesmo lugar', () {
      final session = _session().splitLine('line_0', const Money(18000));

      expect(session.lines.map((l) => l.id), ['line_0#1', 'line_0#2', 'line_1']);
      expect(session.lines[0].amount.cents, 18000);
      expect(session.lines[1].amount.cents, 12000);
      expect(session.lines.take(2).every((l) => l.splitFrom == 'line_0'), isTrue);
      // A assinatura é da linha do arquivo: a reimportação reconhece as duas partes
      expect(session.lines[1].signature, '2026-10-03|30000|supermercado extra#1');
      expect(session.totals.file.cents, 32500);
    });

    test('valor zero ou maior que a linha não divide', () {
      final session = _session();
      expect(session.splitLine('line_0', const Money(0)).lines, hasLength(2));
      expect(session.splitLine('line_0', const Money(30000)).lines, hasLength(2));
    });

    test('cada parte vai para um destino: Casa, empréstimo e pessoal', () {
      var session = _session().splitLine('line_0', const Money(18000));
      session = session.splitLine('line_0#2', const Money(7000));
      expect(session.partsOf('line_0').map((l) => l.amount.cents), [18000, 7000, 5000]);

      session = session
          .withLine(session.lines[1].copyWith(destination: LineDestination.splitP2P, assignedMemberId: 'cristiano'))
          .withLine(session.lines[2].copyWith(destination: LineDestination.cardOwnerPersonal));
      expect(session.totals.house.cents, 18000 + 2500);
      expect(session.totals.loans.cents, 7000);
      expect(session.totals.personal.cents, 5000);

      final plan = session.buildPlan(
        members: _members,
        categories: const [],
        schedule: const CycleSchedule(5),
      );
      expect(plan.newExpenses.map((e) => e.amount.cents), [18000, 2500]);
      expect(plan.loans.single.totalAmount.cents, 7000);
      // Parte com decisão diferente não vira regra aprendida do estabelecimento
      expect(session.rulesToLearn().any((r) => r.matchKey == 'supermercado extra'), isFalse);
      // E não sugere "aplicar a todas" entre as partes
      expect(session.similarLines(session.lines[0]), isEmpty);
    });

    test('juntar devolve a linha original com o valor inteiro', () {
      final split = _session().splitLine('line_0', const Money(18000)).splitLine('line_0#2', const Money(7000));
      final merged = split.mergeSplit('line_0');

      expect(merged.lines.map((l) => l.id), ['line_0', 'line_1']);
      expect(merged.lines.first.amount.cents, 30000);
      expect(merged.lines.first.splitFrom, isNull);
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

    testWidgets('dividir uma linha do exemplo e juntar de novo', (tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<FinanceCubit>.value(value: sl<FinanceCubit>()),
            BlocProvider<P2PCubit>.value(value: sl<P2PCubit>()),
          ],
          child: const MaterialApp(home: ImportPage(initialSourceId: 'pm_card_marina')),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Usar fatura de exemplo'));
      await tester.pumpAndSettle();
      expect(find.text('Todas (5)'), findsOneWidget);

      // Divide a primeira linha (R$ 485,60): metade em cada parte
      await tester.tap(find.byKey(const Key('import_split_sample_1')));
      await tester.pumpAndSettle();
      expect(find.text('Segunda parte: ${const Money(24280).format()}'), findsOneWidget);
      await tester.tap(find.byKey(const Key('import_split_confirm')));
      await tester.pumpAndSettle();

      expect(find.text('Todas (6)'), findsOneWidget);
      expect(find.text('Parte 1 de 2 de ${const Money(48560).format()}'), findsOneWidget);
      expect(find.text('Parte 2 de 2 de ${const Money(48560).format()}'), findsOneWidget);

      await tester.tap(find.text('Juntar').first);
      await tester.pumpAndSettle();
      expect(find.text('Todas (5)'), findsOneWidget);
      expect(find.textContaining('Parte 1 de 2'), findsNothing);
    });
  });
}
