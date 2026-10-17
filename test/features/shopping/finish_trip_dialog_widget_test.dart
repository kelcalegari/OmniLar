import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/di/service_locator.dart';
import 'package:omni_lar/features/auth/presentation/cubit/auth_cubit.dart';
import 'package:omni_lar/features/calendar/presentation/cubit/calendar_cubit.dart';
import 'package:omni_lar/features/finance/presentation/cubit/finance_cubit.dart';
import 'package:omni_lar/features/p2p/presentation/cubit/p2p_cubit.dart';
import 'package:omni_lar/features/routine/presentation/pages/tasks_and_shopping_page.dart';
import 'package:omni_lar/features/shopping/presentation/cubit/shopping_cubit.dart';

void main() {
  setUpAll(() async {
    if (!sl.isRegistered<ShoppingCubit>()) {
      await initServiceLocator();
    }
  });

  testWidgets('fechar compra com item pessoal pede o subtotal e o dono, e não lança sem valor', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    // A fonte de teste (letras quadradas) estoura linhas apertadas; só isso é ignorado
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.exceptionAsString().contains('overflowed')) return;
      previous?.call(details);
    };
    addTearDown(() => FlutterError.onError = previous);

    final shopping = sl<ShoppingCubit>();
    final finance = sl<FinanceCubit>();
    await tester.runAsync(() async {
      await finance.loadCycleData();
      await shopping.loadShoppingData();
    });

    await tester.pumpWidget(MultiBlocProvider(
      providers: [
        BlocProvider.value(value: sl<AuthCubit>()),
        BlocProvider.value(value: sl<CalendarCubit>()),
        BlocProvider.value(value: shopping),
        BlocProvider.value(value: finance),
        BlocProvider.value(value: sl<P2PCubit>()),
      ],
      child: const MaterialApp(home: TasksAndShoppingPage(initialTabIndex: 1)),
    ));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pumpAndSettle();

    // Garante um item pessoal já comprado
    await tester.runAsync(() async {
      final personal = shopping.state.items.where((i) => i.isPersonal).firstOrNull ??
          shopping.state.items.first;
      if (!personal.isPersonal) await shopping.updateItem(personal.copyWith(isPersonal: true));
      if (!personal.isBought) await shopping.toggleItemBought(personal.id);
    });
    await tester.pumpAndSettle();

    final finish = find.byIcon(Icons.receipt_long_rounded).first;
    await tester.ensureVisible(finish);
    await tester.tap(finish);
    await tester.pumpAndSettle();

    expect(find.text('Finalizar Compra da Casa'), findsOneWidget);
    expect(find.textContaining('item(ns) pessoais nesta compra'), findsOneWidget);
    expect(find.text('Subtotal dos Itens Pessoais'), findsOneWidget);
    expect(find.text('De quem são os itens pessoais'), findsOneWidget);

    // Sem o valor da nota, confirmar não fecha a janela
    await tester.tap(find.text('Confirmar e Lançar'));
    await tester.pumpAndSettle();
    expect(find.text('Finalizar Compra da Casa'), findsOneWidget);

    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(find.text('Finalizar Compra da Casa'), findsNothing);
  });
}
