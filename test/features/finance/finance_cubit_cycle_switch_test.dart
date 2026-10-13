import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/domain/value_objects/financial_cycle.dart';
import 'package:omni_lar/features/finance/data/datasources/mock_finance_datasource.dart';
import 'package:omni_lar/features/finance/data/repositories/finance_repository_impl.dart';
import 'package:omni_lar/features/finance/domain/entities/financial_cycle_summary.dart';
import 'package:omni_lar/features/finance/presentation/cubit/finance_cubit.dart';
import 'package:omni_lar/features/finance/presentation/cubit/finance_state.dart';

/// Fonte de demonstração em que o resumo de um ciclo escolhido demora a chegar.
class _SlowCycleDataSource extends MockFinanceDataSource {
  FinancialCycle? slowCycle;
  final release = Completer<void>();

  @override
  Future<FinancialCycleSummary> getCycleSummary(FinancialCycle cycle) async {
    if (cycle == slowCycle) await release.future;
    return super.getCycleSummary(cycle);
  }
}

void main() {
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
