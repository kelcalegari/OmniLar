import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/features/auth/data/datasources/mock_auth_datasource.dart';
import 'package:omni_lar/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:omni_lar/features/auth/presentation/cubit/auth_cubit.dart';
import 'package:omni_lar/core/errors/failures.dart';
import 'package:omni_lar/features/auth/presentation/cubit/auth_state.dart';

void main() {
  group('Auth & House Management (Fase 0 - Fundação)', () {
    late MockAuthDataSource dataSource;
    late AuthRepositoryImpl repository;
    late AuthCubit cubit;

    setUp(() {
      // Inicia não-autenticado para testar todos os fluxos
      dataSource = MockAuthDataSource(startAuthenticated: false);
      repository = AuthRepositoryImpl(dataSource);
      cubit = AuthCubit(repository);
    });

    tearDown(() {
      cubit.close();
      dataSource.dispose();
    });

    test('Estado inicial deve ser unauthenticated quando não há sessão', () {
      expect(cubit.state.status, equals(AuthStatus.unauthenticated));
      expect(cubit.state.isAuthenticated, isFalse);
    });

    test(
      'signInWithEmailPassword com credenciais corretas deve autenticar e carregar a casa',
      () async {
        await cubit.signInWithEmailPassword('carlos@omnilar.com', '123456');

        expect(cubit.state.status, equals(AuthStatus.authenticatedWithHouse));
        expect(cubit.state.user?.email, equals('carlos@omnilar.com'));
        expect(cubit.state.house?.name, equals('Nossa Casa'));
        expect(cubit.state.hasHouse, isTrue);
      },
    );

    test(
      'signInWithEmailPassword com senha incorreta deve emitir failure',
      () async {
        await cubit.signInWithEmailPassword('carlos@omnilar.com', 'errada');

        expect(cubit.state.status, equals(AuthStatus.failure));
        expect(cubit.state.errorMessage, contains('inválidos'));
      },
    );

    test(
      'signUpWithEmailPassword cria usuário novo sem casa (AuthenticatedNoHouse)',
      () async {
        await cubit.signUpWithEmailPassword(
          email: 'novo@omnilar.com',
          password: 'password123',
          fullName: 'Novo Membro',
        );

        expect(cubit.state.status, equals(AuthStatus.authenticatedNoHouse));
        expect(cubit.state.user?.fullName, equals('Novo Membro'));
        expect(cubit.state.hasHouse, isFalse);

        // Usuário sem casa pode criar uma casa
        await cubit.createHouse(name: 'Meu Novo Apê', cycleStartDay: 10);

        expect(cubit.state.status, equals(AuthStatus.authenticatedWithHouse));
        expect(cubit.state.house?.name, equals('Meu Novo Apê'));
        expect(cubit.state.house?.cycleStartDay, equals(10));
      },
    );

    test(
      'joinHouseWithInvite valida convite existente e vincula casa ao usuário',
      () async {
        await cubit.signUpWithEmailPassword(
          email: 'convidado@omnilar.com',
          password: 'password123',
          fullName: 'Convidado Teste',
        );

        expect(cubit.state.status, equals(AuthStatus.authenticatedNoHouse));

        // Entra com código válido LAR123
        await cubit.joinHouseWithInvite('LAR123');

        expect(cubit.state.status, equals(AuthStatus.authenticatedWithHouse));
        expect(cubit.state.house?.name, equals('Nossa Casa'));
      },
    );

    test('joinHouseWithInvite com código inexistente emite failure', () async {
      await cubit.signUpWithEmailPassword(
        email: 'convidado2@omnilar.com',
        password: 'password123',
        fullName: 'Convidado Teste 2',
      );

      await cubit.joinHouseWithInvite('CODIGO_INVALIDO');

      expect(cubit.state.status, equals(AuthStatus.failure));
      expect(cubit.state.errorMessage, contains('inválido ou expirado'));
    });

    test('signOut desloga usuário e zera casa ativa', () async {
      await cubit.signInDemo(memberId: 'member_carlos');
      expect(cubit.state.status, equals(AuthStatus.authenticatedWithHouse));

      await cubit.signOut();
      expect(cubit.state.status, equals(AuthStatus.unauthenticated));
      expect(cubit.state.user, isNull);
      expect(cubit.state.house, isNull);
    });

    test(
      'updateProfile altera com sucesso nome e email do usuário autenticado',
      () async {
        await cubit.signInWithEmailPassword('carlos@omnilar.com', '123456');
        expect(cubit.state.user?.fullName, equals('Carlos Eduardo'));
        expect(cubit.state.user?.email, equals('carlos@omnilar.com'));

        final updated = await cubit.updateProfile(
          fullName: 'Carlos Eduardo Silva',
          email: 'carlos.silva@omnilar.com',
        );

        expect(updated?.fullName, equals('Carlos Eduardo Silva'));
        expect(updated?.email, equals('carlos.silva@omnilar.com'));
        expect(cubit.state.user?.fullName, equals('Carlos Eduardo Silva'));
        expect(cubit.state.user?.email, equals('carlos.silva@omnilar.com'));
      },
    );

    test(
      'updateProfile com email em uso por outro usuário lança erro',
      () async {
        await cubit.signInWithEmailPassword('carlos@omnilar.com', '123456');

        expect(
          () => cubit.updateProfile(
            fullName: 'Carlos Eduardo',
            email: 'marina@omnilar.com',
          ),
          throwsA(isA<AuthFailure>()),
        );
      },
    );
  });
}
