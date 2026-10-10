import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/core/widgets/money_input_field.dart';

void main() {
  group('MoneyInputField - Entrada Nativa e Teclado Oculto por Padrão', () {
    testWidgets('Renderiza TextField nativo e esconde teclado virtual por padrão', (tester) async {
      Money current = const Money.zero();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MoneyInputField(
              initialValue: const Money.zero(),
              onChanged: (val) => current = val,
              quickAddCents: const [1000, 2000, 5000],
            ),
          ),
        ),
      );

      // Deve ter TextField nativo
      expect(find.byType(TextField), findsOneWidget);

      // Teclado virtual não deve estar presente por padrão
      expect(find.text('1'), findsNothing);
      expect(find.text('C'), findsNothing);

      // Chips de atalho rápido devem estar presentes
      expect(find.textContaining('10,00'), findsOneWidget);
      expect(find.textContaining('20,00'), findsOneWidget);
      expect(find.textContaining('50,00'), findsOneWidget);

      // Clicar no chip de R$ 10,00 deve incrementar
      await tester.tap(find.textContaining('10,00'));
      await tester.pumpAndSettle();
      expect(current.cents, equals(1000));

      final textFieldWidget = tester.widget<TextField>(find.byType(TextField));
      expect(textFieldWidget.controller?.text, equals(const Money(1000).format()));

      // Botão de backspace deve aparecer quando o valor > 0
      final backspace = find.byIcon(Icons.backspace_outlined);
      expect(backspace, findsOneWidget);

      await tester.tap(backspace);
      await tester.pumpAndSettle();
      expect(current.cents, equals(100)); // 1000 ~/ 10 = 100 (R$ 1,00)
    });

    testWidgets('Permite digitar números nativos e formata centavos continuamente', (tester) async {
      Money current = const Money.zero();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MoneyInputField(
              initialValue: const Money.zero(),
              onChanged: (val) => current = val,
            ),
          ),
        ),
      );

      final textField = find.byType(TextField);
      await tester.enterText(textField, '1250');
      await tester.pumpAndSettle();

      expect(current.cents, equals(1250));
      final textFieldWidget = tester.widget<TextField>(find.byType(TextField));
      expect(textFieldWidget.controller?.text, equals(const Money(1250).format()));
    });
  });
}
