import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:omni_lar/core/di/service_locator.dart';
import 'package:omni_lar/features/finance/presentation/cubit/finance_cubit.dart';
import 'package:omni_lar/features/p2p/presentation/cubit/p2p_cubit.dart';
import 'package:omni_lar/features/p2p/presentation/pages/create_loan_page.dart';

void main() {
  setUpAll(() async {
    if (!sl.isRegistered<P2PCubit>()) {
      await initServiceLocator();
    }
  });

  Widget buildCreateLoanPage() {
    return MultiBlocProvider(
      providers: [
        BlocProvider.value(value: sl<P2PCubit>()),
        BlocProvider.value(value: sl<FinanceCubit>()),
      ],
      child: const MaterialApp(
        home: CreateLoanPage(),
      ),
    );
  }

  group('CreateLoanPage - Empréstimo Antigo e Detalhamento de Parcelas', () {
    testWidgets('Renderiza switch de empréstimo iniciado no passado', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildCreateLoanPage());
      await tester.pumpAndSettle();

      expect(find.text('Empréstimo iniciado no passado?'), findsOneWidget);
      expect(find.text('Vencimento da 1ª Parcela'), findsOneWidget);
    });

    testWidgets('Ativa modo histórico e exibe seletor de parcelas pagas no passado', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildCreateLoanPage());
      await tester.pumpAndSettle();

      // Clica no switch para ativar modo histórico
      final switchFinder = find.widgetWithText(SwitchListTile, 'Empréstimo iniciado no passado?');
      expect(switchFinder, findsOneWidget);
      await tester.tap(switchFinder);
      await tester.pumpAndSettle();

      // Confere se as opções de parcelas pagas no passado apareceram
      expect(find.text('Parcelas já quitadas anteriormente:'), findsOneWidget);
      expect(find.byType(Slider), findsOneWidget);
      expect(find.textContaining('sem debitar ou creditar o caixa atual'), findsOneWidget);
    });

    testWidgets('Exibe detalhamento e permite alternar status de parcela individual', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildCreateLoanPage());
      await tester.pumpAndSettle();

      // Preenche título
      await tester.enterText(find.widgetWithText(TextField, 'Título do Empréstimo'), 'Celular Passado');
      await tester.pumpAndSettle();

      // Clica em um botão rápido de valor (+ R$ 100,00)
      final quickAdd100 = find.textContaining('100,00');
      expect(quickAdd100, findsWidgets);
      await tester.tap(quickAdd100.first);
      await tester.pumpAndSettle();

      // Escolhe 3x
      await tester.tap(find.text('3x'));
      await tester.pumpAndSettle();

      // Detalhamento das parcelas deve estar visível
      expect(find.text('Detalhamento das Parcelas'), findsOneWidget);
      expect(find.text('Dividir igualmente'), findsOneWidget);

      // Encontra botões de status de parcelas
      final openChips = find.text('Em aberto');
      expect(openChips, findsWidgets);

      // Clica no primeiro chip para alternar para Paga
      await tester.tap(openChips.first);
      await tester.pumpAndSettle();

      expect(find.text('Paga'), findsOneWidget);
    });
  });
}
