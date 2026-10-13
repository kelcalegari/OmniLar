import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
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

  Widget buildTestableWidget() {
    return MultiBlocProvider(
      providers: [
        BlocProvider<ThemeCubit>.value(value: sl<ThemeCubit>()),
        BlocProvider<AuthCubit>.value(value: sl<AuthCubit>()),
        BlocProvider<FinanceCubit>.value(value: sl<FinanceCubit>()),
      ],
      child: const MaterialApp(home: SettingsPage()),
    );
  }

  test('FinanceCubit - add, update and delete payment methods', () async {
    final cubit = sl<FinanceCubit>();
    await cubit.loadCycleData();

    final initialCount = cubit.state.paymentMethods.length;

    // 1. Add
    const newPm = PaymentMethod(
      id: 'test_pm_1',
      name: 'Cartão Teste',
      type: PaymentMethodType.card,
      closingDay: 15,
      dueDay: 25,
    );
    await cubit.addPaymentMethod(newPm);
    expect(cubit.state.paymentMethods.length, equals(initialCount + 1));
    expect(cubit.state.paymentMethods.any((p) => p.id == 'test_pm_1' && p.name == 'Cartão Teste'), isTrue);

    // 2. Update
    final updatedPm = newPm.copyWith(
      name: 'Cartão Teste Editado',
      closingDay: 20,
    );
    await cubit.updatePaymentMethod(updatedPm);
    final found = cubit.state.paymentMethods.firstWhere((p) => p.id == 'test_pm_1');
    expect(found.name, equals('Cartão Teste Editado'));
    expect(found.closingDay, equals(20));

    // 3. Delete
    await cubit.deletePaymentMethod('test_pm_1');
    expect(cubit.state.paymentMethods.any((p) => p.id == 'test_pm_1'), isFalse);
    expect(cubit.state.paymentMethods.length, equals(initialCount));
  });

  testWidgets('SettingsPage - opens payment methods modal and allows editing', (tester) async {
    final cubit = sl<FinanceCubit>();
    await cubit.loadCycleData();

    await tester.pumpWidget(buildTestableWidget());
    await tester.pumpAndSettle();

    // Scroll if needed and tap Cartões e Formas de Pagamento
    // Os ajustes ficam em grupos: abre o grupo antes de procurar a opção
    await tester.tap(find.text('Pagamentos e contas'));
    await tester.pumpAndSettle();
    // As formas de pagamento ficam à vista no grupo, sem janela por cima
    expect(find.text('Cartões e Formas de Pagamento'), findsOneWidget);
    final firstMethod = find.text(cubit.state.paymentMethods.first.name);
    expect(firstMethod, findsOneWidget);

    // Tocar em uma forma de pagamento abre a edição dela
    await tester.ensureVisible(firstMethod);
    await tester.tap(firstMethod);
    await tester.pumpAndSettle();

    expect(find.text('Editar Forma de Pagamento'), findsOneWidget);
    expect(find.text('Salvar Alterações'), findsOneWidget);

    // Cancel edit dialog
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
  });

  testWidgets('SettingsPage - can add a new payment method via UI', (tester) async {
    final cubit = sl<FinanceCubit>();
    await cubit.loadCycleData();

    await tester.pumpWidget(buildTestableWidget());
    await tester.pumpAndSettle();

    // Open modal
    // Os ajustes ficam em grupos: abre o grupo antes de procurar a opção
    await tester.tap(find.text('Pagamentos e contas'));
    await tester.pumpAndSettle();

    // O botão de cadastrar fica no próprio grupo
    final addBtn = find.text('Cadastrar Cartão ou VR');
    await tester.ensureVisible(addBtn);
    await tester.tap(addBtn);
    await tester.pumpAndSettle();

    // Verify dialog title
    expect(find.text('Nova Forma de Pagamento'), findsOneWidget);

    // Enter name in AlertDialog's TextField
    final dialogTextField = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(dialogTextField, 'Cartão Alimentação Pluxee');
    await tester.pumpAndSettle();

    // Tap Salvar
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    // Verify dialog closed
    expect(find.text('Nova Forma de Pagamento'), findsNothing);

    // Verify cubit state was updated with new payment method
    expect(
      cubit.state.paymentMethods.any((p) => p.name == 'Cartão Alimentação Pluxee'),
      isTrue,
    );

    // A forma nova aparece na lista do grupo
    expect(
      find.text('Cartão Alimentação Pluxee', skipOffstage: false),
      findsOneWidget,
    );
  });
}
