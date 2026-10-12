import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:omni_lar/core/di/service_locator.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/features/finance/domain/entities/house_expense.dart';
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

  Widget buildPage(Widget child) {
    return BlocProvider<FinanceCubit>.value(
      value: sl<FinanceCubit>(),
      child: MaterialApp(
        home: Scaffold(body: child),
      ),
    );
  }

  group('Edição e Exclusão Segura de Despesas', () {
    testWidgets('AddExpensePage preenche dados existentes quando expenseToEdit for fornecido', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await sl<FinanceCubit>().loadCycleData();

      final existingExpense = HouseExpense(
        id: 'exp_edit_test',
        title: 'Internet Fibra 500MB',
        amount: const Money(12000), // R$ 120,00
        date: DateTime.now(),
        categoryId: 'cat_contas',
        paidByMemberId: 'user_1',
        paymentMethodId: 'pm_pix',
        splitRule: SplitRule.percentage({'user_1': 50.0, 'user_2': 50.0}),
        status: ExpenseStatus.pending,
      );

      await tester.pumpWidget(buildPage(AddExpensePage(expenseToEdit: existingExpense)));
      await tester.pumpAndSettle();

      // Verifica título da página
      expect(find.text('Editar Despesa'), findsOneWidget);

      // Verifica que o título da despesa foi preenchido no input
      expect(find.text('Internet Fibra 500MB'), findsOneWidget);

      // Faz scroll na ListView para revelar os botões de ação
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pumpAndSettle();

      // Clica em Salvar Alterações
      final saveBtn = find.text('Salvar Alterações');
      expect(saveBtn, findsOneWidget);
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      // Confirma que voltou e a despesa existe
      expect(find.text('Editar Despesa'), findsNothing);
    });

    testWidgets('ExpenseTimelineItem exibe opções de edição para despesa pendente e despesa paga', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await sl<FinanceCubit>().loadCycleData();

      // 1. Despesa pendente
      final pendingExpense = HouseExpense(
        id: 'exp_pending',
        title: 'Conta de Energia Elétrica',
        amount: const Money(25000),
        date: DateTime.now(),
        categoryId: 'cat_contas',
        paidByMemberId: 'user_1',
        paymentMethodId: 'pm_pix',
        splitRule: SplitRule.percentage({'user_1': 100.0}),
        status: ExpenseStatus.pending,
      );

      await tester.pumpWidget(buildPage(ExpenseTimelineItem(expense: pendingExpense)));
      await tester.pumpAndSettle();

      // Toca no card
      await tester.tap(find.text('Conta de Energia Elétrica'));
      await tester.pumpAndSettle();

      // Verifica que o modal abre com opção "Editar Dados"
      expect(find.text('Confirmar Pagamento'), findsWidgets);
      expect(find.text('Editar Dados'), findsOneWidget);
      expect(find.text('Excluir conta'), findsOneWidget);

      // Fecha o modal
      await tester.tap(find.byType(InkWell).first);
      await tester.pumpAndSettle();

      // 2. Despesa paga
      final paidExpense = HouseExpense(
        id: 'exp_paid',
        title: 'Feira Semanal Orgânica',
        amount: const Money(8500),
        date: DateTime.now(),
        categoryId: 'cat_supermercado',
        paidByMemberId: 'user_1',
        paymentMethodId: 'pm_pix',
        splitRule: SplitRule.percentage({'user_1': 100.0}),
        status: ExpenseStatus.paid,
      );

      await tester.pumpWidget(buildPage(ExpenseTimelineItem(expense: paidExpense)));
      await tester.pumpAndSettle();

      // Toca na despesa paga
      await tester.tap(find.text('Feira Semanal Orgânica'));
      await tester.pumpAndSettle();

      // Verifica que o modal de detalhes da despesa paga abre com "Editar Despesa" e "Reverter p/ Pendente"
      expect(find.text('Editar Despesa'), findsOneWidget);
      expect(find.text('Reverter p/ Pendente'), findsOneWidget);
      expect(find.text('Excluir conta'), findsOneWidget);
    });

    testWidgets('ExpenseTimelineItem exclui despesa via popup menu sem crash de rota', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await sl<FinanceCubit>().loadCycleData();

      final expenseToDelete = HouseExpense(
        id: 'exp_delete_menu_test',
        title: 'Despesa para Deletar',
        amount: const Money(5000),
        date: DateTime.now(),
        categoryId: 'cat_contas',
        paidByMemberId: 'user_1',
        paymentMethodId: 'pm_pix',
        splitRule: SplitRule.percentage({'user_1': 100.0}),
        status: ExpenseStatus.pending,
      );

      await tester.pumpWidget(buildPage(ExpenseTimelineItem(expense: expenseToDelete)));
      await tester.pumpAndSettle();

      // Abre o PopupMenuButton
      final popupFinder = find.byTooltip('Opções da despesa');
      expect(popupFinder, findsOneWidget);
      await tester.tap(popupFinder);
      await tester.pumpAndSettle();

      // Clica em Excluir Despesa no menu
      final deleteMenuOption = find.text('Excluir Despesa');
      expect(deleteMenuOption, findsOneWidget);
      await tester.tap(deleteMenuOption);
      await tester.pumpAndSettle();

      // Confirma que abriu o AlertDialog
      expect(find.text('Excluir Despesa'), findsOneWidget);
      expect(find.text('Tem certeza que deseja excluir "Despesa para Deletar"?'), findsOneWidget);

      // Clica no botão Excluir do diálogo
      final confirmBtn = find.widgetWithText(ElevatedButton, 'Excluir');
      await tester.tap(confirmBtn);
      await tester.pumpAndSettle();

      // Diálogo fechou sem erros e snackbar foi exibido
      expect(find.text('Excluir Despesa'), findsNothing);
      expect(find.text('Despesa "Despesa para Deletar" excluída.'), findsOneWidget);
    });
  });
}
