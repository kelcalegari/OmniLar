import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/domain/value_objects/financial_cycle.dart';
import 'package:omni_lar/features/finance/data/datasources/mock_finance_datasource.dart';
import 'package:omni_lar/features/finance/data/repositories/finance_repository_impl.dart';
import 'package:omni_lar/features/finance/domain/entities/contribution.dart';
import 'package:omni_lar/features/finance/domain/entities/financial_cycle_summary.dart';
import 'package:omni_lar/features/finance/domain/entities/house_expense.dart';
import 'package:omni_lar/features/finance/presentation/cubit/finance_cubit.dart';
import 'package:omni_lar/features/finance/presentation/cubit/finance_state.dart';

/// Fonte de demonstração em que o resumo de um ciclo escolhido demora a chegar.
class _SlowCycleDataSource extends MockFinanceDataSource {
  FinancialCycle? slowCycle;
  final release = Completer<void>();

  @override
  Future<FinancialCycleSummary> getCycleSummary(
    FinancialCycle cycle, {
    List<HouseExpense>? expenses,
    List<Contribution>? contributions,
  }) async {
    if (cycle == slowCycle) await release.future;
    return super.getCycleSummary(cycle, expenses: expenses, contributions: contributions);
  }
}

/// Fonte de demonstração que conta as leituras de despesas, aportes e início da casa.
class _CountingDataSource extends MockFinanceDataSource {
  final expenseReads = <FinancialCycle>[];
  int contributionReads = 0;
  int startDateReads = 0;

  @override
  Future<List<HouseExpense>> getExpensesForCycle(FinancialCycle cycle) {
    expenseReads.add(cycle);
    return super.getExpensesForCycle(cycle);
  }

  @override
  Future<List<Contribution>> getContributionsForCycle(FinancialCycle cycle) {
    contributionReads++;
    return super.getContributionsForCycle(cycle);
  }

  @override
  Future<DateTime?> getHouseStartDate() {
    startDateReads++;
    return super.getHouseStartDate();
  }
}

void main() {
  test('Carregar um ciclo lê despesas e aportes uma vez só', () async {
    final ds = _CountingDataSource();
    final cubit = FinanceCubit(FinanceRepositoryImpl(ds));
    await cubit.loadCycleData();
    final current = cubit.state.currentCycle;

    // O ciclo e o anterior (histórico do planejador); o resumo reaproveita
    expect(ds.expenseReads.where((c) => c == current), hasLength(1));
    expect(ds.contributionReads, 1);
    expect(ds.startDateReads, 1);

    // Navegar não relê o início da casa
    await cubit.loadCycleData(cycle: cubit.cycleSchedule.previous(current));
    expect(ds.startDateReads, 1);
    await cubit.close();
  });

  group('FinanceCubit: troca de ciclo', () {
    test('Resposta atrasada de um ciclo não sobrescreve o ciclo pedido depois', () async {
      final ds = _SlowCycleDataSource();
      final cubit = FinanceCubit(FinanceRepositoryImpl(ds));
      await cubit.loadCycleData();
      final current = cubit.state.currentCycle;
      final next = cubit.cycleSchedule.next(current);

      // Vai para o próximo (lento) e volta antes de ele responder
      ds.slowCycle = next;
      final slowLoad = cubit.loadCycleData(cycle: next);
      await cubit.loadCycleData(cycle: current);
      ds.release.complete();
      await slowLoad;

      expect(cubit.state.currentCycle, current);
      expect(cubit.state.summary?.cycle, current);
      expect(cubit.state.status, FinanceStatus.success);
      await cubit.close();
    });

    test('Atalho volta para o ciclo em andamento', () async {
      final cubit = FinanceCubit(FinanceRepositoryImpl(MockFinanceDataSource()));
      await cubit.loadCycleData();
      final current = cubit.state.currentCycle;

      await cubit.loadCycleData(cycle: cubit.cycleSchedule.previous(current));
      await cubit.loadCycleData(
        cycle: cubit.cycleSchedule.previous(cubit.state.currentCycle),
      );
      expect(cubit.state.currentCycle, isNot(current));

      cubit.goToCurrentCycle();
      await cubit.stream.firstWhere((s) => s.status == FinanceStatus.success);

      expect(cubit.state.currentCycle, current);
      expect(cubit.state.currentCycle.contains(DateTime.now()), isTrue);
      await cubit.close();
    });
  });
}
