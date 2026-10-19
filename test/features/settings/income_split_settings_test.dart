import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/di/service_locator.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/core/theme/theme_cubit.dart';
import 'package:omni_lar/features/auth/presentation/cubit/auth_cubit.dart';
import 'package:omni_lar/features/finance/domain/entities/income_split.dart';
import 'package:omni_lar/features/finance/presentation/cubit/finance_cubit.dart';
import 'package:omni_lar/features/settings/presentation/pages/settings_page.dart';

void main() {
  setUpAll(() async {
    if (!sl.isRegistered<AuthCubit>()) {
      await initServiceLocator();
    }
  });

  Future<void> openSplitGroup(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 3600);
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

  testWidgets('padrão: renda privada, divisão à mão e renda dos outros escondida', (tester) async {
    await openSplitGroup(tester);
    expect(find.text('Renda e divisão'), findsWidgets);
    await tester.ensureVisible(find.text('Minha renda mensal'));
    expect(find.text('Percentuais definidos à mão'), findsOneWidget);
    expect(find.text('Cada um vê só a sua'), findsOneWidget);
    expect(find.text('Não informada'), findsOneWidget);
    expect(find.textContaining('é privada'), findsOneWidget);
  });

  testWidgets('o morador informa a própria renda e só ela aparece', (tester) async {
    await openSplitGroup(tester);
    final button = find.byKey(const Key('my_income_button'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('my_income_field')), '350000');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    final cubit = sl<FinanceCubit>();
    expect(cubit.state.memberIncomes.values, [const Money(350000)]);
    expect(cubit.state.houseSettings.incomeVisibility, IncomeVisibility.self);
    expect(find.text('Renda de Marina'), findsNothing);

    await cubit.setMyIncome(null);
  });
}
