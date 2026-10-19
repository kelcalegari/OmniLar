import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/domain/value_objects/financial_cycle.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/features/finance/data/datasources/mock_finance_datasource.dart';
import 'package:omni_lar/features/finance/data/repositories/finance_repository_impl.dart';
import 'package:omni_lar/features/finance/domain/entities/category.dart';
import 'package:omni_lar/features/finance/domain/entities/house_expense.dart';
import 'package:omni_lar/features/finance/domain/entities/house_member.dart';
import 'package:omni_lar/features/finance/domain/entities/house_settings.dart';
import 'package:omni_lar/features/finance/domain/entities/income_split.dart';
import 'package:omni_lar/features/finance/domain/entities/savings_vault.dart';
import 'package:omni_lar/features/finance/domain/entities/split_rule.dart';
import 'package:omni_lar/features/finance/domain/services/cycle_funding_estimator.dart';
import 'package:omni_lar/features/finance/presentation/cubit/finance_cubit.dart';

void main() {
  group('Divisão proporcional à renda', () {
    test('percentuais proporcionais somando exatamente 100', () {
      final split = IncomeSplit.compute({'a': 300000, 'b': 100000}, ['a', 'b'])!;
      expect(split, {'a': 75.0, 'b': 25.0});

      final thirds = IncomeSplit.compute({'a': 100000, 'b': 100000, 'c': 100000}, ['a', 'b', 'c'])!;
      expect(thirds.values.fold<double>(0, (a, b) => a + b), closeTo(100, 1e-9));
      // A sobra do arredondamento vai a quem ganha mais; no empate, ao primeiro
      expect(thirds['a'], 33.34);
    });

    test('sem renda de todos os moradores, cai no rateio atual (nulo)', () {
      expect(IncomeSplit.compute({'a': 300000}, ['a', 'b']), isNull);
      expect(IncomeSplit.compute({'a': 300000, 'b': 0}, ['a', 'b']), isNull);
      expect(IncomeSplit.compute({}, ['a', 'b']), isNull);
      expect(IncomeSplit.compute({'a': 1}, const []), isNull);
    });

    test('rendas de quem saiu da casa não entram', () {
      final split = IncomeSplit.compute({'a': 100000, 'b': 100000, 'x': 900000}, ['a', 'b'])!;
      expect(split, {'a': 50.0, 'b': 50.0});
    });
  });

  group('Visibilidade da renda', () {
    const all = {'me': 100, 'other': 200, 'admin': 300};

    test('padrão da casa é cada um ver só a sua', () {
      expect(const HouseSettings().incomeVisibility, IncomeVisibility.self);
      expect(IncomeVisibility.fromDb('qualquer'), IncomeVisibility.self);
      expect(const HouseSettings().splitBasis, SplitBasis.manual);
    });

    test('self: nem administrador lê a renda dos outros', () {
      for (final isAdmin in [true, false]) {
        final seen = IncomeSplit.visibleTo(
          all: all,
          viewerId: 'me',
          viewerIsAdmin: isAdmin,
          visibility: IncomeVisibility.self,
        );
        expect(seen, {'me': 100});
      }
    });

    test('admins: administrador lê todas; morador comum só a própria', () {
      expect(
        IncomeSplit.visibleTo(all: all, viewerId: 'admin', viewerIsAdmin: true, visibility: IncomeVisibility.admins),
        all,
      );
      expect(
        IncomeSplit.visibleTo(all: all, viewerId: 'me', viewerIsAdmin: false, visibility: IncomeVisibility.admins),
        {'me': 100},
      );
    });

    test('all: todos leem todas', () {
      expect(
        IncomeSplit.visibleTo(all: all, viewerId: 'me', viewerIsAdmin: false, visibility: IncomeVisibility.all),
        all,
      );
    });

    test('configurações da casa leem os campos novos do banco', () {
      final settings = HouseSettings.fromJson({'income_visibility': 'admins', 'split_basis': 'income'});
      expect(settings.incomeVisibility, IncomeVisibility.admins);
      expect(settings.splitBasis, SplitBasis.income);
    });
  });

  group('Renda no app (a renda não vaza)', () {
    late MockFinanceDataSource source;
    late FinanceCubit cubit;

    setUp(() {
      source = MockFinanceDataSource();
      cubit = FinanceCubit(FinanceRepositoryImpl(source));
    });

    tearDown(() => cubit.close());

    test('visibilidade self: o app guarda só a própria renda', () async {
      source.viewerId = 'member_marina';
      await source.setMyIncome(const Money(400000));
      source.viewerId = 'member_carlos';
      expect(await cubit.setMyIncome(const Money(600000)), isTrue);

      expect(cubit.state.memberIncomes, {'member_carlos': const Money(600000)});
      expect(cubit.state.memberIncomes.containsKey('member_marina'), isFalse);

      // Marina também só vê a dela
      source.viewerId = 'member_marina';
      expect(await source.getMemberIncomes(), {'member_marina': const Money(400000)});
    });

    test('visibilidade all: o app mostra a renda de todos', () async {
      source.viewerId = 'member_marina';
      await source.setMyIncome(const Money(400000));
      source.viewerId = 'member_carlos';
      await cubit.updateHouseSettings(incomeVisibility: IncomeVisibility.all);
      await cubit.setMyIncome(const Money(600000));

      expect(cubit.state.memberIncomes, {
        'member_carlos': const Money(600000),
        'member_marina': const Money(400000),
      });
    });

    test('renda inválida é recusada e limpar remove', () async {
      expect(await cubit.setMyIncome(const Money(0)), isFalse);
      await cubit.setMyIncome(const Money(500000));
      expect(cubit.state.memberIncomes, isNotEmpty);
      await cubit.setMyIncome(null);
      expect(cubit.state.memberIncomes, isEmpty);
    });

    test('base renda: com todas as rendas, os percentuais seguem a renda', () async {
      source.viewerId = 'member_marina';
      await source.setMyIncome(const Money(100000));
      source.viewerId = 'member_carlos';
      await cubit.setMyIncome(const Money(300000));
      // Ainda à mão: nada muda
      expect(cubit.state.members.map((m) => m.defaultSplitPercent), [60.0, 40.0]);

      expect(await cubit.updateHouseSettings(splitBasis: SplitBasis.income), isTrue);
      expect(cubit.state.houseSettings.splitBasis, SplitBasis.income);
      expect(cubit.state.members.map((m) => m.defaultSplitPercent), [75.0, 25.0]);
    });

    test('base renda sem a renda de todos mantém o rateio atual', () async {
      await cubit.setMyIncome(const Money(300000));
      await cubit.updateHouseSettings(splitBasis: SplitBasis.income);
      expect(cubit.state.members.map((m) => m.defaultSplitPercent), [60.0, 40.0]);
    });
  });

  group('Meta da caixinha dentro da cota', () {
    final today = DateTime(2026, 10, 19);
    SavingsVault vault({
      bool inQuota = false,
      Money? monthly,
      int target = 120000,
      int balance = 0,
      DateTime? deadline,
    }) =>
        SavingsVault(
          id: 'v',
          name: 'Férias',
          targetAmount: Money(target),
          currentBalance: Money(balance),
          createdAt: DateTime(2026, 1, 1),
          targetDate: deadline,
          monthlyGoal: monthly,
          countsInQuota: inQuota,
        );

    test('padrão: não entra na cota', () {
      expect(vault(monthly: const Money(10000)).quotaContribution(today), const Money.zero());
      expect(vault().countsInQuota, isFalse);
    });

    test('marcada: soma a meta mensal; sem ela, o quanto guardar até o prazo', () {
      expect(vault(inQuota: true, monthly: const Money(10000)).quotaContribution(today), const Money(10000));
      // R$ 1.200 em 12 meses (out/2026 a set/2027)
      expect(
        vault(inQuota: true, deadline: DateTime(2027, 9, 30)).quotaContribution(today),
        const Money(10000),
      );
      expect(vault(inQuota: true).quotaContribution(today), const Money.zero());
    });

    test('meta atingida ou quase: não soma mais do que falta', () {
      expect(vault(inQuota: true, monthly: const Money(10000), balance: 120000).quotaContribution(today), const Money.zero());
      expect(vault(inQuota: true, monthly: const Money(10000), balance: 115000).quotaContribution(today), const Money(5000));
    });

    test('copyWith guarda os campos', () {
      final v = vault().copyWith(countsInQuota: true, monthlyGoal: const Money(500));
      expect(v.countsInQuota, isTrue);
      expect(v.monthlyGoal, const Money(500));
      expect(v.copyWith(clearMonthlyGoal: true).monthlyGoal, isNull);
    });

    group('Planejador de aportes', () {
      const estimator = CycleFundingEstimator();
      final cycle = FinancialCycle.fromDate(date: today, cycleStartDay: 7);
      const members = [
        HouseMember(id: 'ana', name: 'Ana', defaultSplitPercent: 50),
        HouseMember(id: 'bia', name: 'Bia', defaultSplitPercent: 50),
      ];
      final bill = HouseExpense(
        id: 'e1',
        title: 'Aluguel',
        amount: const Money(200000),
        date: DateTime(2026, 10, 10),
        categoryId: 'c',
        paidByMemberId: 'ana',
        paymentMethodId: 'pm_caixa',
        splitRule: const SplitRule.percentage(null),
      );

      dynamic estimate(List<SavingsVault> vaults) => estimator.calculateEstimate(
            cycle: cycle,
            members: members,
            categories: const <ExpenseCategory>[],
            currentCycleExpenses: [bill],
            historicalExpenses: const [],
            currentCycleContributions: const [],
            vaults: vaults,
            today: today,
          );

      test('sem caixinha marcada o planejador é o de sempre', () {
        final base = estimate(const []);
        final unmarked = estimate([vault(monthly: const Money(10000))]);
        expect(unmarked.totalProjectedExpenses, base.totalProjectedExpenses);
        expect(unmarked.vaultGoalsInQuota, const Money.zero());
        expect(unmarked.memberQuotes[0].recommendedAmount, const Money(100000));
      });

      test('só as marcadas somam à cota, dividida pelo rateio padrão', () {
        final e = estimate([
          vault(inQuota: true, monthly: const Money(10000)),
          vault(monthly: const Money(99999)),
        ]);
        expect(e.vaultGoalsInQuota, const Money(10000));
        expect(e.totalProjectedExpenses, const Money(210000));
        expect(e.netFundingRequired, const Money(210000));
        expect(e.memberQuotes[0].recommendedAmount, const Money(105000));
        expect(e.memberQuotes[1].recommendedAmount, const Money(105000));
      });
    });
  });

  group('Migration 0102', () {
    final sql = File('supabase/migrations/20261018220000_0102_income_split_vault_goal.sql').readAsStringSync();

    test('impõe a visibilidade no banco e não usa drop trigger', () {
      expect(sql, contains('create policy "member_incomes_select"'));
      expect(sql, contains('can_view_member_incomes'));
      expect(sql, contains('revoke insert, update, delete on public.member_incomes'));
      expect(sql, contains("default 'self'"));
      expect(sql.toLowerCase(), isNot(contains('drop trigger')));
      expect(sql, contains('create or replace trigger trg_savings_vaults_guard_quota'));
    });

    test('update_house_settings mantém todos os campos da 0101', () {
      final previous = File('supabase/migrations/20261018210000_0101_house_labels_shopping.sql').readAsStringSync();
      final keys = RegExp(r"'([a-z_]+)', v_row\.").allMatches(previous).map((m) => m.group(1)!);
      for (final key in keys) {
        expect(sql, contains("'$key', v_row."), reason: key);
      }
      expect(sql, contains("'income_visibility', v_row."));
      expect(sql, contains("'split_basis', v_row."));
    });
  });
}
