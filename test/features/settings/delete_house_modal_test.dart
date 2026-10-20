import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/features/auth/domain/entities/house.dart';
import 'package:omni_lar/features/settings/presentation/widgets/house_management_panel.dart';

void main() {
  group('DeleteHouseModal Tests', () {
    testWidgets('DeleteHouseModal adjusts padding with keyboard viewInsets without being hidden', (tester) async {
      const house = House(id: 'h1', name: 'Minha Residência', createdBy: 'u1');

      // Simula teclado virtual de 300px aberto
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MediaQuery(
              data: MediaQueryData(viewInsets: EdgeInsets.only(bottom: 300)),
              child: DeleteHouseModal(house: house),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Excluir Casa Definitivamente'), findsOneWidget);
      expect(find.text('Minha Residência'), findsWidgets);

      // O Padding inferior deve ser 300 + 24 = 324px para evitar sobreposição do teclado
      final paddingFinder = find.byWidgetPredicate(
        (w) => w is Padding && w.padding == const EdgeInsets.fromLTRB(24, 24, 24, 324),
      );
      expect(paddingFinder, findsOneWidget);

      // O botão de preencher deve preencher o controller e habilitar o botão
      await tester.tap(find.text('Preencher'));
      await tester.pumpAndSettle();

      final confirmBtn = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Excluir Casa'),
      );
      expect(confirmBtn.onPressed, isNotNull);
    });

    testWidgets('DeleteHouseModal uses default 24px padding when keyboard is closed', (tester) async {
      const house = House(id: 'h1', name: 'Minha Residência', createdBy: 'u1');

      // Sem teclado aberto (viewInsets = zero)
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MediaQuery(
              data: MediaQueryData(viewInsets: EdgeInsets.zero),
              child: DeleteHouseModal(house: house),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final paddingFinder = find.byWidgetPredicate(
        (w) => w is Padding && w.padding == const EdgeInsets.fromLTRB(24, 24, 24, 24),
      );
      expect(paddingFinder, findsOneWidget);
    });
  });
}
