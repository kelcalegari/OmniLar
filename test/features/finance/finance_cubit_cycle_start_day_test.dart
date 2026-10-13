import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/features/finance/data/datasources/mock_finance_datasource.dart';
import 'package:omni_lar/features/finance/data/repositories/finance_repository_impl.dart';
import 'package:omni_lar/features/finance/domain/services/cycle_funding_estimator.dart';
import 'package:omni_lar/features/finance/presentation/cubit/finance_cubit.dart';

void main() {
  group('FinanceCubit: dia de início do ciclo da casa', () {
    FinanceCubit buildCubit(int? Function() cycleStartDayOf) => FinanceCubit(
          FinanceRepositoryImpl(MockFinanceDataSource()),
          const CycleFundingEstimator(),
          cycleStartDayOf,
        );

    test('sem casa carregada usa o dia padrão', () {
      final cubit = buildCubit(() => null);

      expect(cubit.cycleStartDay, FinanceCubit.defaultCycleStartDay);
      expect(cubit.state.currentCycle.startDate.day, FinanceCubit.defaultCycleStartDay);
    });

    test('realinha o ciclo quando a casa é carregada depois do cubit', () async {
      int? houseDay;
      final cubit = buildCubit(() => houseDay);
      expect(cubit.state.currentCycle.startDate.day, 5);

      houseDay = 9;
      await cubit.loadCycleData();

      final cycle = cubit.state.currentCycle;
      expect(cycle.startDate.day, 9);
      expect(cycle.endDate.day, 8);
      expect(cycle.contains(DateTime.now()), isTrue);
    });

    test('navega entre ciclos no dia de início da casa', () async {
      final cubit = buildCubit(() => 9);
      await cubit.loadCycleData();
      final current = cubit.state.currentCycle;

      cubit.nextCycle();
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.currentCycle.startDate.day, 9);
      expect(cubit.state.currentCycle.startDate.isAfter(current.startDate), isTrue);

      await cubit.loadCycleData(cycle: current);
      cubit.previousCycle();
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.currentCycle.startDate.day, 9);
      expect(cubit.state.currentCycle.endDate.isBefore(current.startDate), isTrue);
    });
  });
}
