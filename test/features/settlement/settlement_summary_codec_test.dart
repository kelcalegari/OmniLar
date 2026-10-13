import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/domain/value_objects/financial_cycle.dart';
import 'package:omni_lar/features/settlement/data/datasources/mock_settlement_datasource.dart';
import 'package:omni_lar/features/settlement/data/settlement_summary_codec.dart';
import 'package:omni_lar/features/settlement/domain/entities/settlement_summary.dart';
import 'package:omni_lar/features/settlement/domain/entities/super_pix_transfer.dart';
import 'package:omni_lar/features/finance/data/datasources/mock_finance_datasource.dart';
import 'package:omni_lar/features/p2p/data/datasources/mock_p2p_datasource.dart';

void main() {
  group('Retrato do fechamento', () {
    late SettlementSummary computed;
    final cycle = FinancialCycle.fromDate(date: DateTime.now(), cycleStartDay: 5);

    setUp(() async {
      final datasource = MockSettlementDataSource(
        financeDataSource: MockFinanceDataSource(),
        p2pDataSource: MockP2PDataSource(),
      );
      computed = await datasource.getSettlementSummary(cycle);
    });

    test('o fechamento calculado tem o que o retrato precisa guardar', () {
      expect(computed.memberBalances, isNotEmpty);
      expect(computed.auditTrails, isNotEmpty);
    });

    test('ida e volta pelo JSON preserva saldos, transferências e memória de cálculo', () {
      // Passa pelo texto JSON, como acontece ao gravar e ler do banco
      final json = jsonDecode(jsonEncode(settlementSummaryToJson(computed)));
      final settledAt = DateTime(2026, 10, 13, 12);
      final restored = settlementSummaryFromJson(json, cycle: cycle, settledAt: settledAt)!;

      expect(restored.status, SettlementStatus.settled);
      expect(restored.settledAt, settledAt);
      expect(restored.totalHouseExpenses, computed.totalHouseExpenses);
      expect(restored.totalContributions, computed.totalContributions);
      expect(restored.totalP2PCleared, computed.totalP2PCleared);
      expect(restored.houseTreasuryBalance, computed.houseTreasuryBalance);
      expect(restored.bucketDeficit, computed.bucketDeficit);
      expect(restored.isNetZeroSum, computed.isNetZeroSum);

      expect(restored.memberBalances.length, computed.memberBalances.length);
      for (var i = 0; i < computed.memberBalances.length; i++) {
        final a = computed.memberBalances[i];
        final b = restored.memberBalances[i];
        expect(b.memberId, a.memberId);
        expect(b.memberName, a.memberName);
        expect(b.netBalance, a.netBalance);
        expect(b.contributionDue, a.contributionDue);
        expect(b.contributionPaid, a.contributionPaid);
      }

      expect(restored.transfers.length, computed.transfers.length);
      for (var i = 0; i < computed.transfers.length; i++) {
        final a = computed.transfers[i];
        final b = restored.transfers[i];
        expect(b.fromMemberName, a.fromMemberName);
        expect(b.toMemberName, a.toMemberName);
        expect(b.amount, a.amount);
        expect(b.description, a.description);
        expect(b.status, TransferStatus.confirmed);
      }

      expect(restored.auditTrails.keys.toSet(), computed.auditTrails.keys.toSet());
      for (final id in computed.auditTrails.keys) {
        final a = computed.auditTrails[id]!;
        final b = restored.auditTrails[id]!;
        expect(b.netBalance, a.netBalance);
        expect(b.expenseShares.length, a.expenseShares.length);
        expect(b.contributionsMade.length, a.contributionsMade.length);
        expect(b.outOfPocketExpenses.length, a.outOfPocketExpenses.length);
        expect(b.p2pReceivables.length, a.p2pReceivables.length);
        expect(b.p2pPayables.length, a.p2pPayables.length);
        expect(b.sharedHouseSharesTotal, a.sharedHouseSharesTotal);
        expect(b.personalItemsSharesTotal, a.personalItemsSharesTotal);
        expect(b.mathEquationSummary, a.mathEquationSummary);
      }
    });

    test('retrato ausente, de outra versão ou corrompido devolve null', () {
      expect(settlementSummaryFromJson(null, cycle: cycle), isNull);
      expect(settlementSummaryFromJson({'v': 999}, cycle: cycle), isNull);
      expect(
        settlementSummaryFromJson({
          'v': settlementSnapshotVersion,
          'member_balances': [
            {'member_name': 'sem id'},
          ],
        }, cycle: cycle),
        isNull,
      );
    });
  });
}
