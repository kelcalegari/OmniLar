import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/features/finance/data/datasources/mock_finance_datasource.dart';
import 'package:omni_lar/features/finance/data/repositories/finance_repository_impl.dart';
import 'package:omni_lar/features/finance/presentation/cubit/finance_cubit.dart';

void main() {
  group('Modelo de rateio da casa', () {
    test('o modelo "Por categoria" gravado volta ao recarregar', () async {
      final cubit = FinanceCubit(FinanceRepositoryImpl(MockFinanceDataSource()));
      await cubit.loadCycleData();
      expect(cubit.state.splitModel, 'percentage');

      final members = cubit.state.members;
      await cubit.updateHouseSplitModel(
        splitModel: 'category',
        percentages: {for (final m in members) m.id: 100.0 / members.length},
        fixedAmountsCents: {for (final m in members) m.id: 0},
      );

      expect(cubit.state.splitModel, 'category');
      for (final m in cubit.state.members) {
        expect(m.defaultSplitPercent, closeTo(100.0 / members.length, 0.01));
        expect(m.defaultFixedAmountCents ?? 0, 0);
      }
    });

    test('aporte fixo zero pode ser gravado para um morador', () async {
      final cubit = FinanceCubit(FinanceRepositoryImpl(MockFinanceDataSource()));
      await cubit.loadCycleData();
      final members = cubit.state.members;

      await cubit.updateHouseSplitModel(
        splitModel: 'fixed',
        percentages: {members.first.id: 100.0, for (final m in members.skip(1)) m.id: 0.0},
        fixedAmountsCents: {members.first.id: 90000, for (final m in members.skip(1)) m.id: 0},
      );

      expect(cubit.state.splitModel, 'fixed');
      expect(cubit.state.members.first.defaultFixedAmountCents, 90000);
      for (final m in cubit.state.members.skip(1)) {
        expect(m.defaultFixedAmountCents ?? 0, 0);
      }
    });
  });
}
