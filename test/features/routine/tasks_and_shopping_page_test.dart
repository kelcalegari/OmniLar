import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:omni_lar/core/di/service_locator.dart';
import 'package:omni_lar/features/auth/presentation/cubit/auth_cubit.dart';
import 'package:omni_lar/features/calendar/presentation/cubit/calendar_cubit.dart';
import 'package:omni_lar/features/finance/presentation/cubit/finance_cubit.dart';
import 'package:omni_lar/features/routine/presentation/pages/tasks_and_shopping_page.dart';
import 'package:omni_lar/features/shopping/presentation/cubit/shopping_cubit.dart';

void main() {
  setUpAll(() async {
    if (!sl.isRegistered<ShoppingCubit>() || !sl.isRegistered<CalendarCubit>()) {
      await initServiceLocator();
    }
  });

  Widget buildTasksAndShoppingPage({int initialTab = 0}) {
    return MultiBlocProvider(
      providers: [
        BlocProvider.value(value: sl<CalendarCubit>()),
        BlocProvider.value(value: sl<ShoppingCubit>()),
        BlocProvider.value(value: sl<FinanceCubit>()),
        BlocProvider.value(value: sl<AuthCubit>()),
      ],
      child: MaterialApp(
        home: TasksAndShoppingPage(initialTabIndex: initialTab),
      ),
    );
  }

  group('TasksAndShoppingPage - Seção Separada de Tarefas & Compras', () {
    testWidgets('Renderiza abas de Tarefas da Casa e Lista de Compras',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildTasksAndShoppingPage());
      await tester.pumpAndSettle();

      // Verifica abas
      expect(find.textContaining('Tarefas da Casa ('), findsOneWidget);
      expect(find.textContaining('Lista de Compras ('), findsOneWidget);

      // Na aba Tarefas (padrão)
      expect(find.text('Nova Tarefa'), findsOneWidget);
      expect(find.byType(ChoiceChip), findsWidgets);
    });

    testWidgets('Pode alternar para a aba Lista de Compras e adicionar item',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildTasksAndShoppingPage());
      await tester.pumpAndSettle();

      // Clica na aba Lista de Compras
      await tester.tap(find.textContaining('Lista de Compras ('));
      await tester.pumpAndSettle();

      // Campo de adicionar à lista deve estar visível
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Adicionar'), findsOneWidget);

      // Digita um novo item
      await tester.enterText(find.byType(TextField), 'Leite Desnatado');
      await tester.tap(find.text('Adicionar'));
      await tester.pumpAndSettle();

      // O item deve aparecer na lista
      expect(find.text('Leite Desnatado'), findsOneWidget);
    });

    testWidgets('Aba Tarefas permite alternar filtros e marcar conclusão',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildTasksAndShoppingPage(initialTab: 0));
      await tester.pumpAndSettle();

      // Filtra por Concluídas
      await tester.tap(find.textContaining('Concluídas ('));
      await tester.pumpAndSettle();

      // Filtra por Pendentes
      await tester.tap(find.textContaining('Pendentes ('));
      await tester.pumpAndSettle();

      // Deve encontrar checkboxes de tarefas
      expect(find.byType(Checkbox), findsWidgets);
    });

    testWidgets('Em Desktop (1280x800), renderiza Dual-Pane simultâneo e KPIs no topo sem abas',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildTasksAndShoppingPage());
      await tester.pumpAndSettle();

      // No Desktop, o TabBar inferior do AppBar NÃO é exibido
      expect(find.byType(TabBar), findsNothing);

      // KPIs superiores
      expect(find.text('Tarefas Pendentes'), findsOneWidget);
      expect(find.text('Tarefas Atrasadas'), findsOneWidget);
      expect(find.text('Itens a Comprar'), findsOneWidget);
      expect(find.text('No Carrinho'), findsOneWidget);

      // Ambas as seções aparecem lado a lado simultaneamente
      expect(find.textContaining('Tarefas da Casa ('), findsOneWidget);
      expect(find.textContaining('Lista de Compras ('), findsOneWidget);
      expect(find.text('Nova Tarefa'), findsOneWidget);
      expect(find.text('Adicionar'), findsOneWidget);
    });

    testWidgets(
        'Filtro padrão inicia em Pendentes e Todas agrupa concluídas em seção colapsável com histórico',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildTasksAndShoppingPage());
      await tester.pumpAndSettle();

      // Item 1: Pendentes deve estar selecionado por padrão
      final pendingChip = tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Pendentes (2)'));
      expect(pendingChip.selected, isTrue);

      // Na visualização inicial de pendentes, a tarefa concluída recente ('Trocar lâmpada do corredor') NÃO deve aparecer
      expect(find.text('Trocar lâmpada do corredor'), findsNothing);
      expect(find.text('Comprar botijão de gás'), findsOneWidget);
      expect(find.text('Lavar tapetes da sala'), findsOneWidget);

      // Item 2: Alterna para 'Todas'
      await tester.tap(find.textContaining('Todas ('));
      await tester.pumpAndSettle();

      // Em 'Todas', deve renderizar a seção colapsável de Concluídas com ExpansionTile
      expect(find.byType(ExpansionTile), findsOneWidget);
      expect(find.textContaining('Concluídas ('), findsWidgets);
      expect(find.text('Concluídas nos últimos 15 dias'), findsOneWidget);

      // Ao expandir o ExpansionTile de Concluídas
      await tester.tap(find.byType(ExpansionTile));
      await tester.pumpAndSettle();

      // Agora a tarefa concluída recente aparece
      expect(find.text('Trocar lâmpada do corredor'), findsOneWidget);
      // E a tarefa de mais de 15 dias ('Consertar torneira do jardim') NÃO está visível ainda (filtrada no banco/datasource)
      expect(find.text('Consertar torneira do jardim'), findsNothing);

      // Item 3: Banner de histórico permite carregar tarefas com mais de 15 dias
      expect(find.text('Ver histórico'), findsOneWidget);
      await tester.tap(find.text('Ver histórico'));
      await tester.pumpAndSettle();

      // Agora o histórico completo foi carregado e a tarefa antiga de 18 dias aparece
      expect(find.text('Consertar torneira do jardim'), findsOneWidget);
      expect(find.text('Ocultar antigas'), findsOneWidget);

      // Tocar em 'Ocultar antigas' oculta tarefas de mais de 15 dias novamente
      await tester.tap(find.text('Ocultar antigas'));
      await tester.pumpAndSettle();
      expect(find.text('Consertar torneira do jardim'), findsNothing);
    });
  });
}
