import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:omni_lar/core/di/service_locator.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/features/finance/domain/entities/house_expense.dart';
import 'package:omni_lar/features/finance/domain/entities/house_expense_item.dart';
import 'package:omni_lar/features/finance/domain/entities/split_rule.dart';
import 'package:omni_lar/features/finance/presentation/cubit/finance_cubit.dart';
import 'package:omni_lar/features/finance/presentation/pages/add_expense_page.dart';
import 'package:omni_lar/features/finance/presentation/widgets/expense_timeline_item.dart';

void main() {
  setUpAll(() async {
    if (!sl.isRegistered<FinanceCubit>()) {
      await initServiceLocator();
    }
  });

  group('AddExpensePage - Segmentação de Boletos / Despesas Compostas', () {
    testWidgets('Exibe switch de desmembrar sub-itens e permite adicionar itens', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await sl<FinanceCubit>().loadCycleData();

      await tester.pumpWidget(
        BlocProvider<FinanceCubit>.value(
          value: sl<FinanceCubit>(),
          child: const MaterialApp(
            home: AddExpensePage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Switch visível
      final switchFinder = find.text('Desmembrar Sub-itens (Boleto Composto)');
      expect(switchFinder, findsOneWidget);

      // Clica para ativar
      await tester.tap(switchFinder);
      await tester.pumpAndSettle();

      // Opções expandidas
      expect(find.text('Preset Condomínio'), findsOneWidget);
      expect(find.text('Adicionar Sub-item'), findsOneWidget);
      expect(find.text('Sub-item #1'), findsOneWidget);
    });

    testWidgets('Exibe valores e títulos dos sub-itens legíveis ao editar despesa composta', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await sl<FinanceCubit>().loadCycleData();

      final compoundExpense = HouseExpense(
        id: 'exp_edit_test',
        title: 'Boleto Condomínio Teste',
        amount: const Money(19200),
        date: DateTime(2026, 10, 10),
        dueDate: DateTime(2026, 10, 10),
        categoryId: 'cat_moradia',
        paidByMemberId: 'member_carlos',
        paymentMethodId: 'pm_caixa',
        splitRule: const SplitRule.percentage({'member_carlos': 100}),
        status: ExpenseStatus.pending,
        items: const [
          HouseExpenseItem(
            id: 'it_1',
            expenseId: 'exp_edit_test',
            title: 'Outros',
            amount: Money(10000),
          ),
          HouseExpenseItem(
            id: 'it_2',
            expenseId: 'exp_edit_test',
            title: 'Marmita Cris',
            amount: Money(9200),
          ),
        ],
      );

      await tester.pumpWidget(
        BlocProvider<FinanceCubit>.value(
          value: sl<FinanceCubit>(),
          child: MaterialApp(
            home: AddExpensePage(expenseToEdit: compoundExpense),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verifica que está no modo de edição e com o banner 100% batendo
      expect(find.text('Editar Despesa'), findsOneWidget);
      expect(find.textContaining('100% batendo'), findsOneWidget);

      // Sub-itens exibem os títulos e os valores formatados nos campos
      expect(find.text('Outros'), findsOneWidget);
      expect(find.text('Marmita Cris'), findsOneWidget);
      expect(find.text(const Money(10000).format()), findsOneWidget);
      expect(find.text(const Money(9200).format()), findsOneWidget);
    });
  });

  group('ExpenseTimelineItem - Exibição de Despesas Compostas', () {
    testWidgets('Renderiza badge de sub-itens e lista discriminada no card', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await sl<FinanceCubit>().loadCycleData();

      final expense = HouseExpense(
        id: 'exp_condo_test',
        title: 'Boleto Condomínio Edifício Solar',
        amount: const Money(85000), // R$ 850,00
        date: DateTime(2026, 10, 10),
        dueDate: DateTime(2026, 10, 10),
        categoryId: 'cat_moradia',
        paidByMemberId: 'member_carlos',
        paymentMethodId: 'pm_caixa',
        splitRule: const SplitRule.percentage({'member_carlos': 60, 'member_marina': 40}),
        status: ExpenseStatus.pending,
        items: const [
          HouseExpenseItem(
            id: 'it_1',
            expenseId: 'exp_condo_test',
            title: 'Taxa Ordinária',
            amount: Money(50000),
          ),
          HouseExpenseItem(
            id: 'it_2',
            expenseId: 'exp_condo_test',
            title: 'Consumo Água',
            amount: Money(12000),
          ),
          HouseExpenseItem(
            id: 'it_3',
            expenseId: 'exp_condo_test',
            title: 'Gás Encanado',
            amount: Money(8000),
          ),
          HouseExpenseItem(
            id: 'it_4',
            expenseId: 'exp_condo_test',
            title: 'Obras Fachada',
            amount: Money(15000),
            responsibleMemberId: 'member_carlos',
          ),
        ],
      );

      await tester.pumpWidget(
        BlocProvider<FinanceCubit>.value(
          value: sl<FinanceCubit>(),
          child: MaterialApp(
            home: Scaffold(
              body: ExpenseTimelineItem(
                expense: expense,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verifica título, badge de 4 itens e itens discriminados
      expect(find.text('Boleto Condomínio Edifício Solar'), findsOneWidget);
      expect(find.text('4 itens'), findsOneWidget);
      expect(find.text('Sub-itens discriminados:'), findsOneWidget);
      expect(find.text('Taxa Ordinária'), findsOneWidget);
      expect(find.text('Consumo Água'), findsOneWidget);
      expect(find.text('Gás Encanado'), findsOneWidget);
      expect(find.text('Obras Fachada'), findsOneWidget);
      expect(find.text('100%'), findsOneWidget);

      // Clica para abrir modal de confirmação de pagamento
      await tester.tap(find.text('Boleto Condomínio Edifício Solar'));
      await tester.pumpAndSettle();

      // Modal aberto com discriminação
      expect(find.text('Confirmar Pagamento'), findsNWidgets(2)); // Título e Botão
      expect(find.text('Discriminação do Boleto:'), findsOneWidget);
    });
  });
}
