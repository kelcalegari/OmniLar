import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/features/finance/data/datasources/mock_finance_datasource.dart';
import 'package:omni_lar/features/finance/data/repositories/finance_repository_impl.dart';
import 'package:omni_lar/features/finance/domain/entities/cycle_funding_estimate.dart';
import 'package:omni_lar/features/finance/domain/entities/house_settings.dart';
import 'package:omni_lar/features/finance/presentation/cubit/finance_cubit.dart';

void main() {
  group('FinanceCubit: configurações do planejador guardadas na casa', () {
    test('Modo e ajuste por categoria sobrevivem a uma nova sessão', () async {
      final dataSource = MockFinanceDataSource();
      final cubit = FinanceCubit(FinanceRepositoryImpl(dataSource));
      await cubit.loadCycleData();

      cubit.updateFundingEstimateMode(FundingEstimateMode.comfortable);
      cubit.updateCustomCategoryFunding('cat_mercado', const Money(77700));
      await Future<void>.delayed(Duration.zero);
      await cubit.close();

      // Outro aparelho (ou o app reaberto) lê o que ficou gravado
      final reopened = FinanceCubit(FinanceRepositoryImpl(dataSource));
      await reopened.loadCycleData();
      expect(reopened.state.fundingEstimateMode, FundingEstimateMode.comfortable);
      expect(reopened.state.customCategoryOverrides['cat_mercado']?.cents, 77700);

      reopened.updateCustomCategoryFunding('cat_mercado', null);
      await Future<void>.delayed(Duration.zero);
      expect(reopened.state.customCategoryOverrides.containsKey('cat_mercado'), isFalse);
      expect((await dataSource.getHouseSettings()).categoryOverrides, isEmpty);
      await reopened.close();
    });

    test('Ajustes da casa gravam a regra da sobra e os ciclos da média', () async {
      final dataSource = MockFinanceDataSource();
      final cubit = FinanceCubit(FinanceRepositoryImpl(dataSource));
      await cubit.loadCycleData();

      final ok = await cubit.updateHouseSettings(
        openingBalanceRule: OpeningBalanceRule.keep,
        historyCycles: 6,
        adjustPercent: 15,
      );

      expect(ok, isTrue);
      expect(cubit.state.houseSettings.openingBalanceRule, OpeningBalanceRule.keep);
      expect(cubit.state.houseSettings.historyCycles, 6);
      expect(cubit.state.houseSettings.adjustPercent, 15);
      await cubit.close();
    });
  });
}
