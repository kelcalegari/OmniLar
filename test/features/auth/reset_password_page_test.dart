import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/features/auth/data/datasources/mock_auth_datasource.dart';
import 'package:omni_lar/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:omni_lar/features/auth/presentation/cubit/auth_cubit.dart';
import 'package:omni_lar/features/auth/presentation/pages/reset_password_page.dart';

void main() {
  late MockAuthDataSource dataSource;
  late AuthCubit cubit;

  setUp(() {
    dataSource = MockAuthDataSource(startAuthenticated: false);
    cubit = AuthCubit(AuthRepositoryImpl(dataSource));
  });

  tearDown(() {
    cubit.close();
    dataSource.dispose();
  });

  Future<void> pumpPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      BlocProvider.value(
        value: cubit,
        child: const MaterialApp(
          home: ResetPasswordPage(initialEmail: 'carlos@omnilar.com'),
        ),
      ),
    );
  }

  testWidgets('envia o código e troca a senha', (tester) async {
    await pumpPage(tester);
    expect(find.text('carlos@omnilar.com'), findsOneWidget);

    await tester.tap(find.text('Enviar código'));
    await tester.pumpAndSettle(const Duration(milliseconds: 200));

    expect(find.text('Salvar senha e entrar'), findsOneWidget);
    expect(find.textContaining('Reenviar código em'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextFormField, 'Código'), '123456');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nova senha'),
      'novaSenha1',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Confirme a nova senha'),
      'outraSenha',
    );
    await tester.tap(find.text('Salvar senha e entrar'));
    await tester.pump();
    expect(find.text('As senhas não conferem'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Confirme a nova senha'),
      'novaSenha1',
    );
    await tester.tap(find.text('Salvar senha e entrar'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(cubit.state.isAuthenticated, isTrue);
    expect(cubit.state.user?.email, 'carlos@omnilar.com');

    // Encerra o contador de reenvio
    await tester.pumpWidget(const SizedBox());
  });
}
