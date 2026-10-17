import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:omni_lar/core/di/service_locator.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/core/theme/theme_cubit.dart';
import 'package:omni_lar/features/auth/presentation/cubit/auth_cubit.dart';
import 'package:omni_lar/features/finance/domain/entities/cycle_funding_estimate.dart';
import 'package:omni_lar/features/finance/presentation/cubit/finance_cubit.dart';
import 'package:omni_lar/features/settings/presentation/pages/settings_page.dart';

void main() {
  setUpAll(() async {
    if (!sl.isRegistered<AuthCubit>()) {
      await initServiceLocator();
    }
  });

  Widget buildTestableWidget() {
    return MultiBlocProvider(
      providers: [
        BlocProvider<ThemeCubit>.value(value: sl<ThemeCubit>()),
        BlocProvider<AuthCubit>.value(value: sl<AuthCubit>()),
        BlocProvider<FinanceCubit>.value(value: sl<FinanceCubit>()),
      ],
      child: const MaterialApp(home: SettingsPage()),
    );
  }

  /// Os ajustes ficam em grupos: abre a página do grupo antes de procurar a opção.
  Future<void> openGroup(WidgetTester tester, String title) async {
    await tester.tap(find.text(title));
    await tester.pumpAndSettle();
  }

  testWidgets('SettingsPage renders all setting tiles properly', (
    tester,
  ) async {
    // Carrega dados iniciais do financeCubit
    await sl<FinanceCubit>().loadCycleData();

    await tester.pumpWidget(buildTestableWidget());
    await tester.pumpAndSettle();

    // Índice: os quatro grupos
    expect(find.text('Ajustes da Casa'), findsOneWidget);
    expect(find.text('Casa'), findsOneWidget);
    expect(find.text('Divisão das despesas'), findsOneWidget);
    expect(find.text('Pagamentos e contas'), findsOneWidget);
    expect(find.text('Aplicativo'), findsOneWidget);

    // Cada grupo mostra as opções dele
    await openGroup(tester, 'Casa');
    expect(find.text('Membros da Casa e Convites'), findsOneWidget);
    expect(find.text('Ciclo Financeiro'), findsOneWidget);
    expect(find.text('Chave Pix da Casa'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await openGroup(tester, 'Divisão das despesas');
    expect(find.text('Modelos de Rateio'), findsOneWidget);
    expect(find.text('Categorias de Gastos'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await openGroup(tester, 'Pagamentos e contas');
    expect(find.text('Cartões e Formas de Pagamento'), findsOneWidget);
    expect(find.text('Assinaturas & Contas Fixas'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await openGroup(tester, 'Aplicativo');
    expect(find.text('Assistente IA'), findsOneWidget);
  });

  testWidgets(
    'Can open Categorias de Gastos modal and view default categories',
    (tester) async {
      await sl<FinanceCubit>().loadCycleData();

      await tester.pumpWidget(buildTestableWidget());
      await tester.pumpAndSettle();

      // As categorias ficam à vista dentro do grupo, sem janela por cima
      await openGroup(tester, 'Divisão das despesas');

      expect(find.text('Categorias de Gastos'), findsOneWidget);
      expect(find.text('Supermercado'), findsOneWidget);
      expect(find.text('Moradia / Aluguel'), findsOneWidget);
      expect(find.text('Carro (Combustível)'), findsOneWidget);
      expect(find.text('Nova categoria'), findsOneWidget);

      // Tocar em uma categoria abre a edição dela
      await tester.ensureVisible(find.text('Supermercado'));
      await tester.tap(find.text('Supermercado'));
      await tester.pumpAndSettle();
      expect(find.text('Editar Categoria'), findsOneWidget);
    },
  );

  testWidgets('Can open Formas de Pagamento modal and view cards', (
    tester,
  ) async {
    await sl<FinanceCubit>().loadCycleData();

    await tester.pumpWidget(buildTestableWidget());
    await tester.pumpAndSettle();

    // Clica no tile de formas de pagamento
    await openGroup(tester, 'Pagamentos e contas');
    // As formas de pagamento ficam à vista no grupo, sem janela por cima
    expect(find.text('Cartões e Formas de Pagamento'), findsOneWidget);
    expect(find.text('Nubank Carlos'), findsOneWidget);
    expect(find.text('VR Marina (Vale Refeição)'), findsOneWidget);
    expect(find.text('Cadastrar Cartão ou VR'), findsOneWidget);
  });

  testWidgets(
    'Can open Assinaturas & Contas Fixas modal and view recurring expenses',
    (tester) async {
      await sl<FinanceCubit>().loadCycleData();

      await tester.pumpWidget(buildTestableWidget());
      await tester.pumpAndSettle();

      await openGroup(tester, 'Pagamentos e contas');
      final tile = find.text('Assinaturas & Contas Fixas');
      await tester.ensureVisible(tile);
      await tester.tap(tile);
      await tester.pumpAndSettle();

      expect(find.text('Comprometimento Mensal'), findsOneWidget);
      expect(find.text('Cadastrar Nova Recorrente'), findsOneWidget);
    },
  );

  testWidgets(
    'Can open Modelos de Rateio and see options including Aportes Fixos (Balde Comum)',
    (tester) async {
      await sl<FinanceCubit>().loadCycleData();

      await tester.pumpWidget(buildTestableWidget());
      await tester.pumpAndSettle();

      await openGroup(tester, 'Divisão das despesas');
      await tester.tap(find.text('Modelos de Rateio'));
      await tester.pumpAndSettle();

      expect(find.text('Porcentagem Personalizada'), findsOneWidget);
      expect(find.text('Aportes Fixos (Balde Comum)'), findsOneWidget);
      expect(find.text('Por Categoria de Gasto'), findsOneWidget);
      expect(find.text('Salvar Modelo de Rateio'), findsOneWidget);

      // Clica na opção Aportes Fixos (Balde Comum)
      await tester.tap(find.text('Aportes Fixos (Balde Comum)'));
      await tester.pumpAndSettle();

      expect(find.text('Balde Mensal Previsto:'), findsOneWidget);
      expect(find.text('Aporte de Carlos'), findsOneWidget);
      expect(find.text('Aporte de Marina'), findsOneWidget);
      expect(find.text(const Money(70000).format()), findsWidgets);
      expect(find.text(const Money(130000).format()), findsWidgets);
      expect(find.text(const Money(200000).format()), findsWidgets);
    },
  );

  testWidgets('Can open Ciclo Financeiro dialog', (tester) async {
    await sl<FinanceCubit>().loadCycleData();

    await tester.pumpWidget(buildTestableWidget());
    await tester.pumpAndSettle();

    await openGroup(tester, 'Casa');
    final tile = find.text('Ciclo Financeiro');
    await tester.ensureVisible(tile);
    await tester.tap(tile);
    await tester.pumpAndSettle();

    expect(find.text('Dia de Início do Ciclo'), findsOneWidget);
    expect(find.text('Todo dia 5'), findsOneWidget);
    expect(find.text('Salvar'), findsOneWidget);
  });

  testWidgets('Trocar o dia de início explica o ciclo de transição antes de salvar', (tester) async {
    await sl<FinanceCubit>().loadCycleData();

    await tester.pumpWidget(buildTestableWidget());
    await tester.pumpAndSettle();

    await openGroup(tester, 'Casa');
    final tile = find.text('Ciclo Financeiro');
    await tester.ensureVisible(tile);
    await tester.tap(tile);
    await tester.pumpAndSettle();

    // Mesmo dia: só o período, e salvar fica desligado
    expect(find.textContaining('Período do ciclo: dia 5'), findsOneWidget);
    FilledButton save() => tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Salvar'));
    expect(save().onPressed, isNull);

    await tester.tap(find.text('Dia 5 de cada mês'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dia 10 de cada mês').last);
    await tester.pumpAndSettle();

    expect(find.text('Todo dia 10'), findsOneWidget);
    expect(find.textContaining('O ciclo atual não muda'), findsOneWidget);
    expect(find.textContaining('os ciclos começam todo dia 10'), findsOneWidget);
    expect(save().onPressed, isNotNull);

    // Cancelar não grava
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(find.text('Dia de Início do Ciclo'), findsNothing);
  });

  testWidgets('Can open Editar Perfil da Conta modal and update profile', (
    tester,
  ) async {
    await sl<FinanceCubit>().loadCycleData();

    await tester.pumpWidget(buildTestableWidget());
    await tester.pumpAndSettle();

    // O cartão do topo abre o perfil; o lápis é o alvo visível dele
    final profileTile = find.byTooltip('Editar Perfil');
    await tester.ensureVisible(profileTile);
    await tester.tap(profileTile);
    await tester.pumpAndSettle();

    expect(find.text('Editar Perfil da Conta'), findsOneWidget);
    expect(find.text('Nome Completo'), findsOneWidget);
    // O e-mail de acesso agora é trocado em "Conta e segurança"
    expect(find.text('E-mail da Conta'), findsNothing);
    expect(find.text('Chave Pix (para receber acertos e Super Pix)'), findsOneWidget);

    final nameField = find.widgetWithText(TextFormField, 'Nome Completo');
    await tester.enterText(nameField, 'Carlos Eduardo Santos');
    await tester.pumpAndSettle();

    final pixField = find.widgetWithText(TextFormField, 'Chave Pix (para receber acertos e Super Pix)');
    await tester.enterText(pixField, 'carlos.pix@banco.com');
    await tester.pumpAndSettle();

    final saveButton = find.widgetWithText(FilledButton, 'Salvar');
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(find.text('Editar Perfil da Conta'), findsNothing);
    expect(find.text('Carlos Eduardo Santos'), findsOneWidget);
    expect(find.text('Pix: carlos.pix@banco.com'), findsWidgets);
  });

  testWidgets('Can open Chave Pix da Casa modal and update house pix key', (
    tester,
  ) async {
    await sl<FinanceCubit>().loadCycleData();

    await tester.pumpWidget(buildTestableWidget());
    await tester.pumpAndSettle();

    await openGroup(tester, 'Casa');
    final pixTile = find.text('Chave Pix da Casa');
    await tester.ensureVisible(pixTile);
    expect(pixTile, findsOneWidget);
    await tester.tap(pixTile);
    await tester.pumpAndSettle();

    expect(find.text('Chave Pix da Residência'), findsOneWidget);
    expect(find.text('Nome do Titular / Favorecido'), findsOneWidget);

    final keyField = find.widgetWithText(TextFormField, 'Chave Pix da Residência');
    await tester.enterText(keyField, 'caixa.nossacasa@nubank.com.br');
    await tester.pumpAndSettle();

    final holderField = find.widgetWithText(TextFormField, 'Nome do Titular / Favorecido');
    await tester.enterText(holderField, 'Fundo Conjunto Nossa Casa');
    await tester.pumpAndSettle();

    final saveButton = find.widgetWithText(FilledButton, 'Salvar');
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    // O grupo mostra a chave e o titular gravados
    expect(find.text('caixa.nossacasa@nubank.com.br'), findsOneWidget);
    expect(find.text('Fundo Conjunto Nossa Casa'), findsOneWidget);
  });

  testWidgets('No PC os grupos ficam à esquerda e o conteúdo ao lado, sem trocar de página', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await sl<FinanceCubit>().loadCycleData();

    await tester.pumpWidget(buildTestableWidget());
    await tester.pumpAndSettle();

    // O primeiro grupo já vem aberto ao lado do índice
    expect(find.text('Divisão das despesas'), findsOneWidget);
    expect(find.text('Membros da Casa e Convites'), findsOneWidget);
    expect(find.text('Modelos de Rateio'), findsNothing);

    await tester.tap(find.text('Divisão das despesas'));
    await tester.pumpAndSettle();

    // Mesmo lugar: o índice continua na tela e o conteúdo trocou
    expect(find.text('Pagamentos e contas'), findsOneWidget);
    expect(find.text('Modelos de Rateio'), findsOneWidget);
    expect(find.text('Categorias de Gastos'), findsOneWidget);
    expect(find.text('Membros da Casa e Convites'), findsNothing);
    expect(find.byType(BackButton), findsNothing);
  });

  testWidgets('Edição do rateio em andamento sobrevive a uma atualização da tela', (
    tester,
  ) async {
    final cubit = sl<FinanceCubit>();
    await cubit.loadCycleData();

    await tester.pumpWidget(buildTestableWidget());
    await tester.pumpAndSettle();
    await openGroup(tester, 'Divisão das despesas');

    // Escolhe outro modelo, sem salvar
    await tester.tap(find.text('Aportes Fixos (Balde Comum)'));
    await tester.pumpAndSettle();
    expect(find.text('Balde Mensal Previsto:'), findsOneWidget);

    // O cubit emite um estado novo que não muda moradores nem categorias
    cubit.updateFundingEstimateMode(FundingEstimateMode.comfortable);
    await tester.pumpAndSettle();

    // A escolha em andamento continua na tela
    expect(find.text('Balde Mensal Previsto:'), findsOneWidget);
    cubit.updateFundingEstimateMode(FundingEstimateMode.historicalAverage);
  });

  testWidgets('Casa mostra os moradores e só gera convite quando pedem', (tester) async {
    final cubit = sl<FinanceCubit>();
    await cubit.loadCycleData();

    await tester.pumpWidget(buildTestableWidget());
    await tester.pumpAndSettle();
    await openGroup(tester, 'Casa');

    // Moradores à vista, sem janela
    for (final m in cubit.state.members) {
      expect(find.text(m.name), findsOneWidget);
    }

    // Nenhum código existe até alguém pedir
    expect(find.text('Código de Convite:'), findsNothing);
    final generate = find.text('Gerar código de convite');
    await tester.ensureVisible(generate);
    await tester.tap(generate);
    await tester.pumpAndSettle();

    expect(find.text('Código de Convite:'), findsOneWidget);
    expect(find.text('Gerar outro código'), findsOneWidget);
    expect(find.byTooltip('Copiar Código'), findsOneWidget);
  });

  group('Busca nos ajustes', () {
    Future<void> search(WidgetTester tester, String text) async {
      await tester.enterText(find.widgetWithText(TextField, 'Buscar nos ajustes'), text);
      await tester.pumpAndSettle();
    }

    testWidgets('Acha uma opção sem acento e leva ao grupo dela', (tester) async {
      await sl<FinanceCubit>().loadCycleData();
      await tester.pumpWidget(buildTestableWidget());
      await tester.pumpAndSettle();

      await search(tester, 'cartao');

      // Os resultados tomam o lugar da lista de grupos
      expect(find.text('Cartões e Formas de Pagamento'), findsOneWidget);
      expect(find.text('Aplicativo'), findsNothing);

      await tester.tap(find.text('Cartões e Formas de Pagamento'));
      await tester.pumpAndSettle();

      // Abriu a página do grupo
      expect(find.text('Cadastrar Cartão ou VR'), findsOneWidget);
      expect(find.text('Assinaturas & Contas Fixas'), findsOneWidget);
    });

    testWidgets('Acha pelo sinônimo e pelo que a casa cadastrou', (tester) async {
      final cubit = sl<FinanceCubit>();
      await cubit.loadCycleData();
      await tester.pumpWidget(buildTestableWidget());
      await tester.pumpAndSettle();

      // "balde" não está no título, só nas palavras-chave do rateio
      await search(tester, 'balde');
      expect(find.text('Modelos de Rateio'), findsOneWidget);

      // Nome de uma forma de pagamento cadastrada
      await search(tester, 'nubank');
      expect(find.text('Nubank Carlos'), findsOneWidget);
      expect(find.textContaining('Forma de pagamento'), findsWidgets);
    });

    testWidgets('Categoria e forma de pagamento encontradas abrem direto a edição', (tester) async {
      final cubit = sl<FinanceCubit>();
      await cubit.loadCycleData();
      await tester.pumpWidget(buildTestableWidget());
      await tester.pumpAndSettle();

      final category = cubit.state.categories.first;
      await search(tester, category.name);
      await tester.tap(find.textContaining('Categoria •').first);
      await tester.pumpAndSettle();
      expect(find.text('Editar Categoria'), findsOneWidget);
      expect(find.widgetWithText(TextField, category.name), findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      // Fechando a edição, fica-se no grupo do item
      expect(find.text('Categorias de Gastos'), findsWidgets);
    });

    testWidgets('Sem resultado avisa, e limpar a busca devolve os grupos', (tester) async {
      await sl<FinanceCubit>().loadCycleData();
      await tester.pumpWidget(buildTestableWidget());
      await tester.pumpAndSettle();

      await search(tester, 'xyzxyz');
      expect(find.textContaining('Nada encontrado'), findsOneWidget);
      expect(find.text('Casa'), findsNothing);

      await tester.tap(find.byTooltip('Limpar busca'));
      await tester.pumpAndSettle();

      expect(find.text('Casa'), findsOneWidget);
      expect(find.text('Aplicativo'), findsOneWidget);
    });
  });

  testWidgets('Aplicativo: tema, chave de IA e auditoria ficam na página', (tester) async {
    await sl<FinanceCubit>().loadCycleData();
    final themeCubit = sl<ThemeCubit>();
    final before = themeCubit.state;
    addTearDown(() => themeCubit.setThemeMode(before));

    await tester.pumpWidget(buildTestableWidget());
    await tester.pumpAndSettle();
    await openGroup(tester, 'Aplicativo');

    // Os três blocos à vista, sem janela
    expect(find.text('Assistente IA'), findsOneWidget);
    expect(find.text('Sua Chave de API do Google AI Studio'), findsOneWidget);
    expect(find.text('Aparência & Tema'), findsOneWidget);
    expect(find.text('Auditoria e Histórico da Casa'), findsOneWidget);

    // Trocar o tema é um toque
    await tester.ensureVisible(find.text('Escuro'));
    await tester.tap(find.text('Escuro'));
    await tester.pumpAndSettle();
    expect(themeCubit.state, ThemeMode.dark);

    await tester.tap(find.text('Claro'));
    await tester.pumpAndSettle();
    expect(themeCubit.state, ThemeMode.light);
  });

  testWidgets('Importar fatura fica no menu de cada cartão, sem painel geral', (tester) async {
    await sl<FinanceCubit>().loadCycleData();

    await tester.pumpWidget(buildTestableWidget());
    await tester.pumpAndSettle();
    await openGroup(tester, 'Pagamentos e contas');

    // A importação geral fica na tela da Casa, junto do fechamento
    expect(find.text('Importar Fatura e Extratos'), findsNothing);

    final menu = find.byTooltip('Opções').first;
    await tester.ensureVisible(menu);
    await tester.tap(menu);
    await tester.pumpAndSettle();
    expect(find.textContaining('Importar'), findsWidgets);
  });
}
