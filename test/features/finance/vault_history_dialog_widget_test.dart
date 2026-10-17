import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/di/service_locator.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/features/finance/domain/entities/house_member.dart';
import 'package:omni_lar/features/finance/domain/entities/savings_vault.dart';
import 'package:omni_lar/features/finance/domain/repositories/finance_repository.dart';
import 'package:omni_lar/features/finance/presentation/cubit/finance_cubit.dart';
import 'package:omni_lar/features/finance/presentation/widgets/vault_history_dialog.dart';

void main() {
  setUpAll(() async {
    if (!sl.isRegistered<FinanceCubit>()) {
      await initServiceLocator();
    }
  });

  testWidgets('histórico da caixinha mostra a entrada com o motivo e filtra por tipo', (tester) async {
    late SavingsVault vault;
    late List<SavingsVault> vaults;
    late List<HouseMember> members;
    await tester.runAsync(() async {
      final repo = sl<FinanceRepository>();
      vaults = await repo.getSavingsVaults();
      vault = vaults.first;
      members = await repo.getMembers();
      await repo.depositToVault(
        vaultId: vault.id,
        memberId: members.first.id,
        amount: Money.fromReal(12.34),
        description: 'Depósito do teste de tela',
      );
    });

    await tester.pumpWidget(MaterialApp(
      home: BlocProvider.value(
        value: sl<FinanceCubit>(),
        child: Scaffold(
          body: VaultHistoryDialog(vault: vault, members: members, vaults: vaults),
        ),
      ),
    ));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pumpAndSettle();

    expect(find.text('Histórico: ${vault.name}'), findsOneWidget);
    expect(find.text('Depósito do teste de tela'), findsOneWidget);

    // "Saídas" esconde a entrada; "Entradas" mostra de novo
    await tester.tap(find.text(VaultHistoryFilter.withdrawals.label));
    await tester.pumpAndSettle();
    expect(find.text('Depósito do teste de tela'), findsNothing);

    await tester.tap(find.text(VaultHistoryFilter.deposits.label));
    await tester.pumpAndSettle();
    expect(find.text('Depósito do teste de tela'), findsOneWidget);
  });
}
