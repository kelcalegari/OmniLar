import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:omni_lar/core/di/service_locator.dart';
import 'package:omni_lar/core/widgets/privacy_toggle.dart';
import 'package:omni_lar/features/p2p/presentation/cubit/p2p_cubit.dart';
import 'package:omni_lar/features/p2p/presentation/pages/p2p_page.dart';

void main() {
  setUpAll(() async {
    if (!sl.isRegistered<P2PCubit>()) {
      await initServiceLocator();
    }
  });

  Widget buildP2PPage() {
    return BlocProvider.value(
      value: sl<P2PCubit>(),
      child: const MaterialApp(
        home: P2PPage(),
      ),
    );
  }

  group('P2PPage - Layout & AppBar Padronizado', () {
    testWidgets('Em Celular/Mobile, AppBar é limpa e padronizada com seletor no body',
        (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildP2PPage());
      await tester.pumpAndSettle();

      // AppBar padronizada com título e PrivacyToggleButton
      expect(find.widgetWithText(AppBar, 'Empréstimos P2P'), findsOneWidget);
      expect(find.byType(PrivacyToggleButton), findsOneWidget);

      // Card de Saldo Pessoal Líquido está no corpo da tela
      expect(find.text('Saldo Pessoal Líquido'), findsOneWidget);

      // Abas de navegação segmentadas
      expect(find.textContaining('Eu Devo'), findsOneWidget);
      expect(find.textContaining('Me Devem'), findsOneWidget);
    });

    testWidgets('Em Desktop (1280x800), renderiza duas colunas lado a lado',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildP2PPage());
      await tester.pumpAndSettle();

      // AppBar limpa no desktop
      expect(find.widgetWithText(AppBar, 'Empréstimos P2P'), findsOneWidget);

      // Ambas as colunas exibidas simultaneamente
      expect(find.text('Eu Devo'), findsOneWidget);
      expect(find.text('Me Devem'), findsOneWidget);
    });
  });
}
