import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/di/service_locator.dart';
import 'package:omni_lar/features/finance/data/datasources/mock_finance_datasource.dart';
import 'package:omni_lar/features/finance/data/repositories/finance_repository_impl.dart';
import 'package:omni_lar/features/finance/data/repositories/member_settings_repositories.dart';
import 'package:omni_lar/features/finance/domain/entities/member_settings.dart';
import 'package:omni_lar/features/finance/domain/services/cycle_funding_estimator.dart';
import 'package:omni_lar/features/finance/presentation/cubit/finance_cubit.dart';
import 'package:omni_lar/features/finance/presentation/pages/add_expense_page.dart';

void main() {
  setUpAll(() async {
    if (!sl.isRegistered<FinanceCubit>()) {
      await initServiceLocator();
    }
  });

  Future<void> openForm(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final cubit = FinanceCubit(
      FinanceRepositoryImpl(MockFinanceDataSource()),
      const CycleFundingEstimator(),
      null,
      null,
      InMemoryMemberSettingsRepository(const MemberSettings()),
    );
    await cubit.loadCycleData();
    await tester.pumpWidget(
      BlocProvider<FinanceCubit>.value(
        value: cubit,
        child: const MaterialApp(home: AddExpensePage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> chooseMethod(WidgetTester tester, String name) async {
    final field = find.byIcon(Icons.credit_card_rounded).first;
    await tester.ensureVisible(field);
    await tester.tap(field);
    await tester.pumpAndSettle();
    await tester.tap(find.text(name).last);
    await tester.pumpAndSettle();
  }

  bool chipSelected(WidgetTester tester, Key key) => tester.widget<ChoiceChip>(find.byKey(key)).selected;

  testWidgets('fora do cartão, quem pagou mostra os moradores e a divisão ao lado', (tester) async {
    await openForm(tester);
    await chooseMethod(tester, 'Conta Conjunta (Caixa da Casa)');

    expect(find.text('Quem pagou?'), findsOneWidget);
    expect(find.byKey(const Key('expense_card_payer_note')), findsNothing);
    expect(find.byKey(const Key('expense_card_debtor_house')), findsNothing);
    expect(find.byKey(const Key('expense_split_menu')), findsOneWidget);
  });

  testWidgets('no cartão, quem pagou vira aviso e "De quem é a compra" vem como Da Casa, com a divisão',
      (tester) async {
    await openForm(tester);
    await chooseMethod(tester, 'Nubank Carlos');

    expect(find.byKey(const Key('expense_card_payer_note')), findsOneWidget);
    expect(find.textContaining('definido no pagamento da fatura'), findsOneWidget);
    // De quem é a compra aparece mesmo sem parcelar, já marcada como da Casa
    expect(find.byKey(const Key('expense_card_debtor_house')), findsOneWidget);
    expect(chipSelected(tester, const Key('expense_card_debtor_house')), isTrue);
    // O dono do cartão não deve para ele mesmo
    expect(find.byKey(const Key('expense_card_debtor_member_carlos')), findsNothing);
    // A divisão fica junto da escolha "Da Casa", uma vez só
    expect(find.byKey(const Key('expense_split_menu')), findsOneWidget);
    expect(find.text('Lançar Gasto da Casa'), findsOneWidget);
  });

  testWidgets('compra de um morador esconde a divisão da casa e vira empréstimo', (tester) async {
    await openForm(tester);
    await chooseMethod(tester, 'Nubank Carlos');

    final marina = find.byKey(const Key('expense_card_debtor_member_marina'));
    await tester.ensureVisible(marina);
    await tester.tap(marina);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('expense_split_menu')), findsNothing);
    expect(find.textContaining('Não entra nas despesas da Casa'), findsOneWidget);
    expect(find.text('Lançar como Empréstimo'), findsOneWidget);

    await tester.tap(find.byKey(const Key('expense_card_debtor_house')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('expense_split_menu')), findsOneWidget);
  });
}
