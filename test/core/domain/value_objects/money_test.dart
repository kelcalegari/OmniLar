import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';

void main() {
  group('Money Value Object', () {
    test('criação básica a partir de centavos e reais', () {
      final m1 = Money(1550);
      final m2 = Money.fromReal(15.50);
      expect(m1.cents, 1550);
      expect(m2.cents, 1550);
      expect(m1, m2);
      expect(m1.inReais, 15.50);
    });

    test('operações aritméticas (+, -, *, divisão justa)', () {
      final a = Money.fromReal(100.00);
      final b = Money.fromReal(30.50);

      expect((a + b).cents, 13050);
      expect((a - b).cents, 6950);
      expect((b * 2).cents, 6100);
      expect((-b).cents, -3050);
    });

    test('divisão em partes iguais sem perda de centavos (splitEqually)', () {
      final total = Money(1000); // R$ 10,00
      final split3 = total.splitEqually(3);

      expect(split3.length, 3);
      expect(split3[0].cents, 334);
      expect(split3[1].cents, 333);
      expect(split3[2].cents, 333);

      final sum = split3.reduce((val, elem) => val + elem);
      expect(sum.cents, total.cents);
    });

    test('cálculo de porcentagem', () {
      final total = Money.fromReal(200.00);
      expect(total.percentage(50).inReais, 100.00);
      expect(total.percentage(33.33).cents, 6666);
    });

    test('parse de strings de dinheiro', () {
      expect(Money.parse('R\$ 1.250,50').cents, 125050);
      expect(Money.parse('1250,50').cents, 125050);
      expect(Money.parse('1250.50').cents, 125050);
      expect(Money.parse('0').cents, 0);
      expect(Money.parse('').cents, 0);
    });

    test('formatação brasileira', () {
      final m = Money(123456); // R$ 1.234,56
      expect(m.format(), 'R\$\u{00A0}1.234,56'); // intl usa non-breaking space
      expect(m.format(includeSymbol: false), '1.234,56');
    });

    test('comparações relacionais', () {
      final m1 = Money(100);
      final m2 = Money(200);

      expect(m1 < m2, isTrue);
      expect(m2 > m1, isTrue);
      expect(m1 == Money(100), isTrue);
    });
  });
}
