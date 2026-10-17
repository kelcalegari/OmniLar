import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/features/finance/data/datasources/mock_finance_datasource.dart';
import 'package:omni_lar/features/finance/data/repositories/finance_repository_impl.dart';
import 'package:omni_lar/features/finance/presentation/cubit/finance_cubit.dart';

/// Casa demo que começou no ciclo em andamento.
class _NewHouseDataSource extends MockFinanceDataSource {
  @override
  Future<DateTime?> getHouseStartDate() async => DateTime.now();
}

void main() {
  group('FinanceCubit: primeiro ciclo da casa', () {
    test('Não volta para antes do primeiro ciclo', () async {
      final cubit = FinanceCubit(FinanceRepositoryImpl(_NewHouseDataSource()));
      await cubit.loadCycleData();
      final current = cubit.state.currentCycle;

      expect(cubit.firstCycle, current);
      expect(cubit.canGoToPreviousCycle, isFalse);
      cubit.previousCycle();
      expect(cubit.state.currentCycle, current);
      await cubit.close();
    });

    test('Ciclo pedido de antes da casa abre o primeiro ciclo', () async {
      final cubit = FinanceCubit(FinanceRepositoryImpl(_NewHouseDataSource()));
      await cubit.loadCycleData();
      final current = cubit.state.currentCycle;
      final old = cubit.cycleSchedule.previous(cubit.cycleSchedule.previous(current));

      expect(cubit.isBeforeFirstCycle(old), isTrue);
      await cubit.loadCycleData(cycle: old);
      expect(cubit.state.currentCycle, current);
      await cubit.close();
    });

    test('Lançamento antigo da casa demo libera os ciclos até ele', () async {
      final cubit = FinanceCubit(FinanceRepositoryImpl(MockFinanceDataSource()));
      await cubit.loadCycleData();
      final first = cubit.firstCycle;

      expect(first, isNotNull);
      expect(cubit.canGoBackFrom(first!), isFalse);
      expect(cubit.isBeforeFirstCycle(first), isFalse);
      await cubit.close();
    });
  });
}
