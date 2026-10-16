import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:omni_lar/core/di/service_locator.dart';
import 'package:omni_lar/core/domain/value_objects/financial_cycle.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/core/errors/failures.dart';
import 'package:omni_lar/features/finance/data/datasources/mock_finance_datasource.dart';
import 'package:omni_lar/features/auth/presentation/cubit/auth_cubit.dart';
import 'package:omni_lar/features/finance/domain/entities/savings_vault.dart';
import 'package:omni_lar/features/finance/presentation/cubit/finance_cubit.dart';
import 'package:omni_lar/features/finance/presentation/pages/savings_vaults_page.dart';

void main() {
  setUpAll(() async {
    if (!sl.isRegistered<FinanceCubit>()) {
      await initServiceLocator();
    }
  });

  group('SavingsVaults & Metas da Casa - Regras de Domínio', () {
    test('Calcula porcentagem de progresso e meta atingida corretamente', () {
      final vault = SavingsVault(
        id: 'v1',
        name: 'Reserva de Emergência',
        targetAmount: const Money(500000), // R$ 5.000,00
        currentBalance: const Money(250000), // R$ 2.500,00
        createdAt: DateTime.now(),
      );

      expect(vault.progressPercent, 0.5);
      expect(vault.isGoalReached, isFalse);

      final reachedVault = vault.copyWith(currentBalance: const Money(500000));
      expect(reachedVault.progressPercent, 1.0);
      expect(reachedVault.isGoalReached, isTrue);

      final overVault = vault.copyWith(currentBalance: const Money(600000));
      expect(overVault.progressPercent, 1.0);
      expect(overVault.isGoalReached, isTrue);
    });

    test('Depósito e Resgate alteram o saldo acumulado da caixinha no Cubit', () async {
      final cubit = sl<FinanceCubit>();
      await cubit.loadCycleData();

      final initialVaults = cubit.state.savingsVaults;
      expect(initialVaults, isNotEmpty);

      final targetVault = initialVaults.first;
      final initialBalance = targetVault.currentBalance;

      // Realiza depósito de R$ 200,00
      await cubit.depositToVault(
        vaultId: targetVault.id,
        memberId: 'member_carlos',
        amount: const Money(20000),
        description: 'Aporte de teste',
      );

      final updatedVault = cubit.state.savingsVaults.firstWhere((v) => v.id == targetVault.id);
      expect(updatedVault.currentBalance, initialBalance + const Money(20000));

      // Realiza resgate de R$ 100,00
      await cubit.withdrawFromVault(
        vaultId: targetVault.id,
        memberId: 'member_carlos',
        amount: const Money(10000),
        description: 'Resgate de teste',
      );

      final finalVault = cubit.state.savingsVaults.firstWhere((v) => v.id == targetVault.id);
      expect(finalVault.currentBalance, updatedVault.currentBalance - const Money(10000));
    });
  });

  group('Resgate devolvido ao ciclo', () {
    final cycle = FinancialCycle.fromDate(date: DateTime.now(), cycleStartDay: 1);

    test('Só sacar não mexe no Caixa do ciclo', () async {
      final ds = MockFinanceDataSource();
      final before = await ds.getCycleSummary(cycle);

      await ds.withdrawFromVault(
        vaultId: 'vault_reserva',
        memberId: 'member_carlos',
        amount: const Money(10000),
        description: 'Conserto',
      );

      expect(await ds.getVaultReturnsForCycle(cycle), const Money.zero());
      expect((await ds.getCycleSummary(cycle)).folego, before.folego);
      final history = await ds.getVaultTransactions('vault_reserva');
      expect(history.first.returnedToCycle, isFalse);
    });

    test('Devolver ao ciclo soma o valor ao dinheiro da casa no Caixa', () async {
      final ds = MockFinanceDataSource();
      final before = await ds.getCycleSummary(cycle);

      await ds.withdrawFromVault(
        vaultId: 'vault_reserva',
        memberId: 'member_carlos',
        amount: const Money(15000),
        description: 'Reforçar o Caixa do ciclo',
        returnToCycleStart: cycle.startDate,
      );

      expect(await ds.getVaultReturnsForCycle(cycle), const Money(15000));
      expect(await ds.getOpeningBalance(cycle), const Money(15000));
      final after = await ds.getCycleSummary(cycle);
      expect(after.folego, before.folego + const Money(15000));
      // Não vira aporte de ninguém
      expect(after.totalContributions, before.totalContributions);

      final history = await ds.getVaultTransactions('vault_reserva');
      expect(history.first.returnedToCycle, isTrue);
      expect(history.first.description, 'Reforçar o Caixa do ciclo');

      // Outro ciclo não recebe o valor
      expect(await ds.getVaultReturnsForCycle(cycle.next(1)), const Money.zero());
    });

    test('Resgate sem motivo é recusado e não mexe no saldo', () async {
      final ds = MockFinanceDataSource();
      final balance = (await ds.getSavingsVaults()).firstWhere((v) => v.id == 'vault_reserva').currentBalance;

      await expectLater(
        ds.withdrawFromVault(
          vaultId: 'vault_reserva',
          memberId: 'member_carlos',
          amount: const Money(10000),
          description: '   ',
        ),
        throwsA(isA<ServerFailure>()),
      );
      expect(
        (await ds.getSavingsVaults()).firstWhere((v) => v.id == 'vault_reserva').currentBalance,
        balance,
      );
    });
  });

  group('SavingsVaultsPage - Widget Test', () {
    Widget buildTestWidget() {
      return MultiBlocProvider(
        providers: [
          BlocProvider<AuthCubit>.value(value: sl<AuthCubit>()),
          BlocProvider<FinanceCubit>.value(value: sl<FinanceCubit>()),
        ],
        child: const MaterialApp(
          home: SavingsVaultsPage(),
        ),
      );
    }

    testWidgets('Renderiza total guardado, lista de caixinhas e botões de ação', (tester) async {
      await sl<FinanceCubit>().loadCycleData();

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Caixinhas & Metas da Casa'), findsOneWidget);
      expect(find.text('Total Guardado na Casa'), findsOneWidget);
      expect(find.text('Nova Caixinha'), findsOneWidget);
      expect(find.text('Reserva de Emergência da Casa'), findsOneWidget);
      expect(find.text('Viagem de Férias do Casal'), findsOneWidget);
      expect(find.text('Guardar'), findsWidgets);
      expect(find.text('Resgatar'), findsWidgets);
    });

    testWidgets('Abre diálogo para guardar dinheiro na caixinha', (tester) async {
      await sl<FinanceCubit>().loadCycleData();

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Clica no primeiro botão Guardar
      await tester.tap(find.text('Guardar').first);
      await tester.pumpAndSettle();

      expect(find.textContaining('Guardar em:'), findsOneWidget);
      expect(find.text('Quem está guardando?'), findsOneWidget);
      expect(find.text('Valor a Guardar:'), findsOneWidget);
      expect(find.text('Confirmar e Guardar'), findsOneWidget);

      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
    });

    testWidgets('Resgate pede o motivo e oferece devolver ao ciclo', (tester) async {
      await sl<FinanceCubit>().loadCycleData();

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Resgatar').first);
      await tester.pumpAndSettle();

      expect(find.text('Só sacar'), findsOneWidget);
      expect(find.text('Devolver ao ciclo'), findsOneWidget);

      // Sem motivo o resgate não sai
      await tester.tap(find.text('Confirmar Resgate'));
      await tester.pumpAndSettle();
      expect(find.text('Informe o motivo do resgate'), findsOneWidget);

      await tester.tap(find.text('Devolver ao ciclo'));
      await tester.pumpAndSettle();
      expect(find.textContaining('entra no Caixa do ciclo'), findsOneWidget);

      await tester.ensureVisible(find.text('Conserto'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Conserto'));
      await tester.pumpAndSettle();
      expect(find.text('Informe o motivo do resgate'), findsNothing);

      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
    });
  });
}
