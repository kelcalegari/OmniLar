import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/domain/value_objects/financial_cycle.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/features/settlement/domain/entities/settlement_options.dart';
import 'package:omni_lar/features/settlement/domain/entities/settlement_summary.dart';
import 'package:omni_lar/features/settlement/domain/entities/super_pix_transfer.dart';
import 'package:omni_lar/features/settlement/domain/repositories/settlement_repository.dart';
import 'package:omni_lar/features/settlement/presentation/cubit/settlement_cubit.dart';
import 'package:omni_lar/features/settlement/presentation/cubit/settlement_state.dart';

final _cycle = FinancialCycle(start: DateTime(2026, 10, 5), end: DateTime(2026, 11, 4));

SettlementSummary _summary(int p2pCents) => SettlementSummary(
      cycle: _cycle,
      memberBalances: const [],
      transfers: [
        if (p2pCents > 0)
          SuperPixTransfer(
            id: 't_${DateTime.now().microsecondsSinceEpoch}',
            fromMemberId: 'member_marina',
            fromMemberName: 'Marina',
            toMemberId: 'member_carlos',
            toMemberName: 'Carlos',
            amount: Money(p2pCents),
            description: 'Super Pix',
          ),
      ],
      totalHouseExpenses: const Money.zero(),
      totalContributions: const Money.zero(),
      totalP2PCleared: Money(p2pCents),
      houseTreasuryBalance: const Money.zero(),
    );

class _FakeSettlementRepository implements SettlementRepository {
  int p2pCents = 10000;
  int confirmCalls = 0;

  @override
  Future<SettlementSummary> getSettlementSummary(
    FinancialCycle cycle, {
    SettlementOptions? options,
  }) async => _summary(p2pCents);

  @override
  Future<void> confirmSettlement(SettlementSummary summary, {SettlementOptions? options}) async {
    confirmCalls++;
  }

  @override
  Future<void> reopenSettlement(FinancialCycle cycle) async {}
}

void main() {
  group('Fechamento - recálculo na confirmação', () {
    test('Confirma normalmente quando nada mudou', () async {
      final repo = _FakeSettlementRepository();
      final cubit = SettlementCubit(repo);
      await cubit.loadSettlement(_cycle);

      await cubit.confirmSettlement();

      expect(repo.confirmCalls, 1);
      expect(cubit.state.status, SettlementCubitStatus.settled);
    });

    test('Não grava e pede revisão quando uma parcela foi antecipada com a tela aberta', () async {
      final repo = _FakeSettlementRepository();
      final cubit = SettlementCubit(repo);
      await cubit.loadSettlement(_cycle);
      expect(cubit.state.summary!.totalP2PCleared.cents, 10000);

      final statuses = <SettlementCubitStatus>[];
      final sub = cubit.stream.listen((s) => statuses.add(s.status));

      // Marina antecipa a parcela pela página de P2P enquanto o fechamento está aberto
      repo.p2pCents = 0;
      await cubit.confirmSettlement();
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(repo.confirmCalls, 0);
      expect(statuses, contains(SettlementCubitStatus.error));
      expect(cubit.state.status, SettlementCubitStatus.loaded);
      expect(cubit.state.summary!.transfers, isEmpty);
      expect(cubit.state.errorMessage, contains('Os valores mudaram'));
    });
  });
}
