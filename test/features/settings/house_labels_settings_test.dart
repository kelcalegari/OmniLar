import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/di/service_locator.dart';
import 'package:omni_lar/core/theme/theme_cubit.dart';
import 'package:omni_lar/features/auth/presentation/cubit/auth_cubit.dart';
import 'package:omni_lar/features/finance/domain/entities/import_params.dart';
import 'package:omni_lar/features/finance/presentation/cubit/finance_cubit.dart';
import 'package:omni_lar/features/settings/presentation/pages/settings_page.dart';
import 'package:omni_lar/features/shopping/presentation/cubit/shopping_cubit.dart';

void main() {
  setUpAll(() async {
    if (!sl.isRegistered<AuthCubit>()) {
      await initServiceLocator();
    }
  });

  Future<void> openHouse(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await sl<FinanceCubit>().loadCycleData();
    await sl<ShoppingCubit>().loadShoppingData();
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<ThemeCubit>.value(value: sl<ThemeCubit>()),
          BlocProvider<AuthCubit>.value(value: sl<AuthCubit>()),
          BlocProvider<FinanceCubit>.value(value: sl<FinanceCubit>()),
        ],
        child: const MaterialApp(home: SettingsPage()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Casa').first);
    await tester.pumpAndSettle();
  }

  testWidgets('a casa mostra o nome do Caixa e as unidades de sempre', (tester) async {
    await openHouse(tester);
    expect(find.text('Nomes e compras'), findsOneWidget);
    expect(find.text('Caixa da Casa'), findsWidgets);
    expect(find.text('un, kg, g, l, ml, pct, cx, dz'), findsOneWidget);
    expect(find.text('Compras de mercado por lista'), findsOneWidget);
  });

  testWidgets('administrador troca o nome do Caixa e as unidades', (tester) async {
    final cubit = sl<FinanceCubit>();
    await openHouse(tester);

    await tester.tap(find.text('Nomes e compras'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('cash_label_field')), 'Cofre');
    await tester.enterText(find.byKey(const ValueKey('shopping_units_field')), 'cx, kg');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    expect(cubit.state.houseSettings.cashName, 'Cofre');
    expect(cubit.state.houseSettings.shoppingUnits, ['cx', 'kg']);

    // Volta ao padrão
    await cubit.updateHouseSettings(clearCashLabel: true, shoppingUnits: const ['un', 'kg', 'g', 'l', 'ml', 'pct', 'cx', 'dz']);
    expect(cubit.state.houseSettings.cashName, 'Caixa da Casa');
  });

  testWidgets('unidades repetidas são recusadas', (tester) async {
    final cubit = sl<FinanceCubit>();
    await openHouse(tester);

    await tester.tap(find.text('Nomes e compras'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('shopping_units_field')), 'kg, KG');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('house_labels_error')), findsOneWidget);
    expect(cubit.state.houseSettings.shoppingUnits, contains('un'));
  });

  testWidgets('a lista escolhe categoria e divisão da compra', (tester) async {
    final shopping = sl<ShoppingCubit>();
    final list = shopping.state.lists.first;
    await openHouse(tester);

    final tile = find.byKey(ValueKey('shopping_list_defaults_${list.id}'));
    await tester.ensureVisible(tile);
    await tester.tap(tile);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('list_default_split')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Partes iguais').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    final saved = shopping.state.lists.firstWhere((l) => l.id == list.id);
    expect(saved.defaultSplitMode, ImportSplitMode.equal);
    expect(saved.defaultCategoryId, isNull);
  });
}
