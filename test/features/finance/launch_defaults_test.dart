import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/di/service_locator.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/features/finance/data/datasources/mock_finance_datasource.dart';
import 'package:omni_lar/features/finance/data/offline/house_expense_offline_codec.dart';
import 'package:omni_lar/features/finance/data/repositories/finance_repository_impl.dart';
import 'package:omni_lar/features/finance/data/repositories/member_settings_repositories.dart';
import 'package:omni_lar/features/finance/domain/entities/category.dart';
import 'package:omni_lar/features/finance/domain/entities/house_expense.dart';
import 'package:omni_lar/features/finance/domain/entities/house_member.dart';
import 'package:omni_lar/features/finance/domain/entities/member_settings.dart';
import 'package:omni_lar/features/finance/domain/entities/payment_method.dart';
import 'package:omni_lar/features/finance/domain/entities/split_rule.dart';
import 'package:omni_lar/features/finance/domain/services/cycle_funding_estimator.dart';
import 'package:omni_lar/features/finance/domain/services/expense_launch_defaults.dart';
import 'package:omni_lar/features/finance/presentation/cubit/finance_cubit.dart';
import 'package:omni_lar/features/finance/presentation/pages/add_expense_page.dart';

/// Demonstração com Marina antes de Carlos (o logado), guardando o que foi lançado.
class _RecordingDataSource extends MockFinanceDataSource {
  final List<HouseExpense> saved = [];

  @override
  Future<List<HouseMember>> getMembers() async => (await super.getMembers()).reversed.toList();

  @override
  Future<List<PaymentMethod>> getPaymentMethods() async => [
        ...await super.getPaymentMethods(),
        const PaymentMethod(
          id: 'pm_pix_carlos',
          name: 'Pix Carlos',
          type: PaymentMethodType.pix,
          ownerMemberId: 'member_carlos',
        ),
      ];

  @override
  Future<void> addExpense(HouseExpense expense) async {
    saved.add(expense);
    await super.addExpense(expense);
  }
}

HouseExpense _expense(
  String id, {
  required String createdBy,
  required String paymentMethodId,
  required String categoryId,
  required DateTime date,
}) =>
    HouseExpense(
      id: id,
      title: id,
      amount: const Money(1000),
      date: date,
      categoryId: categoryId,
      paidByMemberId: createdBy,
      paymentMethodId: paymentMethodId,
      splitRule: const SplitRule.percentage(null),
      createdBy: createdBy,
    );

void main() {
  setUpAll(() async {
    if (!sl.isRegistered<FinanceCubit>()) {
      await initServiceLocator();
    }
  });

  const members = [
    HouseMember(id: 'ana', name: 'Ana', defaultSplitPercent: 50),
    HouseMember(id: 'beto', name: 'Beto', defaultSplitPercent: 50),
  ];
  const methods = [
    PaymentMethod(id: 'caixa', name: 'Caixa', type: PaymentMethodType.account),
    PaymentMethod(id: 'pix_beto', name: 'Pix Beto', type: PaymentMethodType.pix, ownerMemberId: 'beto'),
    PaymentMethod(id: 'vr_beto', name: 'VR Beto', type: PaymentMethodType.vr, ownerMemberId: 'beto'),
    PaymentMethod(id: 'pix_ana', name: 'Pix Ana', type: PaymentMethodType.pix, ownerMemberId: 'ana'),
  ];
  const categories = [
    ExpenseCategory(id: 'mercado', name: 'Mercado', icon: '', colorHex: ''),
    ExpenseCategory(id: 'lazer', name: 'Lazer', icon: '', colorHex: ''),
    ExpenseCategory(id: 'casa', name: 'Casa', icon: '', colorHex: ''),
  ];
  final day = DateTime(2026, 10, 10);
  final history = [
    _expense('e1', createdBy: 'beto', paymentMethodId: 'pix_beto', categoryId: 'lazer', date: day),
    _expense('e2', createdBy: 'beto', paymentMethodId: 'vr_beto', categoryId: 'mercado',
        date: day.add(const Duration(days: 2))),
    _expense('e3', createdBy: 'beto', paymentMethodId: 'pix_beto', categoryId: 'lazer',
        date: day.add(const Duration(days: 1))),
    // De outro morador: não conta para o Beto
    _expense('e4', createdBy: 'ana', paymentMethodId: 'pix_ana', categoryId: 'casa',
        date: day.add(const Duration(days: 5))),
  ];

  group('ExpenseLaunchDefaults.formDefaults', () {
    test('quem lança paga, com a última forma que usou e a categoria que mais usa', () {
      final d = ExpenseLaunchDefaults.formDefaults(
        currentUserId: 'beto',
        members: members,
        paymentMethods: methods,
        categories: categories,
        expenses: history,
      );
      expect(d.payerId, 'beto');
      expect(d.paymentMethodId, 'vr_beto'); // a mais recente dele
      expect(d.categoryId, 'lazer'); // duas vezes contra uma
    });

    test('sem histórico: só quem paga; forma e categoria ficam para o formulário', () {
      final d = ExpenseLaunchDefaults.formDefaults(
        currentUserId: 'beto',
        members: members,
        paymentMethods: methods,
        categories: categories,
        expenses: const [],
      );
      expect(d.payerId, 'beto');
      expect(d.paymentMethodId, isNull);
      expect(d.categoryId, isNull);
    });

    test('empate na categoria: vale a mais recente; repetida no histórico conta uma vez', () {
      final d = ExpenseLaunchDefaults.formDefaults(
        currentUserId: 'beto',
        members: members,
        paymentMethods: methods,
        categories: categories,
        expenses: [...history.take(2), history.first],
      );
      expect(d.categoryId, 'mercado');
    });

    test('quem não é morador da casa não vira pagador', () {
      final d = ExpenseLaunchDefaults.formDefaults(
        currentUserId: 'visita',
        members: members,
        paymentMethods: methods,
        categories: categories,
        expenses: history,
      );
      expect(d.payerId, isNull);
      expect(d.paymentMethodId, isNull);
    });

    test('padrões dos Ajustes passam na frente do automático', () {
      final d = ExpenseLaunchDefaults.formDefaults(
        currentUserId: 'beto',
        members: members,
        paymentMethods: methods,
        categories: categories,
        expenses: history,
        settings: const MemberSettings().withLaunchDefaults(
          payer: null,
          paymentMethodId: 'pix_beto',
          categoryId: 'casa',
        ),
      );
      expect(d.paymentMethodId, 'pix_beto');
      expect(d.categoryId, 'casa');
    });

    test('Caixa da casa nos padrões: a conta da casa, com quem lança como pagador', () {
      final d = ExpenseLaunchDefaults.formDefaults(
        currentUserId: 'beto',
        members: members,
        paymentMethods: methods,
        categories: categories,
        expenses: history,
        settings: const MemberSettings({'launch_payer': 'house', 'launch_payment_method_id': 'pix_beto'}),
      );
      expect(d.paymentMethodId, 'caixa');
      expect(d.payerId, 'beto');
    });

    test('forma ou categoria apagada depois de escolhida volta ao automático', () {
      final d = ExpenseLaunchDefaults.formDefaults(
        currentUserId: 'beto',
        members: members,
        paymentMethods: methods,
        categories: categories,
        expenses: history,
        settings: const MemberSettings({'launch_payment_method_id': 'apagada', 'launch_category_id': 'sumiu'}),
      );
      expect(d.paymentMethodId, 'vr_beto');
      expect(d.categoryId, 'lazer');
    });
  });

  group('MemberSettings', () {
    test('guarda as chaves que não conhece e tira as que voltam ao automático', () {
      final settings = MemberSettings.fromJson({'notify_bills': true, 'launch_category_id': 'x'});
      final next = settings.withLaunchDefaults(payer: LaunchPayer.house, paymentMethodId: null, categoryId: null);
      expect(next.toJson(), {'notify_bills': true, 'launch_payer': 'house'});
      expect(next.launchPayer, LaunchPayer.house);
      expect(MemberSettings.fromJson('lixo'), const MemberSettings());
    });

    test('quem lançou vai e volta da fila offline', () {
      final e = history.first;
      expect(houseExpenseFromJson(houseExpenseToJson(e)).createdBy, 'beto');
    });
  });

  group('FinanceCubit', () {
    test('carrega e grava os ajustes do morador junto com o ciclo', () async {
      final repo = InMemoryMemberSettingsRepository(const MemberSettings({'launch_payer': 'house'}));
      final cubit = FinanceCubit(
        FinanceRepositoryImpl(MockFinanceDataSource()),
        const CycleFundingEstimator(),
        null,
        null,
        repo,
      );
      await cubit.loadCycleData();
      expect(cubit.state.memberSettings.launchPayer, LaunchPayer.house);
      expect(cubit.launchHistory, containsAll(cubit.state.expenses));

      final next = cubit.state.memberSettings.withLaunchDefaults(
        payer: null,
        paymentMethodId: null,
        categoryId: 'cat_lazer',
      );
      expect(await cubit.updateMemberSettings(next), isTrue);
      expect(cubit.state.memberSettings.launchCategoryId, 'cat_lazer');
      expect((await repo.load()).launchCategoryId, 'cat_lazer');
      await cubit.close();
    });
  });

  group('AddExpensePage', () {
    late _RecordingDataSource dataSource;

    Future<FinanceCubit> openForm(
      WidgetTester tester, {
      MemberSettings settings = const MemberSettings(),
      List<HouseExpense> before = const [],
    }) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      dataSource = _RecordingDataSource();
      for (final e in before) {
        await dataSource.addExpense(e);
      }
      dataSource.saved.clear();
      final cubit = FinanceCubit(
        FinanceRepositoryImpl(dataSource),
        const CycleFundingEstimator(),
        null,
        null,
        InMemoryMemberSettingsRepository(settings),
      );
      await cubit.loadCycleData();
      await tester.pumpWidget(
        BlocProvider<FinanceCubit>.value(
          value: cubit,
          child: const MaterialApp(home: AddExpensePage()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '5000');
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'O que foi pago?'), 'Feira');
      await tester.pumpAndSettle();
      return cubit;
    }

    Future<void> submit(WidgetTester tester) async {
      final button = find.text('Lançar Gasto da Casa');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
    }

    Future<void> chooseSplit(WidgetTester tester, String label) async {
      await tester.tap(find.byKey(const Key('expense_split_menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
    }

    bool chipSelected(WidgetTester tester, String label) => tester
        .widget<ChoiceChip>(find.ancestor(of: find.text(label), matching: find.byType(ChoiceChip)))
        .selected;

    testWidgets('quem pagou é o logado, não o primeiro da lista, e a despesa guarda quem lançou',
        (tester) async {
      await openForm(tester);
      // Marina vem primeiro na lista; o logado é o Carlos
      await submit(tester);

      final saved = dataSource.saved.single;
      expect(saved.paidByMemberId, 'member_carlos');
      expect(saved.createdBy, 'member_carlos');
      expect(saved.splitRule, const SplitRule.percentage({'member_marina': 40.0, 'member_carlos': 60.0}));
    });

    testWidgets('abre com a última forma de pagamento e a categoria que o morador mais usa',
        (tester) async {
      final now = DateTime.now();
      await openForm(tester, before: [
        _expense('a', createdBy: 'member_carlos', paymentMethodId: 'pm_vr_marina', categoryId: 'cat_lazer',
            date: now.subtract(const Duration(minutes: 2))),
        _expense('b', createdBy: 'member_carlos', paymentMethodId: 'pm_caixa', categoryId: 'cat_lazer',
            date: now.subtract(const Duration(minutes: 1))),
        _expense('c', createdBy: 'member_carlos', paymentMethodId: 'pm_pix_carlos', categoryId: 'cat_contas',
            date: now),
        // Lançada pela Marina: não muda o padrão do Carlos
        _expense('d', createdBy: 'member_marina', paymentMethodId: 'pm_card_marina', categoryId: 'cat_moradia',
            date: now.add(const Duration(minutes: 1))),
      ]);

      expect(find.text('Pix Carlos'), findsOneWidget);
      expect(chipSelected(tester, 'Lazer e Restaurantes'), isTrue);
      await submit(tester);

      final saved = dataSource.saved.single;
      expect(saved.paymentMethodId, 'pm_pix_carlos');
      expect(saved.categoryId, 'cat_lazer');
      expect(saved.paidByMemberId, 'member_carlos');
    });

    testWidgets('padrões dos Ajustes: Caixa da casa e categoria fixa', (tester) async {
      await openForm(
        tester,
        settings: const MemberSettings({'launch_payer': 'house', 'launch_category_id': 'cat_contas'}),
      );

      expect(find.text('Conta Conjunta (Caixa da Casa)'), findsOneWidget);
      expect(chipSelected(tester, 'Contas (Luz, Água, Net)'), isTrue);
      await submit(tester);

      final saved = dataSource.saved.single;
      expect(saved.paymentMethodId, 'pm_caixa');
      expect(saved.categoryId, 'cat_contas');
      expect(saved.paidOutOfPocket, isFalse);
    });

    testWidgets('divisão por valores fixos: começa pela divisão da casa e grava os valores', (tester) async {
      await openForm(tester);
      await chooseSplit(tester, 'Valores fixos');

      // 60/40 de R$ 50,00
      expect(find.text('Os valores fecham o total ✅'), findsOneWidget);
      Finder field(String memberId) => find.descendant(
            of: find.byKey(ValueKey('expense_split_fixed_$memberId')),
            matching: find.byType(EditableText),
          );
      await tester.enterText(field('member_carlos'), '1000');
      await tester.pumpAndSettle();
      expect(find.text('Faltam ${const Money(2000).format()} para fechar o total'), findsOneWidget);

      // Não fecha o total: não grava
      await submit(tester);
      expect(dataSource.saved, isEmpty);
      expect(find.textContaining('A soma dos valores fixos'), findsOneWidget);

      await tester.enterText(field('member_marina'), '4000');
      await tester.pumpAndSettle();
      await submit(tester);

      final rule = dataSource.saved.single.splitRule;
      expect(rule.type, SplitType.fixed);
      expect(rule.fixedAmounts, {'member_carlos': const Money(1000), 'member_marina': const Money(4000)});
    });

    testWidgets('divisão com um responsável só: grava quem foi escolhido', (tester) async {
      await openForm(tester);
      await chooseSplit(tester, 'Um responsável');

      // Começa por quem pagou
      expect(
        tester.widget<ChoiceChip>(find.byKey(const ValueKey('expense_split_single_member_carlos'))).selected,
        isTrue,
      );
      await tester.tap(find.byKey(const ValueKey('expense_split_single_member_marina')));
      await tester.pumpAndSettle();
      await submit(tester);

      final saved = dataSource.saved.single;
      expect(saved.splitRule, const SplitRule.singleResponsible('member_marina'));
      expect(saved.paidByMemberId, 'member_carlos');
    });

    testWidgets('categoria com dono: a escolha da divisão some e vale o dono', (tester) async {
      await openForm(tester);
      expect(find.byKey(const Key('expense_split_menu')), findsOneWidget);
      await chooseSplit(tester, 'Um responsável');

      await tester.tap(find.text('Carro (Combustível)'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('expense_split_menu')), findsNothing);
      await submit(tester);

      expect(dataSource.saved.single.splitRule, const SplitRule.singleResponsible('member_carlos'));
    });
  });
}
