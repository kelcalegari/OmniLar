import 'dart:async';
import '../../domain/entities/user_profile.dart';
import '../../domain/entities/house.dart';
import '../../domain/entities/house_member_info.dart';
import '../../../../core/errors/failures.dart';

class MockAuthDataSource {
  final _authStateController = StreamController<UserProfile?>.broadcast();
  final _houseStateController = StreamController<House?>.broadcast();

  // Membros pré-cadastrados (Carlos e Marina)
  final Map<String, UserProfile> _users = {
    'carlos@omnilar.com': const UserProfile(
      id: 'member_carlos',
      email: 'carlos@omnilar.com',
      fullName: 'Carlos Eduardo',
      avatarUrl: null,
      phone: '(11) 98765-4321',
    ),
    'marina@omnilar.com': const UserProfile(
      id: 'member_marina',
      email: 'marina@omnilar.com',
      fullName: 'Marina Silva',
      avatarUrl: null,
      phone: '(11) 91234-5678',
    ),
  };

  final Map<String, String> _passwords = {
    'carlos@omnilar.com': '123456',
    'marina@omnilar.com': '123456',
  };

  // Casas cadastradas
  final Map<String, House> _houses = {
    'house_nossa_casa': const House(
      id: 'house_nossa_casa',
      name: 'Nossa Casa',
      cycleStartDay: 5,
      timezone: 'America/Sao_Paulo',
      createdBy: 'member_carlos',
    ),
  };

  // Membros vinculados a casas: houseId -> List<HouseMemberInfo>
  final Map<String, List<HouseMemberInfo>> _houseMembers = {
    'house_nossa_casa': [
      HouseMemberInfo(
        id: 'member_info_carlos',
        houseId: 'house_nossa_casa',
        userId: 'member_carlos',
        role: 'owner',
        joinedAt: DateTime(2026, 1, 1),
        profile: const UserProfile(
          id: 'member_carlos',
          email: 'carlos@omnilar.com',
          fullName: 'Carlos Eduardo',
        ),
      ),
      HouseMemberInfo(
        id: 'member_info_marina',
        houseId: 'house_nossa_casa',
        userId: 'member_marina',
        role: 'admin',
        joinedAt: DateTime(2026, 1, 2),
        profile: const UserProfile(
          id: 'member_marina',
          email: 'marina@omnilar.com',
          fullName: 'Marina Silva',
        ),
      ),
    ],
  };

  // Códigos de convite: code -> houseId
  final Map<String, String> _invites = {
    'LAR123': 'house_nossa_casa',
  };

  UserProfile? _currentUser;
  House? _currentHouse;

  MockAuthDataSource({bool startAuthenticated = true}) {
    if (startAuthenticated) {
      _currentUser = _users['carlos@omnilar.com'];
      _currentHouse = _houses['house_nossa_casa'];
    } else {
      _currentUser = null;
      _currentHouse = null;
    }
  }

  Stream<UserProfile?> get authStateChanges => _authStateController.stream;
  Stream<House?> get houseChanges => _houseStateController.stream;

  UserProfile? get currentUser => _currentUser;
  House? get currentHouse => _currentHouse;

  Future<UserProfile> signInWithEmailPassword(String email, String password) async {
    await Future.delayed(const Duration(milliseconds: 300));
    final normalizedEmail = email.trim().toLowerCase();

    final user = _users[normalizedEmail];
    final savedPassword = _passwords[normalizedEmail];

    if (user == null || savedPassword != password) {
      throw const AuthFailure('E-mail ou senha inválidos.');
    }

    _currentUser = user;
    _authStateController.add(_currentUser);

    // Seleciona primeira casa encontrada
    final userHouses = await getUserHouses();
    if (userHouses.isNotEmpty) {
      _currentHouse = userHouses.first;
      _houseStateController.add(_currentHouse);
    } else {
      _currentHouse = null;
      _houseStateController.add(null);
    }

    return user;
  }

  Future<UserProfile> signUpWithEmailPassword({
    required String email,
    required String password,
    required String fullName,
  }) async {
    await Future.delayed(const Duration(milliseconds: 300));
    final normalizedEmail = email.trim().toLowerCase();

    if (_users.containsKey(normalizedEmail)) {
      throw const AuthFailure('Este e-mail já está em uso.');
    }

    final newId = 'user_${DateTime.now().millisecondsSinceEpoch}';
    final newUser = UserProfile(
      id: newId,
      email: normalizedEmail,
      fullName: fullName.trim(),
    );

    _users[normalizedEmail] = newUser;
    _passwords[normalizedEmail] = password;

    _currentUser = newUser;
    _currentHouse = null;
    _authStateController.add(_currentUser);
    _houseStateController.add(null);

    return newUser;
  }

  Future<void> signInDemo({required String memberId}) async {
    await Future.delayed(const Duration(milliseconds: 200));
    final user = _users.values.firstWhere(
      (u) => u.id == memberId,
      orElse: () => _users['carlos@omnilar.com']!,
    );

    _currentUser = user;
    _currentHouse = _houses['house_nossa_casa'];
    _authStateController.add(_currentUser);
    _houseStateController.add(_currentHouse);
  }

  Future<void> signOut() async {
    await Future.delayed(const Duration(milliseconds: 100));
    _currentUser = null;
    _currentHouse = null;
    _authStateController.add(null);
    _houseStateController.add(null);
  }

  Future<List<House>> getUserHouses() async {
    if (_currentUser == null) return [];
    final userId = _currentUser!.id;

    final userHouseIds = <String>{};
    for (final entry in _houseMembers.entries) {
      if (entry.value.any((m) => m.userId == userId)) {
        userHouseIds.add(entry.key);
      }
    }

    return userHouseIds.map((id) => _houses[id]!).toList();
  }

  Future<House> createHouse({
    required String name,
    int cycleStartDay = 5,
  }) async {
    if (_currentUser == null) {
      throw const AuthFailure('Você precisa estar autenticado para criar uma casa.');
    }

    await Future.delayed(const Duration(milliseconds: 300));
    final houseId = 'house_${DateTime.now().millisecondsSinceEpoch}';
    final newHouse = House(
      id: houseId,
      name: name.trim(),
      cycleStartDay: cycleStartDay,
      createdBy: _currentUser!.id,
    );

    _houses[houseId] = newHouse;

    final memberInfo = HouseMemberInfo(
      id: 'member_info_${DateTime.now().millisecondsSinceEpoch}',
      houseId: houseId,
      userId: _currentUser!.id,
      role: 'owner',
      joinedAt: DateTime.now(),
      profile: _currentUser,
    );

    _houseMembers[houseId] = [memberInfo];

    // Gera um código de convite padrão
    final inviteCode = 'LAR${DateTime.now().millisecondsSinceEpoch.toString().substring(7, 10)}';
    _invites[inviteCode] = houseId;

    _currentHouse = newHouse;
    _houseStateController.add(_currentHouse);

    return newHouse;
  }

  Future<House> joinHouseWithInvite(String inviteCode) async {
    if (_currentUser == null) {
      throw const AuthFailure('Você precisa estar autenticado para entrar em uma casa.');
    }

    await Future.delayed(const Duration(milliseconds: 300));
    final normalizedCode = inviteCode.trim().toUpperCase();
    final houseId = _invites[normalizedCode];

    if (houseId == null || !_houses.containsKey(houseId)) {
      throw const NotFoundFailure('Código de convite inválido ou expirado.');
    }

    final house = _houses[houseId]!;
    final currentMembers = _houseMembers[houseId] ?? [];

    if (!currentMembers.any((m) => m.userId == _currentUser!.id)) {
      final newMember = HouseMemberInfo(
        id: 'member_info_${DateTime.now().millisecondsSinceEpoch}',
        houseId: houseId,
        userId: _currentUser!.id,
        role: 'member',
        joinedAt: DateTime.now(),
        profile: _currentUser,
      );
      currentMembers.add(newMember);
      _houseMembers[houseId] = currentMembers;
    }

    _currentHouse = house;
    _houseStateController.add(_currentHouse);

    return house;
  }

  Future<void> selectHouse(String houseId) async {
    final house = _houses[houseId];
    if (house == null) throw const NotFoundFailure('Casa não encontrada.');
    _currentHouse = house;
    _houseStateController.add(_currentHouse);
  }

  Future<List<HouseMemberInfo>> getHouseMembers(String houseId) async {
    return _houseMembers[houseId] ?? [];
  }

  Future<String> createHouseInvite(String houseId) async {
    // Retorna código existente ou gera um novo
    for (final entry in _invites.entries) {
      if (entry.value == houseId) return entry.key;
    }
    final code = 'LAR${(100 + _invites.length).toString()}';
    _invites[code] = houseId;
    return code;
  }

  void dispose() {
    _authStateController.close();
    _houseStateController.close();
  }
}
