import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/domain/value_objects/financial_cycle.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/features/finance/data/datasources/mock_finance_datasource.dart';
import 'package:omni_lar/features/finance/data/repositories/finance_repository_impl.dart';
import 'package:omni_lar/features/finance/domain/entities/cycle_funding_estimate.dart';
import 'package:omni_lar/features/finance/domain/entities/house_expense.dart';
import 'package:omni_lar/features/finance/domain/entities/house_member.dart';
import 'package:omni_lar/features/finance/domain/entities/house_settings.dart';
import 'package:omni_lar/features/finance/domain/entities/opening_inflows.dart';
import 'package:omni_lar/features/finance/domain/entities/split_rule.dart';
import 'package:omni_lar/features/finance/domain/services/cycle_funding_estimator.dart';
import 'package:omni_lar/features/finance/presentation/cubit/finance_cubit.dart';
import 'package:omni_lar/features/settlement/domain/entities/settlement_summary.dart';
import 'package:omni_lar/features/settlement/domain/services/global_clearing_engine.dart';

void main() {
  const engine = GlobalClearingEngine();
  const estimator = CycleFundingEstimator();
  final cycle = FinancialCycle.fromDate(date: DateTime(2026, 10, 12), cycleStartDay: 7);

  HouseExpense expense(String id, int cents) => HouseExpense(
        id: id,
        title: 'Conta $id',
        amount: Money(cents),
        date: DateTime(2026, 10, 12),
        categoryId: 'c',
        paidByMemberId: 'ana',
        paymentMethodId: 'pm_caixa',
        splitRule: const SplitRule.percentage(null),
      );

  int due(SettlementSummary s, String id) =>
      s.memberBalances.firstWhere((b) => b.memberId == id).contributionDue.cents;
  int totalDue(SettlementSummary s) => s.memberBalances.fold<int>(0, (acc, b) => acc + b.contributionDue.cents);

  // Resgate da Reserva da Casa devolvido ao Caixa no primeiro ciclo
  const withdrawal = 195958;
  const reserva = 'vault_reserva';
  const viagem = 'vault_viagem';
  const names = {reserva: 'Reserva da Casa', viagem: 'Viagem'};

  group('Valor fixo, primeiro ciclo, resgate de R\$ 1.959,58 (balde de R\$ 2.000: Ana 1.200, Bia 800)', () {
    const members = [
      HouseMember(id: 'ana', name: 'Ana', defaultFixedAmountCents: 120000),
      HouseMember(id: 'bia', name: 'Bia', defaultFixedAmountCents: 80000),
    ];
    final targets = {for (final m in members) m.id: Money(m.defaultFixedAmountCents!)};

    SettlementSummary compute(
      int expenseCents, {
      Map<String, int> vaults = const {reserva: withdrawal},
      OpeningInflowRules rules = const OpeningInflowRules(),
      OpeningBalanceRule? rule = OpeningBalanceRule.coverExcess,
      bool withInflows = true,
    }) {
      final vaultCents = vaults.values.fold<int>(0, (acc, c) => acc + c);
      return engine.computeSettlement(
        cycle: cycle,
        members: members,
        expenses: [expense('e1', expenseCents)],
        contributions: const [],
        loans: const [],
        customContributionTargets: targets,
        openingBalance: Money(vaultCents),
        vaultReturns: Money(vaultCents),
        openingBalanceRule: rule,
        openingInflows: withInflows
            ? OpeningInflows(
                vaultWithdrawalsByVault: {for (final e in vaults.entries) e.key: Money(e.value)},
                vaultNames: names,
              )
            : null,
        openingInflowRules: rules,
      );
    }

    test('Sem escolha para o resgate: o excedente é cobrado inteiro (como antes)', () {
      final legacy = compute(395958, withInflows: false);
      final s = compute(395958);
      expect(totalDue(s), 200000 + withdrawal);
      expect(due(s, 'ana'), due(legacy, 'ana'));
      expect(due(s, 'bia'), due(legacy, 'bia'));
      // Escolher só a sobra não muda o resgate
      final other = compute(395958, rules: const OpeningInflowRules(rolledSurplus: OpeningBalanceRule.reduceQuotas));
      expect(totalDue(other), 200000 + withdrawal);
    });

    test('Resgate como folga (keep): o excedente continua com os moradores', () {
      final s = compute(395958, rules: const OpeningInflowRules(vaultWithdrawals: OpeningBalanceRule.keep));
      expect(totalDue(s), 200000 + withdrawal);
    });

    test('Resgate cobre o excedente: cada um paga só o valor fixo', () {
      final s = compute(395958, rules: const OpeningInflowRules(vaultWithdrawals: OpeningBalanceRule.coverExcess));
      expect(due(s, 'ana'), 120000);
      expect(due(s, 'bia'), 80000);
      expect(s.bucketDeficit.cents, 0);
    });

    test('Resgate abate os aportes: cobre o excedente e o resto reduz o valor fixo', () {
      // Excedente de R$ 1.000 coberto; os R$ 959,58 restantes abatem 60/40
      final s = compute(300000, rules: const OpeningInflowRules(vaultWithdrawals: OpeningBalanceRule.reduceQuotas));
      expect(totalDue(s), 200000 - (withdrawal - 100000));
      expect(due(s, 'ana'), 120000 - 57575);
      expect(due(s, 'bia'), 80000 - 38383);
      final audit = s.auditTrails['ana']!.expenseShares.where((e) => e.expenseId == 'opening_balance');
      expect(audit.single.expenseTitle, 'Resgate da caixinha Reserva da Casa abatido');
    });

    test('Regra por caixinha: só a Reserva cobre o excedente, a Viagem fica no Caixa', () {
      final s = compute(
        445958,
        vaults: const {reserva: withdrawal, viagem: 50000},
        rules: const OpeningInflowRules(
          vaultWithdrawals: OpeningBalanceRule.keep,
          vaultOverrides: {reserva: OpeningBalanceRule.coverExcess},
        ),
      );
      expect(totalDue(s), 200000 + 50000);
      expect(s.bucketDeficit.cents, 50000);
    });

    test('Depósito maior que o resgate na caixinha não vira entrada', () {
      final s = compute(
        395958,
        vaults: const {reserva: -10000},
        rules: const OpeningInflowRules(vaultWithdrawals: OpeningBalanceRule.reduceQuotas),
      );
      expect(totalDue(s), 200000 + 195958);
    });
  });

  group('Divisão por despesa (R\$ 3.000, 50/50) com resgate de R\$ 1.959,58', () {
    const members = [
      HouseMember(id: 'ana', name: 'Ana', defaultSplitPercent: 50),
      HouseMember(id: 'bia', name: 'Bia', defaultSplitPercent: 50),
    ];

    SettlementSummary compute(OpeningInflowRules rules, {int rolled = 0}) => engine.computeSettlement(
          cycle: cycle,
          members: members,
          expenses: [expense('e1', 300000)],
          contributions: const [],
          loans: const [],
          openingBalance: Money(rolled + withdrawal),
          vaultReturns: const Money(withdrawal),
          openingBalanceRule: OpeningBalanceRule.keep,
          openingInflows: OpeningInflows(
            rolledSurplus: Money(rolled),
            vaultWithdrawalsByVault: const {reserva: Money(withdrawal)},
            vaultNames: names,
          ),
          openingInflowRules: rules,
        );

    test('Abater os aportes reduz a parte de cada um; cobrir o excedente não faz nada', () {
      final reduce = compute(const OpeningInflowRules(vaultOverrides: {reserva: OpeningBalanceRule.reduceQuotas}));
      expect(due(reduce, 'ana'), 150000 - 97979);
      expect(due(reduce, 'bia'), 150000 - 97979);
      final cover = compute(const OpeningInflowRules(vaultWithdrawals: OpeningBalanceRule.coverExcess));
      expect(totalDue(cover), 300000);
    });

    test('Sobra com regra própria abate mesmo com a regra antiga em folga', () {
      final s = compute(
        const OpeningInflowRules(rolledSurplus: OpeningBalanceRule.reduceQuotas),
        rolled: 30000,
      );
      expect(due(s, 'ana'), 135000);
      final audit = s.auditTrails['ana']!.expenseShares.where((e) => e.expenseId == 'opening_balance');
      expect(audit.single.expenseTitle, 'Sobra do ciclo anterior abatida');
    });
  });

  group('Planejador e fechamento concordam', () {
    const fixedMembers = [
      HouseMember(id: 'ana', name: 'Ana', defaultFixedAmountCents: 120000),
      HouseMember(id: 'bia', name: 'Bia', defaultFixedAmountCents: 80000),
    ];
    const splitMembers = [
      HouseMember(id: 'ana', name: 'Ana', defaultSplitPercent: 50),
      HouseMember(id: 'bia', name: 'Bia', defaultSplitPercent: 50),
    ];
    const inflows = OpeningInflows(vaultWithdrawalsByVault: {reserva: Money(withdrawal)}, vaultNames: names);

    CycleFundingEstimate plan(List<HouseMember> members, int expenseCents, OpeningInflowRules rules) =>
        estimator.calculateEstimate(
          cycle: cycle,
          members: members,
          categories: const [],
          currentCycleExpenses: [expense('e1', expenseCents)],
          historicalExpenses: const [],
          currentCycleContributions: const [],
          openingBalanceRule: OpeningBalanceRule.coverExcess,
          openingInflows: inflows,
          openingInflowRules: rules,
        );

    SettlementSummary close(List<HouseMember> members, int expenseCents, OpeningInflowRules rules) =>
        engine.computeSettlement(
          cycle: cycle,
          members: members,
          expenses: [expense('e1', expenseCents)],
          contributions: const [],
          loans: const [],
          customContributionTargets: members.first.defaultFixedAmountCents == null
              ? null
              : {for (final m in members) m.id: Money(m.defaultFixedAmountCents!)},
          openingBalance: const Money(withdrawal),
          vaultReturns: const Money(withdrawal),
          openingBalanceRule: OpeningBalanceRule.coverExcess,
          openingInflows: inflows,
          openingInflowRules: rules,
        );

    void expectSame(List<HouseMember> members, int expenseCents, OpeningInflowRules rules) {
      final e = plan(members, expenseCents, rules);
      final s = close(members, expenseCents, rules);
      for (final m in members) {
        expect(
          e.memberQuotes.firstWhere((q) => q.memberId == m.id).recommendedAmount.cents,
          due(s, m.id),
          reason: m.id,
        );
      }
    }

    test('Valor fixo sem excedente, resgate abatendo os aportes', () {
      const rules = OpeningInflowRules(vaultWithdrawals: OpeningBalanceRule.reduceQuotas);
      expectSame(fixedMembers, 200000, rules);
      final e = plan(fixedMembers, 200000, rules);
      expect(e.netFundingRequired.cents, 200000 - withdrawal);
      expect(e.currentHouseBalance.cents, withdrawal);
    });

    test('Divisão por despesa, resgate abatendo ou guardado', () {
      expectSame(splitMembers, 300000, const OpeningInflowRules(vaultWithdrawals: OpeningBalanceRule.reduceQuotas));
      expectSame(splitMembers, 300000, const OpeningInflowRules(vaultWithdrawals: OpeningBalanceRule.keep));
      final kept = plan(splitMembers, 300000, const OpeningInflowRules(vaultWithdrawals: OpeningBalanceRule.keep));
      expect(kept.netFundingRequired.cents, 300000);
      expect(kept.currentHouseBalance.cents, 0);
    });

    test('Cubit: o resgate com regra da casa entra no planejador', () async {
      final dataSource = MockFinanceDataSource();
      final cubit = FinanceCubit(FinanceRepositoryImpl(dataSource));
      await cubit.loadCycleData();
      await dataSource.withdrawFromVault(
        vaultId: 'vault_reserva',
        memberId: 'member_carlos',
        amount: const Money(15000),
        description: 'Reforçar o Caixa do ciclo',
        returnToCycleStart: cubit.state.currentCycle.startDate,
      );
      await cubit.loadCycleData(cycle: cubit.state.currentCycle);
      final before = cubit.state.fundingEstimate!.netFundingRequired.cents;

      final ok = await cubit.updateHouseSettings(
        inflowRules: const OpeningInflowRules(vaultOverrides: {'vault_reserva': OpeningBalanceRule.reduceQuotas}),
      );
      expect(ok, isTrue);
      expect(cubit.state.houseSettings.inflowRules.vaultRule('vault_reserva'), OpeningBalanceRule.reduceQuotas);
      expect(
        (await dataSource.getHouseSettings()).inflowRules.vaultOverrides['vault_reserva'],
        OpeningBalanceRule.reduceQuotas,
      );
      expect(cubit.state.fundingEstimate!.netFundingRequired.cents, before - 15000);
      await cubit.close();
    });
  });

  group('OpeningInflowRules', () {
    test('Lê a coluna da casa, ignora valores estranhos e volta ao mesmo JSON', () {
      final s = HouseSettings.fromJson({
        'opening_balance_rule': 'cover_excess',
        'opening_inflow_rules': {
          'rolled_surplus': 'reduce_quotas',
          'house_loans_repaid': 'nada',
          'vault_withdrawals': 'cover_excess',
          'vault_overrides': {reserva: 'keep', viagem: 'x'},
        },
      });
      final rules = s.inflowRules;
      expect(rules.rolledSurplusRule(s.openingBalanceRule), OpeningBalanceRule.reduceQuotas);
      expect(rules.houseLoansRepaidRule(s.openingBalanceRule), OpeningBalanceRule.coverExcess);
      expect(rules.vaultRule(reserva), OpeningBalanceRule.keep);
      expect(rules.vaultRule(viagem), OpeningBalanceRule.coverExcess);
      // Entrada de fora sem escolha segue a sobra
      expect(rules.thirdPartyRule(s.openingBalanceRule), OpeningBalanceRule.reduceQuotas);
      expect(OpeningInflowRules.fromJson(rules.toJson()), rules);
      expect(rules.toJson().containsKey('house_loans_repaid'), isFalse);
    });

    test('Sem a coluna: tudo como antes e resgate fica no Caixa', () {
      final s = HouseSettings.fromJson({'opening_balance_rule': 'reduce_quotas'});
      expect(s.inflowRules.isEmpty, isTrue);
      expect(s.inflowRules.rolledSurplusRule(s.openingBalanceRule), OpeningBalanceRule.reduceQuotas);
      expect(s.inflowRules.vaultRule(reserva), OpeningBalanceRule.keep);
      expect(HouseSettings.fromJson({'opening_inflow_rules': 'x'}).inflowRules, const OpeningInflowRules());
    });
  });
}
