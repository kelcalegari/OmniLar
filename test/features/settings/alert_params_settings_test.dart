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

  Future<void> openSettings(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 2400);
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
  }

  testWidgets('Meus lembretes: o morador escolhe a hora e o que silenciar', (tester) async {
    await openSettings(tester);
    await tester.tap(find.text('Conta e segurança'));
    await tester.pumpAndSettle();

    expect(find.text('Meus lembretes'), findsOneWidget);
    expect(find.text('09h'), findsOneWidget);
    expect(find.text('Domingo, 18h'), findsOneWidget);

    await tester.ensureVisible(find.text('Meus lembretes'));
    await tester.tap(find.text('Meus lembretes'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('alert_hour')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('07h').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('reminder_tasks')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    final saved = sl<FinanceCubit>().state.memberSettings;
    expect(saved.alertHour, 7);
    expect(saved.mutedReminders, {'tasks'});
    expect(find.text('Seus lembretes foram atualizados.'), findsOneWidget);

    await sl<FinanceCubit>().updateMemberSettings(const MemberSettings());
  });
}
