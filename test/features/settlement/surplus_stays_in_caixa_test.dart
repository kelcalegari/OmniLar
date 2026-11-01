import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/features/settlement/domain/entities/settlement_options.dart';
import 'package:omni_lar/features/settlement/domain/services/settlement_shortfall.dart';

void main() {
  test('sobra fica no Caixa quando escolhida ou sem caixinha de destino', () {
    expect(surplusStaysInCaixa(const SettlementOptions(surplusAction: SurplusAction.rollover)), isTrue);
    // "Guardar na caixinha" sem caixinha: antes a sobra sumia
    expect(surplusStaysInCaixa(const SettlementOptions(surplusAction: SurplusAction.toVault)), isTrue);
    expect(surplusStaysInCaixa(null), isTrue);
    expect(
      surplusStaysInCaixa(
        const SettlementOptions(surplusAction: SurplusAction.toVault, targetVaultId: 'v1'),
      ),
      isFalse,
    );
    expect(surplusStaysInCaixa(const SettlementOptions(surplusAction: SurplusAction.refund)), isFalse);
  });
}
