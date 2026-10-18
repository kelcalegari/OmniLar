import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/di/service_locator.dart';
import 'package:omni_lar/features/finance/data/datasources/mock_finance_datasource.dart';
import 'package:omni_lar/features/finance/data/repositories/finance_repository_impl.dart';
import 'package:omni_lar/features/finance/domain/entities/category.dart';
import 'package:omni_lar/features/finance/domain/entities/category_default_split.dart';
import 'package:omni_lar/features/finance/domain/entities/house_expense.dart';
import 'package:omni_lar/features/finance/domain/entities/house_member.dart';
import 'package:omni_lar/features/finance/domain/entities/house_settings.dart';
import 'package:omni_lar/features/finance/domain/entities/split_rule.dart';
import 'package:omni_lar/features/finance/domain/services/expense_launch_defaults.dart';
import 'package:omni_lar/features/finance/presentation/cubit/finance_cubit.dart';
import 'package:omni_lar/features/finance/presentation/pages/add_expense_page.dart';

/// Demonstração com padrões de divisão em duas categorias, guardando o lançado.
class _SplitDataSource extends MockFinanceDataSource {
  final List<HouseExpense> saved = [];

  @override
  Future<List<ExpenseCategory>> getCategories() async => [
        ...await super.getCategories(),
        const ExpenseCategory(
          id: 'cat_pet',
          name: 'Pet',
          icon: '',
          colorHex: '',
          defaultSplit: CategoryDefaultSplit.percentage({'member_carlos': 70.0, 'member_marina': 30.0}),
        ),
        const ExpenseCategory(
          id: 'cat_dela',
          name: 'Coisas da Marina',
          icon: '',
          colorHex: '',
          defaultSplit: CategoryDefaultSplit.singleResponsible('member_marina'),
        ),
      ];

  @override
  Future<void> addExpense(HouseExpense expense) async {
    saved.add(expense);
    await super.addExpense(expense);
  }
}

void main() {
  setUpAll(() async {
    if (!sl.isRegistered<FinanceCubit>()) {
      await initServiceLocator();
    }
  });

  group('CategoryDefaultSplit', () {
    test('lê e grava o formato da divisão de despesas', () {
      final percent = CategoryDefaultSplit.fromJson({
        'type': 'percentage',
        'percentages': {'ana': 60, 'beto': 40.0},
      });
      expect(percent, const CategoryDefaultSplit.percentage({'ana': 60.0, 'beto': 40.0}));
      expect(percent!.toJson(), {
        'type': 'percentage',
        'percentages': {'ana': 60.0, 'beto': 40.0},
      });
      final single = CategoryDefaultSplit.fromJson({'type': 'category_owner', 'member_id': 'ana'});
      expect(single, const CategoryDefaultSplit.singleResponsible('ana'));
      expect(single!.toJson(), {'type': 'category_owner', 'member_id': 'ana'});
    });

    test('formato inválido vale como sem padrão', () {
      expect(CategoryDefaultSplit.fromJson(null), isNull);
      expect(CategoryDefaultSplit.fromJson('lixo'), isNull);
      expect(CategoryDefaultSplit.fromJson({'type': 'fixed', 'fixedAmounts': {'a': 100}}), isNull);
      expect(CategoryDefaultSplit.fromJson({'type': 'percentage', 'percentages': {'a': 60, 'b': 30}}), isNull);
      expect(CategoryDefaultSplit.fromJson({'type': 'percentage', 'percentages': {'a': 130, 'b': -30}}), isNull);
      expect(CategoryDefaultSplit.fromJson({'type': 'category_owner'}), isNull);
    });

    test('ignora quem saiu da casa; sem ninguém sobrando, vale a divisão da casa', () {
      const split = CategoryDefaultSplit.percentage({'ana': 60.0, 'saiu': 40.0});
      const members = [HouseMember(id: 'ana', name: 'Ana'), HouseMember(id: 'beto', name: 'Beto')];
      expect(split.toRule(members), const SplitRule.percentage({'ana': 60.0}));
      expect(split.toRule(const [HouseMember(id: 'beto', name: 'Beto')]), isNull);
      expect(const CategoryDefaultSplit.singleResponsible('saiu').toRule(members), isNull);
    });
  });

  group('ExpenseLaunchDefaults.splitRule', () {
    const members = [
      HouseMember(id: 'ana', name: 'Ana', defaultSplitPercent: 50),
      HouseMember(id: 'beto', name: 'Beto', defaultSplitPercent: 50),
    ];

    test('categoria sem padrão segue a divisão da casa', () {
      final rule = ExpenseLaunchDefaults.splitRule(
        category: const ExpenseCategory(id: 'c', name: 'C', icon: '', colorHex: ''),
        members: members,
        paidByMemberId: 'ana',
      );
      expect(rule, const SplitRule.percentage({'ana': 50.0, 'beto': 50.0}));
    });

    test('categoria com padrão usa a divisão dela', () {
      final rule = ExpenseLaunchDefaults.splitRule(
        category: const ExpenseCategory(
          id: 'c',
          name: 'C',
          icon: '',
          colorHex: '',
          defaultSplit: CategoryDefaultSplit.percentage({'ana': 80.0, 'beto': 20.0}),
        ),
        members: members,
        paidByMemberId: 'ana',
      );
      expect(rule, const SplitRule.percentage({'ana': 80.0, 'beto': 20.0}));
    });

    test('o dono da categoria passa na frente do padrão', () {
      final rule = ExpenseLaunchDefaults.splitRule(
        category: const ExpenseCategory(
          id: 'c',
          name: 'C',
          icon: '',
          colorHex: '',
          ownerMemberId: 'beto',
          defaultSplit: CategoryDefaultSplit.singleResponsible('ana'),
        ),
        members: members,
        paidByMemberId: 'ana',
      );
      expect(rule, const SplitRule.singleResponsible('beto'));
    });

    test('morador que entrou com 0% fica fora; sem percentual nenhum, divisão igual', () {
      const joined = [
        HouseMember(id: 'ana', name: 'Ana', defaultSplitPercent: 60),
        HouseMember(id: 'beto', name: 'Beto', defaultSplitPercent: 40),
        HouseMember(id: 'cris', name: 'Cris', defaultSplitPercent: 0),
      ];
      expect(
        ExpenseLaunchDefaults.splitRule(category: null, members: joined, paidByMemberId: 'ana'),
        const SplitRule.percentage({'ana': 60.0, 'beto': 40.0, 'cris': 0.0}),
      );
      final none = [for (final m in joined) m.copyWith(defaultSplitPercent: 0)];
      expect(
        ExpenseLaunchDefaults.splitRule(category: null, members: none, paidByMemberId: 'ana').percentages,
        {for (final m in none) m.id: 100.0 / 3},
      );
    });
  });

  group('HouseSettings.newMemberSplitPolicy', () {
    test('lê o valor do banco; vazio ou desconhecido vale fatia igual', () {
      expect(HouseSettings.fromJson(const {}).newMemberSplitPolicy, NewMemberSplitPolicy.equal);
      expect(HouseSettings.fromJson(const {'new_member_split_policy': 'ask'}).newMemberSplitPolicy,
          NewMemberSplitPolicy.ask);
      expect(HouseSettings.fromJson(const {'new_member_split_policy': 'keep_current'}).newMemberSplitPolicy,
          NewMemberSplitPolicy.keepCurrent);
      expect(HouseSettings.fromJson(const {'new_member_split_policy': 'x'}).newMemberSplitPolicy,
          NewMemberSplitPolicy.equal);
      expect(HouseSettings.columns, contains('new_member_split_policy'));
      expect(HouseSettings.columnsBefore0097, isNot(contains('new_member_split_policy')));
    });

    test('Ajustes gravam a política na casa', () async {
      final cubit = FinanceCubit(FinanceRepositoryImpl(MockFinanceDataSource()));
      await cubit.loadCycleData();
      expect(await cubit.updateHouseSettings(newMemberSplitPolicy: NewMemberSplitPolicy.keepCurrent), isTrue);
      expect(cubit.state.houseSettings.newMemberSplitPolicy, NewMemberSplitPolicy.keepCurrent);
      await cubit.close();
    });
  });

  group('AddExpensePage: divisão padrão da categoria', () {
    late _SplitDataSource dataSource;

    Future<void> openForm(WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      dataSource = _SplitDataSource();
      final cubit = FinanceCubit(FinanceRepositoryImpl(dataSource));
      await cubit.loadCycleData();
      await tester.pumpWidget(
        BlocProvider<FinanceCubit>.value(value: cubit, child: const MaterialApp(home: AddExpensePage())),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '10000');
      await tester.enterText(find.widgetWithText(TextField, 'O que foi pago?'), 'Ração');
      await tester.pumpAndSettle();
    }

    Future<void> submit(WidgetTester tester) async {
      final button = find.text('Lançar Gasto da Casa');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
    }

    testWidgets('escolher a categoria sugere a divisão dela e grava', (tester) async {
      await openForm(tester);
      expect(find.text('Divisão da casa'), findsOneWidget);

      await tester.tap(find.text('Pet'));
      await tester.pumpAndSettle();
      expect(find.text('Divisão da categoria'), findsOneWidget);
      await submit(tester);

      expect(dataSource.saved.single.splitRule,
          const SplitRule.percentage({'member_carlos': 70.0, 'member_marina': 30.0}));
    });

    testWidgets('padrão de um responsável só vem marcado e some ao trocar para categoria sem padrão',
        (tester) async {
      await openForm(tester);
      await tester.tap(find.text('Coisas da Marina'));
      await tester.pumpAndSettle();
      expect(find.text('Um responsável'), findsOneWidget);
      expect(
        tester.widget<ChoiceChip>(find.byKey(const ValueKey('expense_split_single_member_marina'))).selected,
        isTrue,
      );

      // Categoria sem padrão: volta à divisão da casa
      await tester.tap(find.text('Lazer e Restaurantes'));
      await tester.pumpAndSettle();
      expect(find.text('Divisão da casa'), findsOneWidget);
      await submit(tester);
      expect(dataSource.saved.single.splitRule,
          const SplitRule.percentage({'member_carlos': 60.0, 'member_marina': 40.0}));
    });

    testWidgets('escolha manual da divisão vence o padrão da categoria', (tester) async {
      await openForm(tester);
      await tester.tap(find.byKey(const Key('expense_split_menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Um responsável').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('expense_split_single_member_carlos')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Pet'));
      await tester.pumpAndSettle();
      expect(find.text('Um responsável'), findsOneWidget);
      await submit(tester);

      expect(dataSource.saved.single.splitRule, const SplitRule.singleResponsible('member_carlos'));
    });

    testWidgets('voltar para "Divisão da casa" na mão tira a sugestão da categoria', (tester) async {
      await openForm(tester);
      await tester.tap(find.text('Pet'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('expense_split_menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Divisão da casa').last);
      await tester.pumpAndSettle();
      await submit(tester);

      expect(dataSource.saved.single.splitRule,
          const SplitRule.percentage({'member_carlos': 60.0, 'member_marina': 40.0}));
    });
  });
}
