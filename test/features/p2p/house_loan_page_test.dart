import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/di/service_locator.dart';
import 'package:omni_lar/features/finance/presentation/cubit/finance_cubit.dart';
import 'package:omni_lar/features/p2p/presentation/cubit/p2p_cubit.dart';
import 'package:omni_lar/features/p2p/presentation/pages/create_loan_page.dart';

void main() {
  setUpAll(() async {
    if (!sl.isRegistered<P2PCubit>()) {
      await initServiceLocator();
    }
  });

  testWidgets('administrador escolhe o Caixa da Casa e de onde sai o dinheiro', (tester) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.runAsync(() => sl<FinanceCubit>().loadCycleData());
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider.value(value: sl<P2PCubit>()),
          BlocProvider.value(value: sl<FinanceCubit>()),
        ],
        child: const MaterialApp(home: CreateLoanPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('loan_house_funding')), findsNothing);
    await tester.tap(find.byKey(const Key('loan_lender_house')));
    await tester.pumpAndSettle();

    // O Caixa empresta agora: some o cadastro de empréstimo antigo
    expect(find.byKey(const Key('loan_house_funding')), findsOneWidget);
    expect(find.text('Empréstimo iniciado no passado?'), findsNothing);
    expect(find.textContaining('Sai da sobra deste ciclo'), findsOneWidget);

    await tester.tap(find.text('Caixinha'));
    await tester.pumpAndSettle();
    expect(find.textContaining('cada pagamento volta para ela'), findsOneWidget);
  });
}
