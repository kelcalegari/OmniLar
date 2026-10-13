import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/domain/value_objects/financial_cycle.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/features/settlement/domain/entities/settlement_options.dart';
import 'package:omni_lar/features/settlement/domain/entities/settlement_summary.dart';
import 'package:omni_lar/features/settlement/domain/entities/super_pix_transfer.dart';
import 'package:omni_lar/features/settlement/domain/entities/transfer_settlement_resolution.dart';
import 'package:omni_lar/features/settlement/domain/services/settlement_shortfall.dart';

void main() {
  group('Pagamento parcial ao Caixa da Casa', () {
    final cycle = FinancialCycle.fromDate(
      date: DateTime(2026, 10, 12),
      cycleStartDay: 9,
    );

    // Bia deve R$ 1.300,00 ao Caixa e Caio deve R$ 200,00 à Ana; sobra de R$ 500,00.
    final summary = SettlementSummary(
      cycle: cycle,
      memberBalances: const [],
      transfers: const [
        SuperPixTransfer(
          id: 't1',
          fromMemberId: 'bia',
          fromMemberName: 'Bia',
          toMemberId: 'entity_caixa',
          toMemberName: 'Caixa da Casa',
          amount: Money(130000),
          description: 'Super Pix',
        ),
        SuperPixTransfer(
          id: 't2',
          fromMemberId: 'caio',
          fromMemberName: 'Caio',
          toMemberId: 'ana',
          toMemberName: 'Ana',
          amount: Money(20000),
          description: 'Super Pix',
        ),
      ],
      totalHouseExpenses: const Money(250000),
      totalContributions: const Money.zero(),
      totalP2PCleared: const Money.zero(),
      houseTreasuryBalance: const Money(50000),
    );

    SettlementOptions partial(
      String transferId,
      int expected,
      int paid,
      ShortfallAction action, {
      String? vaultId,
    }) {
      return SettlementOptions(
        transferResolutions: {
          transferId: TransferSettlementResolution(
            transferId: transferId,
            amountExpected: Money(expected),
            amountPaid: Money(paid),
            shortfallAction: action,
            vaultId: vaultId,
          ),
        },
      );
    }

    test('Sem pagamento parcial, a sobra inteira está disponível', () {
      expect(unpaidToHouse(summary, const SettlementOptions()).cents, 0);
      expect(availableSurplus(summary, const SettlementOptions()).cents, 50000);
    });

    test('O que faltou entrar no Caixa sai da sobra, seja acordo, pendência ou perdão', () {
      for (final action in [
        ShortfallAction.createP2PLoan,
        ShortfallAction.rolloverPending,
        ShortfallAction.forgiveRemainder,
      ]) {
        final options = partial('t1', 130000, 100000, action);
        expect(unpaidToHouse(summary, options).cents, 30000, reason: '$action');
        expect(availableSurplus(summary, options).cents, 20000, reason: '$action');
      }
    });

    test('Faltou mais do que a sobra: não há sobra para movimentar', () {
      final options = partial('t1', 130000, 50000, ShortfallAction.rolloverPending);
      expect(availableSurplus(summary, options).cents, 0);
    });

    test('Diferença coberta pela Caixinha não reduz a sobra', () {
      final options = partial(
        't1',
        130000,
        100000,
        ShortfallAction.deductFromVault,
        vaultId: 'v1',
      );
      expect(unpaidToHouse(summary, options).cents, 0);
      expect(availableSurplus(summary, options).cents, 50000);
    });

    test('Pagamento parcial entre moradores não mexe na sobra do Caixa', () {
      final options = partial('t2', 20000, 5000, ShortfallAction.createP2PLoan);
      expect(unpaidToHouse(summary, options).cents, 0);
      expect(availableSurplus(summary, options).cents, 50000);
    });
  });
}
