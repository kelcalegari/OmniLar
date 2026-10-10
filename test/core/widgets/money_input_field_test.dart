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

    testWidgets('Garante padrao Fintech/ATM: digitar 1 vira 0,01 e digitar 1 novamente vira 0,11', (tester) async {
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
      final textFieldWidget = tester.widget<TextField>(textField);
      final controller = textFieldWidget.controller!;

      // Simula o usuário digitando através da máscara após a vírgula: "R$ 0,100"
      await tester.enterText(textField, 'R\$ 0,100');
      await tester.pumpAndSettle();

      // Não deve virar R$ 1,00; deve virar R$ 0,01 (1 centavo)
      expect(current.cents, equals(1));
      expect(controller.text, equals(const Money(1).format()));

      // Digitar outro '1' (agora no fim de "R$ 0,01")
      await tester.enterText(textField, '${controller.text}1');
      await tester.pumpAndSettle();

      // Não deve virar R$ 10,01; deve virar R$ 0,11 (11 centavos)
      expect(current.cents, equals(11));
      expect(controller.text, equals(const Money(11).format()));

      // Digitar '0'
      await tester.enterText(textField, '${controller.text}0');
      await tester.pumpAndSettle();
      expect(current.cents, equals(110)); // R$ 1,10
      expect(controller.text, equals(const Money(110).format()));

      // Pressionar backspace apagando o último dígito
      await tester.enterText(textField, controller.text.substring(0, controller.text.length - 1));
      await tester.pumpAndSettle();
      expect(current.cents, equals(11)); // R$ 0,11
      expect(controller.text, equals(const Money(11).format()));
    });

    test('MoneyInputFormatter unit tests - comportamento rigoroso ATM', () {
      const formatter = MoneyInputFormatter();

      // Inicia em 0
      const initial = TextEditingValue(
        text: 'R\$ 0,00',
        selection: TextSelection.collapsed(offset: 7),
      );

      // Usuário inseriu '1' no meio/após a vírgula: "R$ 0,100"
      final afterCommaInsert = formatter.formatEditUpdate(
        initial,
        const TextEditingValue(
          text: 'R\$ 0,100',
          selection: TextSelection.collapsed(offset: 6),
        ),
      );
      expect(afterCommaInsert.text, equals(const Money(1).format())); // R$ 0,01
      expect(afterCommaInsert.selection.baseOffset, equals(afterCommaInsert.text.length));

      // Próximo dígito '1' inserido no fim
      final nextDigit = formatter.formatEditUpdate(
        afterCommaInsert,
        TextEditingValue(
          text: '${afterCommaInsert.text}1',
          selection: TextSelection.collapsed(offset: afterCommaInsert.text.length + 1),
        ),
      );
      expect(nextDigit.text, equals(const Money(11).format())); // R$ 0,11

      // Backspace
      final afterBackspace = formatter.formatEditUpdate(
        nextDigit,
        TextEditingValue(
          text: nextDigit.text.substring(0, nextDigit.text.length - 1),
          selection: TextSelection.collapsed(offset: nextDigit.text.length - 1),
        ),
      );
      expect(afterBackspace.text, equals(const Money(1).format())); // R$ 0,01
    });

    test('MoneyInputFormatter com allowEmpty permite campo opcional vazio e limpa no backspace', () {
      const formatter = MoneyInputFormatter(allowEmpty: true);

      // Inicia vazio
      const empty = TextEditingValue.empty;
      expect(formatter.formatEditUpdate(empty, empty).text, equals(''));

      // Digita '1' em campo vazio
      final firstDigit = formatter.formatEditUpdate(
        empty,
        const TextEditingValue(text: '1', selection: TextSelection.collapsed(offset: 1)),
      );
      expect(firstDigit.text, equals(const Money(1).format())); // R$ 0,01

      // Digita '5'
      final secondDigit = formatter.formatEditUpdate(
        firstDigit,
        TextEditingValue(
          text: '${firstDigit.text}5',
          selection: TextSelection.collapsed(offset: firstDigit.text.length + 1),
        ),
      );
      expect(secondDigit.text, equals(const Money(15).format())); // R$ 0,15

      // Backspace 1: volta para R$ 0,01
      final bs1 = formatter.formatEditUpdate(
        secondDigit,
        TextEditingValue(
          text: secondDigit.text.substring(0, secondDigit.text.length - 1),
          selection: TextSelection.collapsed(offset: secondDigit.text.length - 1),
        ),
      );
      expect(bs1.text, equals(const Money(1).format())); // R$ 0,01

      // Backspace 2: volta para R$ 0,00
      final bs2 = formatter.formatEditUpdate(
        bs1,
        TextEditingValue(
          text: bs1.text.substring(0, bs1.text.length - 1),
          selection: TextSelection.collapsed(offset: bs1.text.length - 1),
        ),
      );
      expect(bs2.text, equals(const Money(0).format())); // R$ 0,00

      // Backspace 3 em R$ 0,00: limpa o campo para vazio
      final bs3 = formatter.formatEditUpdate(
        bs2,
        TextEditingValue(
          text: bs2.text.substring(0, bs2.text.length - 1),
          selection: TextSelection.collapsed(offset: bs2.text.length - 1),
        ),
      );
      expect(bs3.text, equals(''));
    });

    test('MoneyTextEditingController expõe Money e cents diretamente com seleção correta', () {
      final ctrl = MoneyTextEditingController(initialMoney: const Money(4500));
      expect(ctrl.text, equals(const Money(4500).format()));
      expect(ctrl.cents, equals(4500));
      expect(ctrl.money, equals(const Money(4500)));

      ctrl.setMoney(const Money(1));
      expect(ctrl.text, equals(const Money(1).format()));
      expect(ctrl.cents, equals(1));
      expect(ctrl.selection.baseOffset, equals(ctrl.text.length));

      ctrl.clear();
      expect(ctrl.text, equals(const Money(0).format()));

      final optionalCtrl = MoneyTextEditingController(allowEmpty: true);
      expect(optionalCtrl.text, equals(''));
      expect(optionalCtrl.cents, equals(0));
      optionalCtrl.clear();
      expect(optionalCtrl.text, equals(''));
    });

    testWidgets('MoneyTextFormField formata tecla a tecla 1 -> 0,01, 11 -> 0,11, 110 -> 1,10', (tester) async {
      Money? changedMoney;
      final controller = MoneyTextEditingController(allowEmpty: true);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MoneyTextFormField(
              controller: controller,
              labelText: 'Custo estimado',
              onChanged: (m) => changedMoney = m,
              allowEmpty: true,
            ),
          ),
        ),
      );

      final formField = find.byType(TextFormField);
      expect(formField, findsOneWidget);

      // Inicia vazio por ser allowEmpty: true
      expect(controller.text, equals(''));

      // Digita '1' -> vira R$ 0,01
      await tester.enterText(formField, '1');
      await tester.pumpAndSettle();
      expect(controller.text, equals(const Money(1).format()));
      expect(changedMoney?.cents, equals(1));

      // Digita outro '1' -> vira R$ 0,11
      await tester.enterText(formField, '${controller.text}1');
      await tester.pumpAndSettle();
      expect(controller.text, equals(const Money(11).format()));
      expect(changedMoney?.cents, equals(11));

      // Digita '0' -> vira R$ 1,10
      await tester.enterText(formField, '${controller.text}0');
      await tester.pumpAndSettle();
      expect(controller.text, equals(const Money(110).format()));
      expect(changedMoney?.cents, equals(110));

      // Digita '0' -> vira R$ 11,00
      await tester.enterText(formField, '${controller.text}0');
      await tester.pumpAndSettle();
      expect(controller.text, equals(const Money(1100).format()));
      expect(changedMoney?.cents, equals(1100));
    });
  });
}
