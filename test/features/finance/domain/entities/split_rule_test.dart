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

    test('Percentuais que somam mais de 100% são normalizados em vez de sobrar para o último', () {
      const rule = SplitRule.percentage({'user_a': 35.0, 'user_b': 65.0, 'user_c': 50.0});
      final total = Money.fromReal(1000.00);

      final allocations = rule.calculateAllocations(
        totalAmount: total,
        memberIds: ['user_a', 'user_b', 'user_c'],
      );
      final reordered = rule.calculateAllocations(
        totalAmount: total,
        memberIds: ['user_c', 'user_a', 'user_b'],
      );

      expect(allocations['user_a']?.cents, 23334);
      expect(allocations['user_b']?.cents, 43333);
      expect(allocations['user_c']?.cents, 33333);
      expect(allocations.values.reduce((a, b) => a + b).cents, total.cents);
      for (final id in ['user_a', 'user_b', 'user_c']) {
        // Só o centavo de empate pode mudar de mãos com a ordem
        expect((reordered[id]!.cents - allocations[id]!.cents).abs(), lessThanOrEqualTo(1));
      }
    });

    test('Membro sem percentual definido não absorve a sobra do rateio', () {
      const rule = SplitRule.percentage({'user_a': 60.0, 'user_b': 40.0});
      final total = Money.fromReal(100.01);

      final allocations = rule.calculateAllocations(
        totalAmount: total,
        memberIds: ['user_a', 'user_b', 'user_c'],
      );

      expect(allocations['user_a']?.cents, 6001);
      expect(allocations['user_b']?.cents, 4000);
      expect(allocations['user_c']?.cents, 0);
    });
  });
}
