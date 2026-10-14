import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/di/service_locator.dart';
import 'package:omni_lar/features/auth/presentation/cubit/auth_cubit.dart';
import 'package:omni_lar/features/finance/domain/repositories/finance_repository.dart';
import 'package:omni_lar/features/finance/presentation/cubit/finance_cubit.dart';
import 'package:omni_lar/features/p2p/presentation/cubit/p2p_cubit.dart';
import 'package:omni_lar/features/reconciliation/presentation/pages/import_page.dart';

void main() {
  setUpAll(() async {
    if (!sl.isRegistered<AuthCubit>()) {
      await initServiceLocator();
    }
    await sl<AuthCubit>().signInDemo(memberId: 'member_carlos');
    await sl<FinanceCubit>().loadCycleData();
  });

  Widget buildPage({String? sourceId}) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<FinanceCubit>.value(value: sl<FinanceCubit>()),
        BlocProvider<P2PCubit>.value(value: sl<P2PCubit>()),
      ],
      child: MaterialApp(home: ImportPage(initialSourceId: sourceId)),
    );
  }

  testWidgets('sem origem escolhida não dá para enviar arquivo', (tester) async {
    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();

    expect(find.text('1. De onde é o arquivo?'), findsOneWidget);
    final pick = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Escolher arquivo'),
    );
    expect(pick.onPressed, isNull);
    expect(find.byKey(const Key('import_confirm')), findsNothing);
  });

  testWidgets('fatura de exemplo: revisa, separa e grava despesas e empréstimo', (tester) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repository = sl<FinanceRepository>();
    final cycle = sl<FinanceCubit>().cycleSchedule;
    Future<int> importedCount() async {
      final ids = <String>{};
      final now = DateTime.now();
      for (final date in [now, DateTime(now.year, now.month + 1, now.day), DateTime(now.year, now.month + 2, now.day)]) {
        for (final expense in await repository.getExpensesForCycle(cycle.cycleFor(date))) {
          if (expense.notes?.startsWith('Importado de Nubank Carlos') == true) ids.add(expense.id);
        }
      }
      return ids.length;
    }

    final loansBefore = (await tester.runAsync(() async {
      await sl<P2PCubit>().loadLoans();
      return sl<P2PCubit>().state.allLoans.length;
    }))!;

    await tester.pumpWidget(buildPage(sourceId: 'pm_card_carlos'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Usar fatura de exemplo'));
    await tester.pumpAndSettle();

    // Cartão escolhido: o vencimento da fatura já vem sugerido
    expect(find.textContaining('Vence em'), findsOneWidget);
    expect(find.text('Pao de Acucar'), findsOneWidget);
    expect(find.text('Todas (5)'), findsOneWidget);

    // Conforme o dia, uma despesa da casa demo tem o mesmo valor de uma linha
    // do exemplo: aqui todas são compras novas
    while (find.text('É a mesma').evaluate().isNotEmpty) {
      final row = find.ancestor(of: find.text('É a mesma').first, matching: find.byType(Wrap)).first;
      await tester.tap(find.descendant(of: row, matching: find.text('São diferentes')));
      await tester.pumpAndSettle();
    }

    // A linha da Farm passa a ser dívida da Marina (a única outra moradora)
    final farmRow = find.ancestor(of: find.text('Farm Rio'), matching: find.byType(Padding)).first;
    await tester.tap(find.descendant(of: farmRow, matching: find.text('Casa')));
    await tester.pumpAndSettle();
    // O seletor traz cada morador pelo nome, e não um "outro morador" genérico
    expect(find.text('Outro morador deve'), findsNothing);
    await tester.tap(find.text('Marina deve').last);
    await tester.pumpAndSettle();
    expect(find.text('Marina deve'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('import_confirm')));
    await tester.tap(find.byKey(const Key('import_confirm')));
    await tester.pumpAndSettle();

    expect(find.textContaining('fatura_exemplo.csv importado'), findsOneWidget);
    expect(find.textContaining('4 despesas lançadas'), findsOneWidget);
    expect(find.textContaining('1 empréstimo criado'), findsOneWidget);

    expect(await tester.runAsync(importedCount), 4);
    expect(sl<P2PCubit>().state.allLoans.length, loansBefore + 1);

    // A importação entra no histórico
    expect(find.text('Importações anteriores'), findsOneWidget);
    expect(find.textContaining('5 lançamentos criados'), findsOneWidget);

    // Importar o mesmo arquivo de novo não duplica: todas as linhas já vieram
    await tester.tap(find.text('Usar fatura de exemplo'));
    await tester.pumpAndSettle();
    expect(find.text('Já importadas (5)'), findsOneWidget);
    expect(find.text('Novas (0)'), findsOneWidget);

    // Desfazer exclui o que a importação criou
    await tester.ensureVisible(find.text('Desfazer'));
    await tester.tap(find.text('Desfazer'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Desfazer'));
    await tester.pumpAndSettle();

    expect(await tester.runAsync(importedCount), 0);
    expect(sl<P2PCubit>().state.allLoans.length, loansBefore);
    expect(find.textContaining('desfeita'), findsWidgets);
    // Com a importação desfeita, as linhas do arquivo aberto voltam a ser novas
    expect(find.text('Novas (5)'), findsOneWidget);
  });

  testWidgets('edição em lote: marca todas as linhas e muda o destino de uma vez', (tester) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(buildPage(sourceId: 'pm_card_carlos'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Usar fatura de exemplo'));
    await tester.pumpAndSettle();
    while (find.text('É a mesma').evaluate().isNotEmpty) {
      final row = find.ancestor(of: find.text('É a mesma').first, matching: find.byType(Wrap)).first;
      await tester.tap(find.descendant(of: row, matching: find.text('São diferentes')));
      await tester.pumpAndSettle();
    }
    expect(find.text('Novas (5)'), findsOneWidget);

    await tester.tap(find.text('Selecionar as 5 linhas para editar juntas'));
    await tester.pumpAndSettle();
    expect(find.text('5 linhas marcadas'), findsOneWidget);

    await tester.tap(find.byKey(const Key('import_bulk_destination')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ignorar').last);
    await tester.pumpAndSettle();

    expect(find.text('Novas (0)'), findsOneWidget);
    expect(find.text('Ignoradas (5)'), findsOneWidget);
  });

  testWidgets('o que foi decidido em uma importação vem pronto na seguinte', (tester) async {
    tester.view.physicalSize = const Size(1200, 3400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    Future<void> loadSample() async {
      await tester.tap(find.text('Usar fatura de exemplo'));
      await tester.pumpAndSettle();
      while (find.text('É a mesma').evaluate().isNotEmpty) {
        final row = find.ancestor(of: find.text('É a mesma').first, matching: find.byType(Wrap)).first;
        await tester.tap(find.descendant(of: row, matching: find.text('São diferentes')));
        await tester.pumpAndSettle();
      }
    }

    // Cartão da Marina: sem regras nem importações dos outros testes
    await tester.pumpWidget(buildPage(sourceId: 'pm_card_marina'));
    await tester.pumpAndSettle();
    await loadSample();

    // Steam é gasto pessoal de quem paga
    final steamRow = find.ancestor(of: find.text('Steam Games'), matching: find.byType(Padding)).first;
    await tester.tap(find.descendant(of: steamRow, matching: find.text('Casa')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pessoal de Marina').last);
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('import_confirm')));
    await tester.tap(find.byKey(const Key('import_confirm')));
    await tester.pumpAndSettle();
    expect(find.textContaining('4 despesas lançadas'), findsOneWidget);
    expect(find.textContaining('Regras aprendidas'), findsOneWidget);

    // Desfaz para o mesmo arquivo voltar a ser novo, e abre de novo
    await tester.ensureVisible(find.text('Desfazer').first);
    await tester.tap(find.text('Desfazer').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Desfazer'));
    await tester.pumpAndSettle();
    await loadSample();

    expect(find.text('Novas (5)'), findsOneWidget);
    final steamAgain = find.ancestor(of: find.text('Steam Games'), matching: find.byType(Padding)).first;
    expect(find.descendant(of: steamAgain, matching: find.text('Pessoal de Marina')), findsOneWidget);
  });
}
