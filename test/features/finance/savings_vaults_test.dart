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

  group('Prazo da meta', () {
    final created = DateTime(2026, 1, 1);
    SavingsVault vault({int balance = 0, DateTime? deadline}) => SavingsVault(
          id: 'v',
          name: 'Viagem',
          targetAmount: const Money(120000),
          currentBalance: Money(balance),
          createdAt: created,
          targetDate: deadline,
        );

    test('Sem prazo não calcula ritmo', () {
      final v = vault();
      expect(v.monthlyNeeded(DateTime(2026, 3, 1)), isNull);
      expect(v.isBehindPace(DateTime(2026, 3, 1)), isFalse);
    });

    test('Divide o que falta pelos meses até o prazo, contando o mês atual', () {
      final v = vault(balance: 20000, deadline: DateTime(2026, 12, 31));
      // Faltam R$ 1.000,00 em 10 meses (março a dezembro)
      expect(v.monthlyNeeded(DateTime(2026, 3, 10)), const Money(10000));
    });

    test('Ritmo abaixo quando o saldo está atrás da linha reta até o prazo', () {
      final deadline = DateTime(2026, 12, 31);
      final today = DateTime(2026, 7, 1); // metade do caminho
      expect(vault(balance: 30000, deadline: deadline).isBehindPace(today), isTrue);
      expect(vault(balance: 70000, deadline: deadline).isBehindPace(today), isFalse);
    });

    test('Prazo vencido sem a meta conta como atrasado; meta atingida não', () {
      final deadline = DateTime(2026, 6, 30);
      final after = DateTime(2026, 7, 2);
      expect(vault(balance: 50000, deadline: deadline).isOverdue(after), isTrue);
      expect(vault(balance: 50000, deadline: deadline).isBehindPace(after), isTrue);
      expect(vault(balance: 120000, deadline: deadline).isOverdue(after), isFalse);
    });
  });

  group('Editar, excluir e transferir', () {
    test('Editar muda nome, meta e prazo, mas não o saldo', () async {
      final ds = MockFinanceDataSource();
      final v = (await ds.getSavingsVaults()).firstWhere((v) => v.id == 'vault_viagem');

      await ds.updateSavingsVault(v.copyWith(
        name: 'Viagem de Natal',
        targetAmount: const Money(900000),
        targetDate: DateTime(2026, 12, 20),
        currentBalance: const Money(1),
      ));

      final after = (await ds.getSavingsVaults()).firstWhere((x) => x.id == 'vault_viagem');
      expect(after.name, 'Viagem de Natal');
      expect(after.targetAmount, const Money(900000));
      expect(after.targetDate, DateTime(2026, 12, 20));
      expect(after.currentBalance, v.currentBalance);

      await expectLater(ds.updateSavingsVault(after.copyWith(name: '  ')), throwsA(isA<ServerFailure>()));
    });

    test('Excluir exige a caixinha zerada', () async {
      final ds = MockFinanceDataSource();
      final v = (await ds.getSavingsVaults()).firstWhere((v) => v.currentBalance.isPositive);

      await expectLater(ds.deleteSavingsVault(v.id), throwsA(isA<ServerFailure>()));

      await ds.withdrawFromVault(
        vaultId: v.id,
        memberId: 'member_carlos',
        amount: v.currentBalance,
        description: 'Esvaziar',
      );
      await ds.deleteSavingsVault(v.id);
      expect((await ds.getSavingsVaults()).any((x) => x.id == v.id), isFalse);
    });

    test('Transferir move o saldo e deixa os dois lados no histórico', () async {
      final ds = MockFinanceDataSource();
      final vaults = await ds.getSavingsVaults();
      final from = vaults.firstWhere((v) => v.id == 'vault_reserva');
      final to = vaults.firstWhere((v) => v.id == 'vault_viagem');

      await ds.transferBetweenVaults(
        fromVaultId: from.id,
        toVaultId: to.id,
        amount: const Money(10000),
        description: 'Mudança de prioridade',
      );

      final after = await ds.getSavingsVaults();
      expect(after.firstWhere((v) => v.id == from.id).currentBalance, from.currentBalance - const Money(10000));
      expect(after.firstWhere((v) => v.id == to.id).currentBalance, to.currentBalance + const Money(10000));

      final out = (await ds.getVaultTransactions(from.id)).first;
      final into = (await ds.getVaultTransactions(to.id)).first;
      expect(out.isTransfer && out.isWithdraw && out.counterpartVaultId == to.id, isTrue);
      expect(into.isTransfer && into.isDeposit && into.counterpartVaultId == from.id, isTrue);
      expect(VaultHistoryFilter.transfers.matches(out), isTrue);
      expect(VaultHistoryFilter.deposits.matches(out), isFalse);

      // Sem motivo, acima do saldo ou para a mesma caixinha: recusado
      await expectLater(
        ds.transferBetweenVaults(fromVaultId: from.id, toVaultId: to.id, amount: const Money(1), description: ''),
        throwsA(isA<ServerFailure>()),
      );
      await expectLater(
        ds.transferBetweenVaults(
          fromVaultId: from.id,
          toVaultId: to.id,
          amount: Money(from.currentBalance.cents * 10),
          description: 'x',
        ),
        throwsA(isA<ServerFailure>()),
      );
      await expectLater(
        ds.transferBetweenVaults(fromVaultId: from.id, toVaultId: from.id, amount: const Money(1), description: 'x'),
        throwsA(isA<ServerFailure>()),
      );
    });

    test('Histórico pagina do mais recente para o mais antigo', () async {
      final ds = MockFinanceDataSource();
      for (var i = 0; i < 5; i++) {
        await ds.depositToVault(
          vaultId: 'vault_reforma',
          memberId: 'member_carlos',
          amount: Money(100 + i),
          description: 'Depósito $i',
        );
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
      final first = await ds.getVaultTransactions('vault_reforma', limit: 3);
      expect(first.length, 3);
      final next = await ds.getVaultTransactions('vault_reforma', limit: 3, before: first.last.date);
      expect(next.every((t) => t.date.isBefore(first.last.date)), isTrue);
      expect({...first.map((t) => t.id)}.intersection({...next.map((t) => t.id)}), isEmpty);
    });

    test('Depósito sem motivo é recusado', () async {
      final ds = MockFinanceDataSource();
      await expectLater(
        ds.depositToVault(vaultId: 'vault_reserva', memberId: 'member_carlos', amount: const Money(100), description: ' '),
        throwsA(isA<ServerFailure>()),
      );
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

    test('Depósito tirado do Caixa do ciclo desfaz a devolução', () async {
      final ds = MockFinanceDataSource();
      final before = await ds.getCycleSummary(cycle);

      await ds.withdrawFromVault(
        vaultId: 'vault_reserva',
        memberId: 'member_carlos',
        amount: const Money(15000),
        description: 'Reforçar o Caixa do ciclo',
        returnToCycleStart: cycle.startDate,
      );
      await ds.depositToVault(
        vaultId: 'vault_viagem',
        memberId: 'member_carlos',
        amount: const Money(5000),
        description: 'Devolução errada',
        fromCycleStart: cycle.startDate,
      );

      expect(await ds.getVaultReturnsForCycle(cycle), const Money(10000));
      expect((await ds.getCycleSummary(cycle)).folego, before.folego + const Money(10000));
      final history = await ds.getVaultTransactions('vault_viagem');
      expect(history.first.takenFromCycle, isTrue);

      // Do Caixa só volta o que as caixinhas devolveram
      final viagem = (await ds.getSavingsVaults()).firstWhere((v) => v.id == 'vault_viagem').currentBalance;
      await expectLater(
        ds.depositToVault(
          vaultId: 'vault_viagem',
          memberId: 'member_carlos',
          amount: const Money(10001),
          description: 'Demais',
          fromCycleStart: cycle.startDate,
        ),
        throwsA(isA<ServerFailure>()),
      );
      expect(
        (await ds.getSavingsVaults()).firstWhere((v) => v.id == 'vault_viagem').currentBalance,
        viagem,
      );

      // Depósito de fora não mexe no Caixa do ciclo
      await ds.depositToVault(
        vaultId: 'vault_viagem',
        memberId: 'member_carlos',
        amount: const Money(7000),
        description: 'Aporte',
      );
      expect(await ds.getVaultReturnsForCycle(cycle), const Money(10000));
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

    testWidgets('Guardar exige o motivo do depósito', (tester) async {
      await sl<FinanceCubit>().loadCycleData();
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Guardar').first);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Confirmar e Guardar'));
      await tester.tap(find.text('Confirmar e Guardar'));
      await tester.pumpAndSettle();
      expect(find.text('Informe o motivo do depósito'), findsOneWidget);

      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
    });

    testWidgets('Menu da caixinha abre editar e transferir', (tester) async {
      await sl<FinanceCubit>().loadCycleData();
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Mais ações').first);
      await tester.pumpAndSettle();
      expect(find.text('Editar'), findsOneWidget);
      expect(find.text('Transferir'), findsOneWidget);
      expect(find.text('Excluir'), findsOneWidget);

      await tester.tap(find.text('Editar'));
      await tester.pumpAndSettle();
      expect(find.text('Editar Caixinha'), findsOneWidget);
      expect(find.text('Prazo da meta (opcional)'), findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Mais ações').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Transferir'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Transferir de:'), findsOneWidget);
      expect(find.text('Para a caixinha'), findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
    });

    testWidgets('Histórico mostra filtros e a transferência', (tester) async {
      final cubit = sl<FinanceCubit>();
      await cubit.loadCycleData();
      final vaults = cubit.state.savingsVaults.where((v) => v.currentBalance.cents >= 100).toList();
      final from = vaults.first;
      final to = cubit.state.savingsVaults.firstWhere((v) => v.id != from.id);
      await tester.runAsync(() => cubit.transferBetweenVaults(
            fromVaultId: from.id,
            toVaultId: to.id,
            amount: const Money(100),
            description: 'Organizar as caixinhas',
          ));

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      final index = cubit.state.savingsVaults.indexWhere((v) => v.id == from.id);
      final historyButton = find.text('Histórico de entradas e saídas').at(index);
      await tester.ensureVisible(historyButton);
      await tester.pumpAndSettle();
      await tester.tap(historyButton);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();

      expect(find.text('Transferências'), findsOneWidget);
      expect(find.textContaining('Transferido para ${to.name}'), findsOneWidget);

      await tester.tap(find.text('Entradas'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Transferido para ${to.name}'), findsNothing);

      await tester.tap(find.text('Fechar'));
      await tester.pumpAndSettle();
    });

    testWidgets('Guardar oferece tirar do Caixa do ciclo quando houve devolução', (tester) async {
      final cubit = sl<FinanceCubit>();
      await cubit.loadCycleData();
      final vault = cubit.state.savingsVaults.first;
      await tester.runAsync(() => cubit.withdrawFromVault(
            vaultId: vault.id,
            memberId: 'member_carlos',
            amount: const Money(3000),
            description: 'Reforçar o Caixa do ciclo',
            returnToCycleStart: cubit.cycleSchedule.cycleFor(DateTime.now()).startDate,
          ));

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Guardar').first);
      await tester.pumpAndSettle();

      expect(find.text('De fora'), findsOneWidget);
      await tester.tap(find.text('Do Caixa do ciclo'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Disponível para voltar'), findsOneWidget);

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
