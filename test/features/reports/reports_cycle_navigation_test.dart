import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/di/service_locator.dart';
import 'package:omni_lar/features/finance/presentation/cubit/finance_cubit.dart';
import 'package:omni_lar/features/reports/presentation/pages/reports_page.dart';

void main() {
  setUpAll(() async {
    if (!sl.isRegistered<FinanceCubit>()) {
      await initServiceLocator();
    }
  });

  testWidgets('Relatórios: fora do ciclo atual aparece o atalho para voltar a ele', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final finance = sl<FinanceCubit>();
    finance.goToCurrentCycle();
    await finance.loadCycleData();

    await tester.pumpWidget(BlocProvider<FinanceCubit>.value(
      value: finance,
      child: const MaterialApp(home: ReportsPage()),
    ));
    await tester.pumpAndSettle();

    final back = find.byKey(const Key('reports_back_to_current_cycle'));
    expect(back, findsNothing);

    await tester.tap(find.byTooltip('Ciclo Anterior'));
    await tester.pumpAndSettle();
    expect(back, findsOneWidget);
    expect(finance.state.currentCycle.contains(DateTime.now()), isFalse);

    await tester.tap(back);
    await tester.pumpAndSettle();
    expect(back, findsNothing);
    expect(finance.state.currentCycle.contains(DateTime.now()), isTrue);
  });
}
