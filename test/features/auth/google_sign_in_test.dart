import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/features/auth/data/datasources/mock_auth_datasource.dart';
import 'package:omni_lar/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:omni_lar/features/auth/presentation/cubit/auth_cubit.dart';
import 'package:omni_lar/features/auth/presentation/cubit/auth_state.dart';
import 'package:omni_lar/features/auth/presentation/pages/login_page.dart';

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

  Future<void> pumpLogin(WidgetTester tester, {required bool showGoogle}) async {
    tester.view.physicalSize = const Size(400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      BlocProvider.value(
        value: cubit,
        child: MaterialApp(home: LoginPage(showGoogleSignIn: showGoogle)),
      ),
    );
  }

  testWidgets('botão do Google fica escondido sem configuração', (tester) async {
    await pumpLogin(tester, showGoogle: false);
    expect(find.text('Continuar com Google'), findsNothing);
  });

  testWidgets('falha do Google aparece como aviso na tela de login', (tester) async {
    await pumpLogin(tester, showGoogle: true);
    expect(find.text('Continuar com Google'), findsOneWidget);

    await tester.tap(find.text('Continuar com Google'));
    await tester.pumpAndSettle();

    expect(cubit.state.status, AuthStatus.failure);
    expect(find.textContaining('modo demonstração'), findsOneWidget);
  });
}
