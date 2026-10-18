import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/di/service_locator.dart';
import 'package:omni_lar/core/theme/theme_cubit.dart';
import 'package:omni_lar/features/auth/presentation/cubit/auth_cubit.dart';
import 'package:omni_lar/features/finance/domain/entities/member_settings.dart';
import 'package:omni_lar/features/finance/presentation/cubit/finance_cubit.dart';
import 'package:omni_lar/features/settings/presentation/pages/settings_page.dart';

void main() {
  setUpAll(() async {
    if (!sl.isRegistered<AuthCubit>()) {
      await initServiceLocator();
    }
  });

  testWidgets('Meus padrões de lançamento: cada morador escolhe quem paga, a forma e a categoria',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
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
    await tester.tap(find.text('Conta e segurança'));
    await tester.pumpAndSettle();

    // Sem escolha, mostra o automático
    final panel = find.text('Meus padrões de lançamento');
    await tester.ensureVisible(panel);
    expect(find.text('Quem paga'), findsOneWidget);
    expect(find.text('Eu'), findsOneWidget);
    expect(find.text('A última que usei'), findsOneWidget);
    expect(find.text('A que mais uso'), findsOneWidget);

    await tester.tap(panel);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('launch_category')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lazer e Restaurantes').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('launch_payer_house')));
    await tester.pumpAndSettle();
    expect(find.text('Pelo Caixa da casa, a forma é a conta da casa.'), findsOneWidget);
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    expect(find.text('Seus padrões de lançamento foram atualizados.'), findsOneWidget);
    final saved = sl<FinanceCubit>().state.memberSettings;
    expect(saved.launchPayer, LaunchPayer.house);
    expect(saved.launchCategoryId, 'cat_lazer');
    expect(saved.launchPaymentMethodId, isNull);
    expect(find.text('Caixa da casa'), findsOneWidget);
    expect(find.text('Conta da casa'), findsOneWidget);
    expect(find.text('Lazer e Restaurantes'), findsOneWidget);

    // Volta ao automático para os outros testes do modo demo
    await sl<FinanceCubit>().updateMemberSettings(const MemberSettings());
  });
}
