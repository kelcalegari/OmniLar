import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/di/service_locator.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/features/finance/domain/entities/house_inflow.dart';
import 'package:omni_lar/features/finance/presentation/cubit/finance_cubit.dart';
import 'package:omni_lar/main.dart';

void main() {
  setUpAll(() async {
    if (!sl.isRegistered<FinanceCubit>()) {
      await initServiceLocator();
    }
  });

  testWidgets('Timeline na Home permite alternar entre Saídas e Entradas com filtro Sem aplicar', (tester) async {
    final financeCubit = sl<FinanceCubit>();
    await financeCubit.loadCycleData();

    // Popula entradas para teste
    final now = DateTime.now();
    await financeCubit.registerThirdPartyReceipt(
      payerName: 'Roberta',
      amount: const Money(8500),
      receivedOn: now,
      vaultId: 'vault_reserva',
      description: 'Pix pizza cartão',
    );

    // Repasse vindo de ciclo anterior (60 dias atrás)
    final pastDate = now.subtract(const Duration(days: 60));
    await financeCubit.registerThirdPartyReceipt(
      payerName: 'Lucas Trabalho',
      amount: const Money(5000),
      receivedOn: pastDate,
      vaultId: 'vault_reserva',
      description: 'Almoço mês passado',
    );

    await financeCubit.addHouseInflow(
      HouseInflow(
        id: 'inflow_test_1',
        amount: const Money(4200),
        description: 'Reembolso mercado',
        source: HouseInflowSource.refund,
        receivedOn: now,
      ),
    );

    await tester.pumpWidget(const OmniLarApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    // Encontra o alternador de Saídas / Entradas e rola até ele
    final toggle = find.byKey(const Key('timeline_direction_toggle'));
    expect(toggle, findsOneWidget);

    await tester.ensureVisible(toggle);
    await tester.pumpAndSettle();

    // Clica para alternar para Entradas
    await tester.tap(find.textContaining('Entradas'));
    await tester.pumpAndSettle();

    // Filtros de entradas devem aparecer
    expect(find.text('Todas'), findsOneWidget);
    expect(find.textContaining('Sem aplicar'), findsOneWidget);
    expect(find.text('Repasses'), findsOneWidget);

    // Seção de pendências de ciclos anteriores e do ciclo atual
    expect(find.text('Pendências de Ciclos Anteriores'), findsOneWidget);
    expect(find.text('Deste Ciclo'), findsOneWidget);

    // Badge de ciclo anterior para Lucas
    expect(find.text('Repasse (ciclo anterior)'), findsOneWidget);
    expect(find.text('Repasse (guardado)'), findsOneWidget);

    // Os itens devem estar visíveis
    expect(find.text('Roberta'), findsOneWidget);
    expect(find.text('Lucas Trabalho'), findsOneWidget);
    expect(find.text('Reembolso mercado'), findsOneWidget);

    // Filtra por "Sem aplicar"
    await tester.tap(find.textContaining('Sem aplicar'));
    await tester.pumpAndSettle();

    // Ambos os repasses e o reembolso livre aparecem no filtro sem aplicar
    expect(find.text('Roberta'), findsOneWidget);
    expect(find.text('Lucas Trabalho'), findsOneWidget);
    expect(find.text('Reembolso mercado'), findsOneWidget);
  });
}
