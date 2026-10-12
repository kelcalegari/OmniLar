import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:omni_lar/core/di/service_locator.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/core/theme/theme_cubit.dart';
import 'package:omni_lar/features/auth/presentation/cubit/auth_cubit.dart';
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

  testWidgets('SettingsPage renders all setting tiles properly', (
    tester,
  ) async {
    // Carrega dados iniciais do financeCubit
    await sl<FinanceCubit>().loadCycleData();

    await tester.pumpWidget(buildTestableWidget());
    await tester.pumpAndSettle();

    expect(find.text('Ajustes da Casa'), findsOneWidget);
    expect(find.text('Membros da Casa e Convites'), findsOneWidget);
    expect(find.text('Categorias de Gastos'), findsOneWidget);
    expect(find.text('Modelos de Rateio'), findsOneWidget);
    expect(find.text('Cartões e Formas de Pagamento'), findsOneWidget);
    expect(find.text('Assinaturas & Contas Fixas'), findsOneWidget);
    expect(find.text('Ciclo Financeiro'), findsOneWidget);
    expect(find.text('Assistente IA'), findsOneWidget);
  });

  testWidgets(
    'Can open Categorias de Gastos modal and view default categories',
    (tester) async {
      await sl<FinanceCubit>().loadCycleData();

      await tester.pumpWidget(buildTestableWidget());
      await tester.pumpAndSettle();

      // Clica no tile de categorias
      await tester.tap(find.text('Categorias de Gastos'));
      await tester.pumpAndSettle();

      // Verifica que o modal abriu
      expect(find.text('Categorias da Casa'), findsOneWidget);
      expect(find.text('Supermercado'), findsOneWidget);
      expect(find.text('Moradia / Aluguel'), findsOneWidget);
      expect(find.text('Carro (Combustível)'), findsOneWidget);
      expect(find.text('Cadastrar Nova Categoria'), findsOneWidget);
    },
  );

  testWidgets('Can open Formas de Pagamento modal and view cards', (
    tester,
  ) async {
    await sl<FinanceCubit>().loadCycleData();

    await tester.pumpWidget(buildTestableWidget());
    await tester.pumpAndSettle();

    // Clica no tile de formas de pagamento
    final paymentTile = find.text('Cartões e Formas de Pagamento');
    await tester.ensureVisible(paymentTile);
    await tester.tap(paymentTile);
    await tester.pumpAndSettle();

    // Verifica que o modal abriu
    expect(find.text('Formas de Pagamento'), findsOneWidget);
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

    final tile = find.text('Ciclo Financeiro');
    await tester.ensureVisible(tile);
    await tester.tap(tile);
    await tester.pumpAndSettle();

    expect(find.text('Dia de Início do Ciclo'), findsOneWidget);
    expect(find.text('Todo dia 5'), findsOneWidget);
    expect(find.text('Salvar'), findsOneWidget);
  });

  testWidgets('Can open Editar Perfil da Conta modal and update profile', (
    tester,
  ) async {
    await sl<FinanceCubit>().loadCycleData();

    await tester.pumpWidget(buildTestableWidget());
    await tester.pumpAndSettle();

    final profileTile = find.text('Meu Perfil da Conta');
    await tester.ensureVisible(profileTile);
    await tester.tap(profileTile);
    await tester.pumpAndSettle();

    expect(find.text('Editar Perfil da Conta'), findsOneWidget);
    expect(find.text('Nome Completo'), findsOneWidget);
    expect(find.text('E-mail da Conta'), findsOneWidget);
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

    expect(find.text('caixa.nossacasa@nubank.com.br • Fundo Conjunto Nossa Casa'), findsOneWidget);
  });
}
