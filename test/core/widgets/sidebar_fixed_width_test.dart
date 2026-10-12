import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/di/service_locator.dart';
import 'package:omni_lar/features/finance/presentation/cubit/finance_cubit.dart';
import 'package:omni_lar/main.dart';

void main() {
  setUpAll(() async {
    if (!sl.isRegistered<FinanceCubit>()) {
      await initServiceLocator();
    }
  });

  testWidgets('A barra lateral e o botão de ação mantêm largura fixa e imutável ao trocar de aba', (tester) async {
    tester.view.physicalSize = const Size(1280, 850);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(const OmniLarApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    // Função auxiliar para verificar as larguras
    double getRailWidth() {
      final railFinder = find.byType(NavigationRail);
      expect(railFinder, findsOneWidget);
      final renderBox = tester.renderObject(railFinder) as RenderBox;
      return renderBox.size.width;
    }

    double getButtonWidth() {
      final buttonFinder = find.descendant(
        of: find.byType(NavigationRail),
        matching: find.byType(FilledButton),
      );
      expect(buttonFinder, findsOneWidget);
      final renderBox = tester.renderObject(buttonFinder) as RenderBox;
      return renderBox.size.width;
    }

    // 1. Aba Inicial (A Casa)
    final railWidthHome = getRailWidth();
    final buttonWidthHome = getButtonWidth();
    expect(railWidthHome, equals(152.0));
    expect(buttonWidthHome, equals(132.0));

    // 2. Navega para Tarefas
    await tester.tap(find.descendant(of: find.byType(NavigationRail), matching: find.text('Tarefas')));
    await tester.pumpAndSettle();
    expect(getRailWidth(), equals(railWidthHome));
    expect(getButtonWidth(), equals(buttonWidthHome));

    // 3. Navega para Agenda
    await tester.tap(find.descendant(of: find.byType(NavigationRail), matching: find.text('Agenda')));
    await tester.pumpAndSettle();
    expect(getRailWidth(), equals(railWidthHome));
    expect(getButtonWidth(), equals(buttonWidthHome));

    // 4. Navega para Pessoal
    await tester.tap(find.descendant(of: find.byType(NavigationRail), matching: find.text('Pessoal')));
    await tester.pumpAndSettle();
    expect(getRailWidth(), equals(railWidthHome));
    expect(getButtonWidth(), equals(buttonWidthHome));

    // 5. Navega para Ajustes
    await tester.tap(find.descendant(of: find.byType(NavigationRail), matching: find.text('Ajustes')));
    await tester.pumpAndSettle();
    expect(getRailWidth(), equals(railWidthHome));
    expect(getButtonWidth(), equals(buttonWidthHome));
  });
}
