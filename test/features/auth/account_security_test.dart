import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/errors/failures.dart';
import 'package:omni_lar/features/auth/data/datasources/mock_auth_datasource.dart';
import 'package:omni_lar/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:omni_lar/features/auth/presentation/cubit/auth_cubit.dart';
import 'package:omni_lar/features/auth/presentation/cubit/auth_state.dart';
import 'package:omni_lar/features/settings/presentation/widgets/account_security_panel.dart';

void main() {
  late MockAuthDataSource dataSource;
  late AuthCubit cubit;

  setUp(() async {
    dataSource = MockAuthDataSource(startAuthenticated: false);
    cubit = AuthCubit(AuthRepositoryImpl(dataSource));
    await cubit.signInWithEmailPassword('carlos@omnilar.com', '123456');
  });

  tearDown(() {
    cubit.close();
    dataSource.dispose();
  });

  group('Alterar senha', () {
    test('senha atual errada é recusada', () async {
      await expectLater(
        cubit.changePassword(currentPassword: 'errada', newPassword: 'nova123'),
        throwsA(
          isA<AuthFailure>().having((f) => f.message, 'message', contains('Senha atual')),
        ),
      );
    });

    test('troca a senha e a nova passa a valer no login', () async {
      await cubit.changePassword(currentPassword: '123456', newPassword: 'nova123');

      await cubit.signOut();
      await cubit.signInWithEmailPassword('carlos@omnilar.com', '123456');
      expect(cubit.state.status, AuthStatus.failure);
      await cubit.signInWithEmailPassword('carlos@omnilar.com', 'nova123');
      expect(cubit.state.status, AuthStatus.authenticatedWithHouse);
    });
  });

  group('Alterar e-mail', () {
    test('e-mail de outra conta é recusado', () async {
      await expectLater(
        cubit.requestEmailChange('marina@omnilar.com'),
        throwsA(isA<AuthFailure>()),
      );
      expect(cubit.pendingEmailChange, isNull);
    });

    test('fica pendente até o código e depois troca', () async {
      await cubit.requestEmailChange('carlos.novo@omnilar.com');
      expect(cubit.pendingEmailChange, 'carlos.novo@omnilar.com');
      expect(cubit.state.user?.email, 'carlos@omnilar.com');

      await expectLater(
        cubit.confirmEmailChange(email: 'carlos.novo@omnilar.com', code: '000000'),
        throwsA(isA<AuthFailure>()),
      );

      final done = await cubit.confirmEmailChange(
        email: 'carlos.novo@omnilar.com',
        code: MockAuthDataSource.mockConfirmationCode,
      );
      expect(done, isTrue);
      expect(cubit.state.user?.email, 'carlos.novo@omnilar.com');
      expect(cubit.pendingEmailChange, isNull);
    });
  });

  testWidgets('painel mostra e-mail, forma de entrar e a troca pendente', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.runAsync(() => cubit.requestEmailChange('carlos.novo@omnilar.com'));
    await tester.pumpWidget(
      BlocProvider.value(
        value: cubit,
        child: const MaterialApp(home: Scaffold(body: AccountSecurityPanel())),
      ),
    );

    expect(find.text('carlos@omnilar.com'), findsOneWidget);
    expect(find.text('E-mail e senha'), findsOneWidget);
    expect(find.textContaining('carlos.novo@omnilar.com'), findsOneWidget);
    expect(find.text('Digitar código'), findsOneWidget);
  });
}
