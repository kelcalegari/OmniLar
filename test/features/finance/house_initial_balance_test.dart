import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/domain/value_objects/financial_cycle.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/core/errors/failures.dart';
import 'package:omni_lar/features/finance/data/datasources/mock_finance_datasource.dart';
import 'package:omni_lar/features/finance/data/repositories/finance_repository_impl.dart';
import 'package:omni_lar/features/finance/domain/entities/house_expense.dart';
import 'package:omni_lar/features/finance/domain/entities/house_initial_balance.dart';
import 'package:omni_lar/features/finance/domain/entities/house_member.dart';
import 'package:omni_lar/features/finance/domain/entities/house_settings.dart';
import 'package:omni_lar/features/finance/domain/entities/opening_inflows.dart';
import 'package:omni_lar/features/finance/domain/entities/split_rule.dart';
import 'package:omni_lar/features/finance/presentation/cubit/finance_cubit.dart';
import 'package:omni_lar/features/settlement/domain/entities/settlement_summary.dart';
import 'package:omni_lar/features/settlement/domain/services/global_clearing_engine.dart';

/// Casa nova: começou no ciclo em andamento.
class _NewHouseDataSource extends MockFinanceDataSource {
  @override
  Future<DateTime?> getHouseStartDate() async => DateTime.now();
}

void main() {
  const engine = GlobalClearingEngine();
  // Casa criada em 17/10, ciclo começa no dia 5
  final firstCycle = FinancialCycle.fromDate(date: DateTime(2026, 10, 17), cycleStartDay: 5);
  final secondCycle = firstCycle.next(5);
  final initial = HouseInitialBalance(
    reserve: const Money(300000),
    cash: const Money(100000),
    cashCycleStart: firstCycle.startDate,
  );

  group('HouseInitialBalance', () {
    test('Saldo na conta é a sobra só do primeiro ciclo e só sem fechamento anterior', () {
      expect(initial.rolledSurplusFor(firstCycle, hasPreviousSettlement: false), const Money(100000));
      expect(initial.rolledSurplusFor(secondCycle, hasPreviousSettlement: false), const Money.zero());
      expect(initial.rolledSurplusFor(firstCycle, hasPreviousSettlement: true), const Money.zero());
      expect(const HouseInitialBalance().rolledSurplusFor(firstCycle, hasPreviousSettlement: false), const Money.zero());
    });

    test('Lê as colunas da casa e ignora valores estranhos', () {
      final read = HouseInitialBalance.fromJson(const {
        'initial_reserve_cents': 300000,
        'initial_cash_cents': 100000,
        'initial_cash_cycle_start': '2026-10-05',
      });
      expect(read, initial);
      expect(HouseInitialBalance.fromJson(null).isEmpty, isTrue);
      final odd = HouseInitialBalance.fromJson(const {'initial_cash_cents': -5, 'initial_cash_cycle_start': 'x'});
      expect(odd.cash, const Money.zero());
      expect(odd.cashCycleStart, isNull);
    });
  });

  group('Fechamento: valor fixo (Ana 1.200, Bia 800), conta de R\$ 2.500, saldo na conta de R\$ 1.000', () {
    const members = [
      HouseMember(id: 'ana', name: 'Ana', defaultFixedAmountCents: 120000),
      HouseMember(id: 'bia', name: 'Bia', defaultFixedAmountCents: 80000),
    ];
    final targets = {for (final m in members) m.id: Money(m.defaultFixedAmountCents!)};

    HouseExpense expense(FinancialCycle cycle) => HouseExpense(
          id: 'e1',
          title: 'Aluguel',
          amount: const Money(250000),
          date: cycle.startDate.add(const Duration(days: 3)),
          categoryId: 'c',
          paidByMemberId: 'ana',
          paymentMethodId: 'pm_caixa',
          splitRule: const SplitRule.percentage(null),
        );

    SettlementSummary close(FinancialCycle cycle, OpeningBalanceRule rule) {
      // Como o datasource: sem fechamento anterior, a sobra do ciclo é o saldo inicial
      final rolled = initial.rolledSurplusFor(cycle, hasPreviousSettlement: false);
      return engine.computeSettlement(
        cycle: cycle,
        members: members,
        expenses: [expense(cycle)],
        contributions: const [],
        loans: const [],
        customContributionTargets: targets,
        openingBalance: rolled,
        openingBalanceRule: rule,
        openingInflows: OpeningInflows(rolledSurplus: rolled),
        openingInflowRules: OpeningInflowRules(rolledSurplus: rule),
      );
    }

    int totalDue(SettlementSummary s) => s.memberBalances.fold<int>(0, (acc, b) => acc + b.contributionDue.cents);
    int due(SettlementSummary s, String id) =>
        s.memberBalances.firstWhere((b) => b.memberId == id).contributionDue.cents;

    test('Guardar como folga: o primeiro ciclo cobra o excedente inteiro', () {
      expect(totalDue(close(firstCycle, OpeningBalanceRule.keep)), 250000);
    });

    test('Cobrir só o excedente: no primeiro ciclo cada um paga só o valor fixo', () {
      final s = close(firstCycle, OpeningBalanceRule.coverExcess);
      expect(due(s, 'ana'), 120000);
      expect(due(s, 'bia'), 80000);
    });

    test('Abater os aportes: cobre o excedente e o resto abate o valor fixo', () {
      expect(totalDue(close(firstCycle, OpeningBalanceRule.reduceQuotas)), 250000 - 100000);
    });

    test('Segundo ciclo: o saldo inicial não entra de novo, com qualquer regra', () {
      for (final rule in OpeningBalanceRule.values) {
        expect(totalDue(close(secondCycle, rule)), 250000, reason: rule.name);
      }
    });
  });

  group('Modo demo', () {
    test('Reserva guardada entra na Reserva sem mexer no Caixa do ciclo; gravar de novo troca o valor', () async {
      final dataSource = MockFinanceDataSource();
      final cycle = FinancialCycle.fromDate(date: DateTime.now(), cycleStartDay: 5);
      final before = (await dataSource.getSavingsVaults()).first;
      Future<List<String>> initialEntries() async => [
            for (final t in await dataSource.getVaultTransactions(before.id))
              if (t.description == 'Saldo inicial da casa') '${t.type}:${t.amount.cents}:${t.cycleStartDate}',
          ];

      await dataSource.setHouseInitialBalance(
        reserve: const Money(50000),
        cash: const Money.zero(),
        cycleStart: cycle.startDate,
      );
      expect((await dataSource.getSavingsVaults()).first.currentBalance.cents, before.currentBalance.cents + 50000);
      expect(await initialEntries(), ['deposit:50000:null']);
      expect(await dataSource.getVaultReturnsForCycle(cycle), const Money.zero());
      expect(await dataSource.getOpeningBalance(cycle), const Money.zero());

      await dataSource.setHouseInitialBalance(
        reserve: const Money(80000),
        cash: const Money.zero(),
        cycleStart: cycle.startDate,
      );
      expect((await dataSource.getSavingsVaults()).first.currentBalance.cents, before.currentBalance.cents + 80000);
      expect(await initialEntries(), ['deposit:80000:null']);

      await dataSource.setHouseInitialBalance(
        reserve: const Money.zero(),
        cash: const Money.zero(),
        cycleStart: cycle.startDate,
      );
      expect((await dataSource.getSavingsVaults()).first.currentBalance, before.currentBalance);
      expect(await initialEntries(), isEmpty);
      expect((await dataSource.getHouseInitialBalance()).isEmpty, isTrue);
    });

    test('Baixar a reserva abaixo do que já saiu dela é recusado', () async {
      final dataSource = MockFinanceDataSource();
      final cycle = FinancialCycle.fromDate(date: DateTime.now(), cycleStartDay: 5);
      final vault = (await dataSource.getSavingsVaults()).first;
      await dataSource.setHouseInitialBalance(
        reserve: const Money(50000),
        cash: const Money.zero(),
        cycleStart: cycle.startDate,
      );
      await dataSource.withdrawFromVault(
        vaultId: vault.id,
        memberId: 'member_carlos',
        amount: Money(vault.currentBalance.cents + 40000),
        description: 'gasto grande',
      );
      await expectLater(
        dataSource.setHouseInitialBalance(reserve: const Money.zero(), cash: const Money.zero(), cycleStart: cycle.startDate),
        throwsA(isA<ServerFailure>()),
      );
    });

    test('Saldo na conta é a sobra do primeiro ciclo, segue a regra da sobra e não volta no segundo', () async {
      final dataSource = MockFinanceDataSource();
      final cycle = FinancialCycle.fromDate(date: DateTime.now(), cycleStartDay: 5);
      await dataSource.setHouseInitialBalance(
        reserve: const Money.zero(),
        cash: const Money(100000),
        cycleStart: cycle.startDate,
      );

      expect((await dataSource.getOpeningInflows(cycle)).rolledSurplus, const Money(100000));
      expect(await dataSource.getOpeningBalance(cycle), const Money(100000));
      expect((await dataSource.getCycleSummary(cycle)).rolledOverBalance, const Money(100000));
      final next = cycle.next(5);
      expect((await dataSource.getOpeningInflows(next)).rolledSurplus, const Money.zero());
      expect(await dataSource.getOpeningBalance(next), const Money.zero());

      // Com fechamento anterior vale a sobra dele
      dataSource.hasSettlementBefore = (_) async => true;
      expect((await dataSource.getOpeningInflows(cycle)).rolledSurplus, const Money.zero());
    });

    test('Cubit: o saldo na conta entra no primeiro ciclo da casa e abate o planejador', () async {
      final dataSource = _NewHouseDataSource();
      final cubit = FinanceCubit(FinanceRepositoryImpl(dataSource));
      await cubit.loadCycleData();
      await cubit.updateHouseSettings(
        inflowRules: const OpeningInflowRules(rolledSurplus: OpeningBalanceRule.reduceQuotas),
      );
      final before = cubit.state.fundingEstimate!.netFundingRequired.cents;
      final vaultBefore = cubit.state.totalSavings;

      final error = await cubit.setHouseInitialBalance(reserve: const Money(30000), cash: const Money(20000));
      expect(error, isNull);
      expect(cubit.state.initialBalance.cash, const Money(20000));
      expect(cubit.state.initialBalance.cashCycleStart, cubit.state.currentCycle.startDate);
      expect(cubit.state.summary!.openingInflows!.rolledSurplus, const Money(20000));
      expect(cubit.state.fundingEstimate!.netFundingRequired.cents, before - 20000);
      expect(cubit.state.totalSavings, vaultBefore + const Money(30000));

      // Editar troca o valor, sem somar
      expect(await cubit.setHouseInitialBalance(reserve: const Money(30000), cash: const Money(5000)), isNull);
      expect(cubit.state.summary!.openingInflows!.rolledSurplus, const Money(5000));
      expect(cubit.state.totalSavings, vaultBefore + const Money(30000));

      // O ciclo seguinte não recebe o saldo inicial
      cubit.nextCycle();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(cubit.state.summary!.openingInflows!.rolledSurplus, const Money.zero());
      await cubit.close();
    });
  });
}
