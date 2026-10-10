import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/features/finance/domain/entities/split_rule.dart';

void main() {
  group('SplitRule Allocations', () {
    test('Rateio por Porcentagem (60/40) exato em centavos', () {
      const rule = SplitRule.percentage({'user_a': 60.0, 'user_b': 40.0});
      final total = Money.fromReal(150.00); // R$ 150,00

      final allocations = rule.calculateAllocations(
        totalAmount: total,
        memberIds: ['user_a', 'user_b'],
      );

      expect(allocations['user_a']?.cents, 9000); // R$ 90,00
      expect(allocations['user_b']?.cents, 6000); // R$ 60,00
    });

    test('Rateio por Porcentagem com dízima/arredondamento mantém soma exata', () {
      const rule = SplitRule.percentage({'user_a': 33.33, 'user_b': 66.67});
      final total = Money.fromReal(100.00); // R$ 100,00 (10.000 centavos)

      final allocations = rule.calculateAllocations(
        totalAmount: total,
        memberIds: ['user_a', 'user_b'],
      );

      final sum = allocations.values.reduce((a, b) => a + b);
      expect(sum.cents, total.cents);
    });

    test('Rateio por Categoria (100% dono)', () {
      const rule = SplitRule.singleResponsible('user_carlos');
      final total = Money.fromReal(180.00);

      final allocations = rule.calculateAllocations(
        totalAmount: total,
        memberIds: ['user_carlos', 'user_marina'],
      );

      expect(allocations['user_carlos']?.cents, 18000);
      expect(allocations['user_marina']?.cents, 0);
    });
  });
}
