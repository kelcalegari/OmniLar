import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/di/service_locator.dart';
import 'package:omni_lar/core/theme/theme_cubit.dart';
import 'package:omni_lar/features/auth/presentation/cubit/auth_cubit.dart';
import 'package:omni_lar/features/finance/domain/entities/category_default_split.dart';
import 'package:omni_lar/features/finance/domain/entities/house_settings.dart';
import 'package:omni_lar/features/finance/presentation/cubit/finance_cubit.dart';
import 'package:omni_lar/features/settings/presentation/pages/settings_page.dart';

void main() {
  setUpAll(() async {
    if (!sl.isRegistered<AuthCubit>()) {
      await initServiceLocator();
    }
  });

  Future<void> openSplitGroup(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await sl<FinanceCubit>().loadCycleData();
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
    await tester.tap(find.text('Divisão das despesas'));
    await tester.pumpAndSettle();
  }

  testWidgets('Divisão para quem entra: o administrador escolhe a política da casa', (tester) async {
    await openSplitGroup(tester);

    final panel = find.text('Divisão para quem entra');
    await tester.ensureVisible(panel);
    expect(find.text('Fatia igual para quem chega'), findsOneWidget);
    await tester.tap(panel);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('new_member_policy_keep_current')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    expect(find.text('Divisão para quem entra atualizada.'), findsOneWidget);
    expect(sl<FinanceCubit>().state.houseSettings.newMemberSplitPolicy, NewMemberSplitPolicy.keepCurrent);
    expect(find.text('Manter a divisão atual'), findsOneWidget);

    // Volta ao de sempre para os outros testes do modo demo
    await sl<FinanceCubit>().updateHouseSettings(newMemberSplitPolicy: NewMemberSplitPolicy.equal);
  });

  testWidgets('Categoria: percentuais próprios precisam fechar 100% e ficam gravados', (tester) async {
    await openSplitGroup(tester);

    await tester.tap(find.text('Lazer e Restaurantes'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('category_split_mode')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Percentuais próprios').last);
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const ValueKey('category_split_percent_member_carlos')), '70');
    await tester.enterText(find.byKey(const ValueKey('category_split_percent_member_marina')), '20');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('category_split_error')), findsOneWidget);
    expect(find.textContaining('somam 90%'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('category_split_percent_member_marina')), '30');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    final cat = sl<FinanceCubit>().state.categories.firstWhere((c) => c.id == 'cat_lazer');
    expect(cat.defaultSplit, const CategoryDefaultSplit.percentage({'member_carlos': 70.0, 'member_marina': 30.0}));
    expect(find.textContaining('Divisão padrão: Carlos 70% / Marina 30%'), findsOneWidget);
  });
}
