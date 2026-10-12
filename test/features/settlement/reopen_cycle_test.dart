import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/domain/value_objects/financial_cycle.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/features/finance/data/datasources/mock_finance_datasource.dart';
import 'package:omni_lar/features/finance/domain/entities/contribution.dart';
import 'package:omni_lar/features/finance/domain/entities/house_expense.dart';
import 'package:omni_lar/features/finance/domain/entities/house_member.dart';
import 'package:omni_lar/features/finance/domain/entities/split_rule.dart';
import 'package:omni_lar/features/p2p/data/datasources/mock_p2p_datasource.dart';
import 'package:omni_lar/features/settlement/data/datasources/mock_settlement_datasource.dart';
import 'package:omni_lar/features/settlement/domain/entities/settlement_summary.dart';
import 'package:omni_lar/features/settlement/domain/services/global_clearing_engine.dart';

void main() {
  group('Reabrir o ciclo, lançar e fechar de novo', () {
    late MockFinanceDataSource finance;
    late MockSettlementDataSource settlement;
    late FinancialCycle cycle;

    HouseExpense outOfPocket(String id, int cents, String paidBy) => HouseExpense(
      id: id,
      title: 'Despesa $id',
      amount: Money(cents),
      date: cycle.startDate.add(const Duration(days: 1)),
      categoryId: 'cat_moradia',
      paidByMemberId: paidBy,
      paymentMethodId: 'pm_pix',
      paidOutOfPocket: true,
      splitRule: const SplitRule.percentage({'member_carlos': 50.0, 'member_marina': 50.0}),
    );

    int net(SettlementSummary summary, String memberId) =>
        summary.memberBalances.firstWhere((b) => b.memberId == memberId).netBalance.cents;

    setUp(() {
      finance = MockFinanceDataSource();
      settlement = MockSettlementDataSource(
        financeDataSource: finance,
        p2pDataSource: MockP2PDataSource(),
      );
      cycle = FinancialCycle.fromDate(date: DateTime.now(), cycleStartDay: 5);
    });

    test('Reabrir sem novos lançamentos não gera nenhuma cobrança nova', () async {
      await finance.addExpense(outOfPocket('exp_reabrir_1', 20000, 'member_carlos'));

      final first = await settlement.getSettlementSummary(cycle);
      await settlement.confirmSettlement(first);
      await settlement.reopenSettlement(cycle);

      final reopened = await settlement.getSettlementSummary(cycle);

      expect(reopened.status, SettlementStatus.readyToSettle);
      expect(reopened.isReopened, isTrue);
      // Quem pagou do bolso já foi reembolsado no primeiro fechamento
      expect(net(reopened, 'member_carlos'), 0);
      expect(net(reopened, 'member_marina'), 0);
      expect(reopened.transfers, isEmpty);
    });

    test('Novo lançamento após reabrir cobra só a diferença', () {
      // Primeiro fechamento já acertado: Carlos pagou R$ 200,00 do bolso (reembolsado)
      // e cada um ficou com R$ 100,00 de aporte registrado.
      final settledExpense = outOfPocket('e1', 20000, 'member_carlos')
          .copyWith(settledAt: DateTime(2031, 3, 20));
      // Despesa esquecida, lançada depois de reabrir: R$ 100,00 pagos pela Marina
      final forgottenExpense = outOfPocket('e2', 10000, 'member_marina');

      final summary = const GlobalClearingEngine().computeSettlement(
        cycle: cycle,
        members: const [
          HouseMember(id: 'member_carlos', name: 'Carlos'),
          HouseMember(id: 'member_marina', name: 'Marina'),
        ],
        expenses: [settledExpense, forgottenExpense],
        contributions: [
          Contribution(id: 'c1', memberId: 'member_carlos', amount: const Money(10000), date: cycle.startDate),
          Contribution(id: 'c2', memberId: 'member_marina', amount: const Money(10000), date: cycle.startDate),
        ],
        loans: const [],
      );

      expect(net(summary, 'member_marina'), 5000);
      expect(net(summary, 'member_carlos'), -5000);
      expect(summary.transfers.length, 1);
      expect(summary.transfers.single.fromMemberId, 'member_carlos');
      expect(summary.transfers.single.toMemberId, 'member_marina');
      expect(summary.transfers.single.amount.cents, 5000);
    });

    test('Mudar o rateio padrão da casa depois de fechar não mexe no que já foi acertado', () async {
      // Despesa sem rateio próprio: usa o padrão da casa (60/40 nos dados de demonstração)
      await finance.addExpense(
        outOfPocket('exp_reabrir_padrao', 20000, 'member_carlos')
            .copyWith(splitRule: const SplitRule.percentage(null)),
      );

      await settlement.confirmSettlement(await settlement.getSettlementSummary(cycle));

      await finance.updateHouseSplitModel(
        splitModel: 'percentage',
        percentages: const {'member_carlos': 10.0, 'member_marina': 90.0},
        fixedAmountsCents: const {'member_carlos': 0, 'member_marina': 0},
      );
      await settlement.reopenSettlement(cycle);
      final reopened = await settlement.getSettlementSummary(cycle);

      expect(net(reopened, 'member_carlos'), 0);
      expect(net(reopened, 'member_marina'), 0);
      expect(reopened.transfers, isEmpty);
    });

    test('Fechar de novo mantém o histórico do primeiro fechamento', () async {
      await finance.addExpense(outOfPocket('exp_reabrir_1', 20000, 'member_carlos'));

      final first = await settlement.getSettlementSummary(cycle);
      final firstTransfers = first.transfers.length;
      await settlement.confirmSettlement(first);
      await settlement.reopenSettlement(cycle);

      await finance.addExpense(outOfPocket('exp_reabrir_2', 10000, 'member_marina'));
      await settlement.confirmSettlement(await settlement.getSettlementSummary(cycle));

      final closedAgain = await settlement.getSettlementSummary(cycle);
      expect(closedAgain.status, SettlementStatus.settled);
      expect(closedAgain.transfers.length, firstTransfers + 1);

      // Reabrir de novo, sem lançamentos, continua sem cobrança
      await settlement.reopenSettlement(cycle);
      final reopenedAgain = await settlement.getSettlementSummary(cycle);
      expect(reopenedAgain.transfers, isEmpty);
    });
  });
}
