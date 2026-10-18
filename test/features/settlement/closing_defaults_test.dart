import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/domain/value_objects/financial_cycle.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/features/finance/data/datasources/mock_finance_datasource.dart';
import 'package:omni_lar/features/finance/data/repositories/finance_repository_impl.dart';
import 'package:omni_lar/features/finance/domain/entities/closing_defaults.dart';
import 'package:omni_lar/features/finance/domain/entities/house_settings.dart';
import 'package:omni_lar/features/settlement/domain/entities/settlement_options.dart';
import 'package:omni_lar/features/settlement/domain/entities/settlement_summary.dart';
import 'package:omni_lar/features/settlement/domain/entities/super_pix_transfer.dart';
import 'package:omni_lar/features/settlement/domain/entities/transfer_settlement_resolution.dart';
import 'package:omni_lar/features/settlement/domain/repositories/settlement_repository.dart';
import 'package:omni_lar/features/settlement/presentation/cubit/settlement_cubit.dart';
import 'package:omni_lar/features/settlement/presentation/cubit/settlement_state.dart';

final _cycle = FinancialCycle(start: DateTime(2026, 10, 5), end: DateTime(2026, 11, 4));

const _transfer = SuperPixTransfer(
  id: 't1',
  fromMemberId: 'member_marina',
  fromMemberName: 'Marina',
  toMemberId: 'member_carlos',
  toMemberName: 'Carlos',
  amount: Money(10000),
  description: 'Super Pix',
);

/// Guarda as opções com que o fechamento foi calculado.
class _RecordingSettlementRepository implements SettlementRepository {
  final calculatedWith = <SettlementOptions?>[];
  int confirmCalls = 0;

  @override
  Future<SettlementSummary> getSettlementSummary(FinancialCycle cycle, {SettlementOptions? options}) async {
    calculatedWith.add(options);
    return SettlementSummary(
      cycle: cycle,
      memberBalances: const [],
      transfers: const [_transfer],
      totalHouseExpenses: const Money.zero(),
      totalContributions: const Money.zero(),
      totalP2PCleared: const Money(10000),
      houseTreasuryBalance: const Money.zero(),
    );
  }

  @override
  Future<void> confirmSettlement(SettlementSummary summary, {SettlementOptions? options}) async {
    confirmCalls++;
  }

  @override
  Future<void> markTransferSent(String recordId) async {}

  @override
  Future<void> reopenSettlement(FinancialCycle cycle) async {}

  @override
  Future<bool> isCycleSettled(FinancialCycle cycle) async => false;
}

void main() {
  group('HouseSettings: padrões do fechamento (0094)', () {
    test('Lê e grava o objeto closing_defaults', () {
      final settings = HouseSettings.fromJson({
        'closing_defaults': {
          'surplus_action': 'refund',
          'surplus_vault_id': 'vault_viagem',
          'deficit_split': 'equal',
          'deficit_vault_id': 'vault_reserva',
          'shortfall_action': 'rollover_pending',
        },
      });
      final defaults = settings.closingDefaults;
      expect(defaults.surplusAction, SurplusAction.refund);
      expect(defaults.surplusVaultId, 'vault_viagem');
      expect(defaults.deficitSplit, DeficitSplit.equal);
      expect(defaults.deficitVaultId, 'vault_reserva');
      expect(defaults.shortfallAction, ShortfallAction.rolloverPending);
      expect(defaults.toJson(), {
        'surplus_action': 'refund',
        'surplus_vault_id': 'vault_viagem',
        'deficit_split': 'equal',
        'deficit_vault_id': 'vault_reserva',
        'shortfall_action': 'rollover_pending',
      });
      expect(ClosingDefaults.fromJson(defaults.toJson()), defaults);
    });

    test('Sem coluna, vazio ou com valores estranhos, fica sem escolha', () {
      expect(HouseSettings.fromJson({}).closingDefaults.isEmpty, isTrue);
      expect(HouseSettings.fromJson({'closing_defaults': {}}).closingDefaults.isEmpty, isTrue);
      expect(HouseSettings.fromJson({'closing_defaults': 'x'}).closingDefaults.isEmpty, isTrue);
      final odd = ClosingDefaults.fromJson({'surplus_action': 'burn', 'deficit_vault_id': '', 'deficit_split': 3});
      expect(odd.isEmpty, isTrue);
      expect(const ClosingDefaults().toJson(), isEmpty);
      for (final action in SurplusAction.values) {
        expect(ClosingDefaults.surplusActionFromDb(ClosingDefaults.surplusActionToDb(action)), action);
      }
      for (final action in ShortfallAction.values) {
        expect(ClosingDefaults.shortfallActionFromDb(ClosingDefaults.shortfallActionToDb(action)), action);
      }
    });
  });

  group('Fechamento abre com os padrões da casa', () {
    late MockFinanceDataSource finance;
    late _RecordingSettlementRepository repo;

    setUp(() {
      finance = MockFinanceDataSource();
      repo = _RecordingSettlementRepository();
    });

    test('Sem padrões, nada muda: primeira caixinha, proporcional e sem caixinha no excedente', () async {
      final cubit = SettlementCubit(repo, FinanceRepositoryImpl(finance));
      await cubit.loadSettlement(_cycle);

      expect(repo.calculatedWith.single, const SettlementOptions());
      expect(cubit.state.options, const SettlementOptions(targetVaultId: 'vault_reserva'));
      expect(cubit.state.closingDefaults.isEmpty, isTrue);
      await cubit.close();
    });

    test('Já calcula com os padrões e abre com eles marcados', () async {
      await finance.updateHouseSettings({
        'closing_defaults': const ClosingDefaults(
          surplusAction: SurplusAction.refund,
          surplusVaultId: 'vault_viagem',
          deficitSplit: DeficitSplit.equal,
          deficitVaultId: 'vault_reforma',
          shortfallAction: ShortfallAction.forgiveRemainder,
        ).toJson(),
      });
      final cubit = SettlementCubit(repo, FinanceRepositoryImpl(finance));
      await cubit.loadSettlement(_cycle);

      // Devolver a sobra e a caixinha do excedente pesam no primeiro cálculo
      final first = repo.calculatedWith.single!;
      expect(first.surplusAction, SurplusAction.refund);
      expect(first.deficitSplit, DeficitSplit.equal);
      expect(first.deficitVaultId, 'vault_reforma');
      expect(cubit.state.options.targetVaultId, 'vault_viagem');
      expect(cubit.state.closingDefaults.shortfallAction, ShortfallAction.forgiveRemainder);

      // Quem fecha ainda muda naquele ciclo, e trocar de ciclo não volta ao padrão
      await cubit.updateDeficitSplit(DeficitSplit.proportional);
      await cubit.loadSettlement(_cycle);
      expect(cubit.state.options.deficitSplit, DeficitSplit.proportional);
      await cubit.close();
    });

    test('Caixinha guardada como padrão que não existe mais é ignorada', () async {
      await finance.updateHouseSettings({
        'closing_defaults': {
          'surplus_action': 'to_vault',
          'surplus_vault_id': 'vault_apagada',
          'deficit_vault_id': 'vault_apagada',
        },
      });
      final cubit = SettlementCubit(repo, FinanceRepositoryImpl(finance));
      await cubit.loadSettlement(_cycle);

      expect(repo.calculatedWith.single!.deficitVaultId, isNull);
      expect(cubit.state.options.targetVaultId, 'vault_reserva');
      expect(cubit.state.status, SettlementCubitStatus.loaded);
      await cubit.close();
    });

    test('Lembrar como padrão grava as escolhas ao confirmar', () async {
      final cubit = SettlementCubit(repo, FinanceRepositoryImpl(finance));
      await cubit.loadSettlement(_cycle);
      cubit.updateSurplusAction(SurplusAction.rollover);
      await cubit.updateDeficitVault('vault_viagem');
      cubit.updateTransferResolution(const TransferSettlementResolution(
        transferId: 't1',
        amountExpected: Money(10000),
        amountPaid: Money(4000),
        shortfallAction: ShortfallAction.rolloverPending,
      ));

      await cubit.confirmSettlement(rememberAsHouseDefaults: true);

      expect(repo.confirmCalls, 1);
      expect(cubit.state.status, SettlementCubitStatus.settled);
      final saved = (await finance.getHouseSettings()).closingDefaults;
      expect(saved.surplusAction, SurplusAction.rollover);
      expect(saved.surplusVaultId, isNull);
      expect(saved.deficitSplit, DeficitSplit.proportional);
      expect(saved.deficitVaultId, 'vault_viagem');
      expect(saved.shortfallAction, ShortfallAction.rolloverPending);
      expect(cubit.state.closingDefaults, saved);
      await cubit.close();
    });

    test('Sem lembrar, os padrões da casa não mudam', () async {
      final cubit = SettlementCubit(repo, FinanceRepositoryImpl(finance));
      await cubit.loadSettlement(_cycle);
      cubit.updateSurplusAction(SurplusAction.rollover);

      await cubit.confirmSettlement();

      expect((await finance.getHouseSettings()).closingDefaults.isEmpty, isTrue);
      await cubit.close();
    });
  });
}
