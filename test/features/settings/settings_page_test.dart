import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:omni_lar/core/di/service_locator.dart';
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
        BlocProvider<AuthCubit>.value(value: sl<AuthCubit>()),
        BlocProvider<FinanceCubit>.value(value: sl<FinanceCubit>()),
      ],
      child: const MaterialApp(
        home: SettingsPage(),
      ),
    );
  }

  testWidgets('SettingsPage renders all setting tiles properly', (tester) async {
    // Carrega dados iniciais do financeCubit
    await sl<FinanceCubit>().loadCycleData();

    await tester.pumpWidget(buildTestableWidget());
    await tester.pumpAndSettle();

    expect(find.text('Ajustes da Casa'), findsOneWidget);
    expect(find.text('Membros da Casa e Convites'), findsOneWidget);
    expect(find.text('Categorias de Gastos'), findsOneWidget);
    expect(find.text('Modelos de Rateio'), findsOneWidget);
    expect(find.text('Cartões e Formas de Pagamento'), findsOneWidget);
    expect(find.text('Ciclo Financeiro'), findsOneWidget);
    expect(find.text('Assistente IA'), findsOneWidget);
  });

  testWidgets('Can open Categorias de Gastos modal and view default categories', (tester) async {
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
  });

  testWidgets('Can open Formas de Pagamento modal and view cards', (tester) async {
    await sl<FinanceCubit>().loadCycleData();

    await tester.pumpWidget(buildTestableWidget());
    await tester.pumpAndSettle();

    // Clica no tile de formas de pagamento
    await tester.tap(find.text('Cartões e Formas de Pagamento'));
    await tester.pumpAndSettle();

    // Verifica que o modal abriu
    expect(find.text('Formas de Pagamento'), findsOneWidget);
    expect(find.text('Nubank Carlos'), findsOneWidget);
    expect(find.text('VR Marina (Vale Refeição)'), findsOneWidget);
    expect(find.text('Cadastrar Cartão ou VR'), findsOneWidget);
  });

  testWidgets('Can open Modelos de Rateio and see options', (tester) async {
    await sl<FinanceCubit>().loadCycleData();

    await tester.pumpWidget(buildTestableWidget());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Modelos de Rateio'));
    await tester.pumpAndSettle();

    expect(find.text('Porcentagem Personalizada'), findsOneWidget);
    expect(find.text('Por Categoria de Gasto'), findsOneWidget);
    expect(find.text('Salvar Modelo de Rateio'), findsOneWidget);
  });

  testWidgets('Can open Ciclo Financeiro dialog', (tester) async {
    await sl<FinanceCubit>().loadCycleData();

    await tester.pumpWidget(buildTestableWidget());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ciclo Financeiro'));
    await tester.pumpAndSettle();

    expect(find.text('Dia de Início do Ciclo'), findsOneWidget);
    expect(find.text('Todo dia 5'), findsOneWidget);
    expect(find.text('Salvar'), findsOneWidget);
  });
}
