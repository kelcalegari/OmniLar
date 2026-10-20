import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/features/auth/data/datasources/mock_auth_datasource.dart';
import 'package:omni_lar/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:omni_lar/features/auth/presentation/cubit/auth_cubit.dart';
import 'package:omni_lar/features/auth/presentation/cubit/auth_state.dart';

void main() {
  group('Múltiplas Casas e Gestão de Contexto', () {
    late MockAuthDataSource dataSource;
    late AuthRepositoryImpl repository;
    late AuthCubit cubit;

    setUp(() {
      dataSource = MockAuthDataSource(startAuthenticated: false);
      repository = AuthRepositoryImpl(dataSource);
      cubit = AuthCubit(repository);
    });

    tearDown(() {
      cubit.close();
      dataSource.dispose();
    });

    test('Login carrega a casa ativa e a lista de casas do usuário', () async {
      await cubit.signInWithEmailPassword('carlos@omnilar.com', '123456');

      expect(cubit.state.status, equals(AuthStatus.authenticatedWithHouse));
      expect(cubit.state.house, isNotNull);
      expect(cubit.state.house?.name, equals('Nossa Casa'));
      expect(cubit.state.userHouses, isNotEmpty);
      expect(cubit.state.userHouses.any((h) => h.id == 'house_nossa_casa'), isTrue);
    });

    test('Criar uma segunda casa atualiza a casa ativa e a lista de casas', () async {
      await cubit.signInWithEmailPassword('carlos@omnilar.com', '123456');
      final initialCount = cubit.state.userHouses.length;

      await cubit.createHouse(name: 'Casa de Praia', cycleStartDay: 10);

      expect(cubit.state.status, equals(AuthStatus.authenticatedWithHouse));
      expect(cubit.state.house?.name, equals('Casa de Praia'));
      expect(cubit.state.userHouses.length, equals(initialCount + 1));
      expect(cubit.state.userHouses.any((h) => h.name == 'Casa de Praia'), isTrue);
    });

    test('switchHouse alterna perfeitamente entre as casas existentes', () async {
      await cubit.signInWithEmailPassword('carlos@omnilar.com', '123456');
      final firstHouseId = cubit.state.house!.id;

      await cubit.createHouse(name: 'Casa de Campo', cycleStartDay: 15);
      final secondHouseId = cubit.state.house!.id;

      expect(cubit.state.house?.id, equals(secondHouseId));
      expect(cubit.state.house?.name, equals('Casa de Campo'));

      // Alterna de volta para a primeira casa
      await cubit.switchHouse(firstHouseId);
      expect(cubit.state.house?.id, equals(firstHouseId));
      expect(cubit.state.house?.name, equals('Nossa Casa'));

      // Alterna novamente para a segunda casa
      await cubit.switchHouse(secondHouseId);
      expect(cubit.state.house?.id, equals(secondHouseId));
      expect(cubit.state.house?.name, equals('Casa de Campo'));
    });

    test('Persistência da última casa selecionada é lembrada no login seguinte', () async {
      // 1. Loga e cria uma segunda casa
      await cubit.signInWithEmailPassword('carlos@omnilar.com', '123456');
      await cubit.createHouse(name: 'Sítio Recanto', cycleStartDay: 1);
      final sitioId = cubit.state.house!.id;

      // 2. Faz logout
      await cubit.signOut();
      expect(cubit.state.status, equals(AuthStatus.unauthenticated));

      // 3. Faz login novamente e confere se abriu o Sítio (última selecionada)
      await cubit.signInWithEmailPassword('carlos@omnilar.com', '123456');
      expect(cubit.state.house?.id, equals(sitioId));
      expect(cubit.state.house?.name, equals('Sítio Recanto'));
    });

    test('Não permite arquivar, excluir ou sair se o usuário tiver apenas uma casa ativa', () async {
      await cubit.signInWithEmailPassword('carlos@omnilar.com', '123456');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(cubit.state.userHouses.length, equals(1));
      final soleHouseId = cubit.state.house!.id;

      // 1. Tentar arquivar a única casa
      await cubit.archiveHouse(soleHouseId);
      expect(cubit.state.status, equals(AuthStatus.failure));
      expect(cubit.state.errorMessage, contains('Você precisa ter pelo menos uma casa ativa'));
      expect(cubit.state.house?.id, equals(soleHouseId));

      // 2. Tentar excluir a única casa
      await cubit.deleteHouse(soleHouseId);
      expect(cubit.state.status, equals(AuthStatus.failure));
      expect(cubit.state.errorMessage, contains('Você precisa ter pelo menos uma casa ativa'));
      expect(cubit.state.house?.id, equals(soleHouseId));

      // 3. Tentar sair da única casa
      await cubit.leaveHouse(soleHouseId);
      expect(cubit.state.status, equals(AuthStatus.failure));
      expect(cubit.state.errorMessage, contains('Você precisa ter pelo menos uma casa ativa'));
      expect(cubit.state.house?.id, equals(soleHouseId));
    });

    test('Arquivar casa secundária oculta ela da lista e mantém a casa ativa atual', () async {
      await cubit.signInWithEmailPassword('carlos@omnilar.com', '123456');
      final mainHouseId = cubit.state.house!.id;

      await cubit.createHouse(name: 'Casa Temporária', cycleStartDay: 5);
      final tempHouseId = cubit.state.house!.id;

      // Alterna de volta para a principal
      await cubit.switchHouse(mainHouseId);
      expect(cubit.state.userHouses.length, equals(2));

      // Arquiva a casa secundária
      await cubit.archiveHouse(tempHouseId);
      expect(cubit.state.status, equals(AuthStatus.authenticatedWithHouse));
      expect(cubit.state.house?.id, equals(mainHouseId));
      expect(cubit.state.userHouses.length, equals(1));
      expect(cubit.state.userHouses.any((h) => h.id == tempHouseId), isFalse);
    });

    test('Arquivar a casa ativa atual seleciona automaticamente a próxima casa ativa', () async {
      await cubit.signInWithEmailPassword('carlos@omnilar.com', '123456');
      final firstHouseId = cubit.state.house!.id;

      await cubit.createHouse(name: 'Casa Montanha', cycleStartDay: 10);
      final secondHouseId = cubit.state.house!.id;

      // Arquiva a casa ativa atual (Casa Montanha)
      await cubit.archiveHouse(secondHouseId);
      expect(cubit.state.status, equals(AuthStatus.authenticatedWithHouse));
      expect(cubit.state.house?.id, equals(firstHouseId));
      expect(cubit.state.house?.name, equals('Nossa Casa'));
      expect(cubit.state.userHouses.length, equals(1));
    });

    test('Excluir permanentemente a casa ativa remove-a e seleciona a próxima casa', () async {
      await cubit.signInWithEmailPassword('carlos@omnilar.com', '123456');
      final firstHouseId = cubit.state.house!.id;

      await cubit.createHouse(name: 'Casa para Exclusão', cycleStartDay: 10);
      final toDeleteId = cubit.state.house!.id;

      // Exclui a casa
      await cubit.deleteHouse(toDeleteId);
      expect(cubit.state.status, equals(AuthStatus.authenticatedWithHouse));
      expect(cubit.state.house?.id, equals(firstHouseId));
      expect(cubit.state.userHouses.any((h) => h.id == toDeleteId), isFalse);
    });
  });
}
