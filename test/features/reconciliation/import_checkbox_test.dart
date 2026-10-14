import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/di/service_locator.dart';
import 'package:omni_lar/features/auth/presentation/cubit/auth_cubit.dart';
import 'package:omni_lar/features/finance/presentation/cubit/finance_cubit.dart';
import 'package:omni_lar/features/p2p/presentation/cubit/p2p_cubit.dart';
import 'package:omni_lar/features/reconciliation/presentation/pages/import_page.dart';

void main() {
  setUpAll(() async {
    if (!sl.isRegistered<AuthCubit>()) {
      await initServiceLocator();
    }
    await sl<AuthCubit>().signInDemo(memberId: 'member_carlos');
    await sl<FinanceCubit>().loadCycleData();
  });

  testWidgets('marcar uma linha pelo checkbox abre a edição em lote', (tester) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<FinanceCubit>.value(value: sl<FinanceCubit>()),
          BlocProvider<P2PCubit>.value(value: sl<P2PCubit>()),
        ],
        child: const MaterialApp(home: ImportPage(initialSourceId: 'pm_card_marina')),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Usar fatura de exemplo'));
    await tester.pumpAndSettle();

    final boxes = find.byType(Checkbox);
    expect(boxes, findsWidgets);
    expect(tester.widget<Checkbox>(boxes.first).onChanged, isNotNull);

    await tester.tap(boxes.first);
    await tester.pumpAndSettle();
    expect(find.text('1 linha marcada'), findsOneWidget);
    expect(tester.widget<Checkbox>(boxes.first).value, isTrue);

    await tester.tap(boxes.first);
    await tester.pumpAndSettle();
    expect(find.text('1 linha marcada'), findsNothing);
  });
}
