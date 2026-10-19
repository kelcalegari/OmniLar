import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/di/service_locator.dart';
import 'package:omni_lar/core/theme/theme_cubit.dart';
import 'package:omni_lar/features/auth/presentation/cubit/auth_cubit.dart';
import 'package:omni_lar/features/finance/domain/entities/payment_method.dart';
import 'package:omni_lar/features/finance/presentation/cubit/finance_cubit.dart';
import 'package:omni_lar/features/settings/presentation/pages/settings_page.dart';

void main() {
  setUpAll(() async {
    if (!sl.isRegistered<AuthCubit>()) {
      await initServiceLocator();
    }
  });

  Future<void> openPayments(WidgetTester tester) async {
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
    await tester.tap(find.text('Pagamentos e contas'));
    await tester.pumpAndSettle();
  }

  testWidgets('a página mostra os padrões da importação', (tester) async {
    await openPayments(tester);
    expect(find.text('Importação de extrato'), findsOneWidget);
    expect(find.text('3 dias (2 em outra forma de pagamento)'), findsOneWidget);
    expect(find.text('Divisão da categoria ou da casa'), findsOneWidget);
    expect(find.text('Sem preferência'), findsOneWidget);
  });

  testWidgets('o cartão escolhe quem costuma pagar a fatura e depois limpa', (tester) async {
    final cubit = sl<FinanceCubit>();
    await cubit.loadCycleData();
    final member = cubit.state.members.first;
    await cubit.addPaymentMethod(const PaymentMethod(
      id: 'pm_fatura_teste',
      name: 'Cartão Fatura Teste',
      type: PaymentMethodType.card,
      closingDay: 20,
      dueDay: 28,
    ));
    addTearDown(() => cubit.deletePaymentMethod('pm_fatura_teste'));

    await openPayments(tester);
    final tile = find.text('Cartão Fatura Teste');
    await tester.ensureVisible(tile);
    await tester.tap(tile);
    await tester.pumpAndSettle();

    final dropdown = find.byKey(const ValueKey('usual_invoice_payer'));
    await tester.ensureVisible(dropdown);
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text(member.name).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salvar Alterações'));
    await tester.pumpAndSettle();

    PaymentMethod saved() => cubit.state.paymentMethods.firstWhere((p) => p.id == 'pm_fatura_teste');
    expect(saved().usualInvoicePayerId, member.id);

    await cubit.updatePaymentMethod(saved().copyWith(clearUsualInvoicePayer: true));
    expect(saved().usualInvoicePayerId, isNull);
  });
}
