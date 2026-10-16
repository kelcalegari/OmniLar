import 'dart:async';
import '../../domain/entities/user_profile.dart';
import '../../domain/entities/house.dart';
import '../../domain/entities/house_member_info.dart';
import '../../../../core/errors/failures.dart';
import 'auth_datasource.dart';

class MockAuthDataSource implements AuthDataSource {
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
      pixKey: 'carlos@omnilar.com',
    ),
    'marina@omnilar.com': const UserProfile(
      id: 'member_marina',
      email: 'marina@omnilar.com',
      fullName: 'Marina Silva',
      avatarUrl: null,
      phone: '(11) 91234-5678',
      pixKey: 'marina@omnilar.com',
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
      pixKey: 'financeiro.nossacasa@banco.com',
      pixKeyType: 'email',
      pixKeyHolderName: 'Caixa Nossa Casa',
      pixKeyBank: 'Nubank',
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
  final Map<String, String> _invites = {'LAR123': 'house_nossa_casa'};

  UserProfile? _currentUser;
  House? _currentHouse;

  /// Simula o Supabase com a confirmação de e-mail ligada: o cadastro só
  /// abre a sessão depois do código [mockConfirmationCode].
  final bool requireEmailConfirmation;
  static const mockConfirmationCode = '123456';
  final Set<String> _unconfirmedEmails = {};

  MockAuthDataSource({
    bool startAuthenticated = true,
    this.requireEmailConfirmation = false,
  }) {
    if (startAuthenticated) {
      _currentUser = _users['carlos@omnilar.com'];
      _currentHouse = _houses['house_nossa_casa'];
    } else {
      _currentUser = null;
      _currentHouse = null;
    }
  }

  @override
  Stream<UserProfile?> get authStateChanges => _authStateController.stream;
  @override
  Stream<House?> get houseChanges => _houseStateController.stream;

  @override
  UserProfile? get currentUser => _currentUser;
  @override
  House? get currentHouse => _currentHouse;
  @override
  bool get isDemoMode => true;
  @override
  bool get isRestoringSession => false;

  @override
  Future<UserProfile> signInWithEmailPassword(
    String email,
    String password,
  ) async {
    await Future.delayed(const Duration(milliseconds: 300));
    final normalizedEmail = email.trim().toLowerCase();

    final user = _users[normalizedEmail];
    final savedPassword = _passwords[normalizedEmail];

    if (user == null || savedPassword != password) {
      throw const AuthFailure('E-mail ou senha inválidos.');
    }
    if (_unconfirmedEmails.contains(normalizedEmail)) {
      throw EmailNotConfirmedFailure(normalizedEmail);
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

  @override
  Future<UserProfile?> signUpWithEmailPassword({
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

    if (requireEmailConfirmation) {
      _unconfirmedEmails.add(normalizedEmail);
      return null;
    }

    _currentUser = newUser;
    _currentHouse = null;
    _authStateController.add(_currentUser);
    _houseStateController.add(null);

    return newUser;
  }

  @override
  Future<UserProfile> verifySignUpCode({
    required String email,
    required String code,
  }) async {
    await Future.delayed(const Duration(milliseconds: 200));
    final normalizedEmail = email.trim().toLowerCase();
    final user = _users[normalizedEmail];
    if (user == null || code.trim() != mockConfirmationCode) {
      throw const AuthFailure('Código inválido ou expirado. Peça um novo.');
    }
    _unconfirmedEmails.remove(normalizedEmail);
    _currentUser = user;
    _currentHouse = null;
    _authStateController.add(_currentUser);
    _houseStateController.add(null);
    return user;
  }

  @override
  Future<void> resendSignUpCode(String email) async {
    await Future.delayed(const Duration(milliseconds: 100));
  }

  @override
  Future<void> requestPasswordReset(String email) async {
    // Como no Supabase: responde igual exista a conta ou não
    await Future.delayed(const Duration(milliseconds: 100));
  }

  @override
  Future<UserProfile> resetPasswordWithCode({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    await Future.delayed(const Duration(milliseconds: 200));
    final normalizedEmail = email.trim().toLowerCase();
    final user = _users[normalizedEmail];
    if (user == null || code.trim() != mockConfirmationCode) {
      throw const AuthFailure('Código inválido ou expirado. Peça um novo.');
    }
    _passwords[normalizedEmail] = newPassword;
    // O código chega por e-mail, então também confirma a conta
    _unconfirmedEmails.remove(normalizedEmail);

    _currentUser = user;
    _authStateController.add(_currentUser);
    final userHouses = await getUserHouses();
    _currentHouse = userHouses.isNotEmpty ? userHouses.first : null;
    _houseStateController.add(_currentHouse);
    return user;
  }

  String? _pendingEmailChange;

  @override
  String? get pendingEmailChange => _pendingEmailChange;

  @override
  List<String> get signInProviders => const ['email'];

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    await Future.delayed(const Duration(milliseconds: 150));
    final email = _currentUser?.email;
    if (email == null) throw const AuthFailure('Usuário não autenticado.');
    if (_passwords[email] != currentPassword) {
      throw const AuthFailure('Senha atual incorreta.');
    }
    if (currentPassword == newPassword) {
      throw const AuthFailure('A nova senha precisa ser diferente da atual.');
    }
    _passwords[email] = newPassword;
  }

  @override
  Future<void> requestEmailChange(String newEmail) async {
    await Future.delayed(const Duration(milliseconds: 150));
    final normalized = newEmail.trim().toLowerCase();
    if (_currentUser == null) throw const AuthFailure('Usuário não autenticado.');
    if (normalized == _currentUser!.email) {
      throw const AuthFailure('Este já é o seu e-mail de acesso.');
    }
    if (_users.containsKey(normalized)) {
      throw const AuthFailure('Este e-mail já tem uma conta. Entre com sua senha.');
    }
    _pendingEmailChange = normalized;
  }

  @override
  Future<bool> confirmEmailChange({
    required String email,
    required String code,
  }) async {
    await Future.delayed(const Duration(milliseconds: 150));
    final pending = _pendingEmailChange;
    final user = _currentUser;
    if (pending == null || user == null || code.trim() != mockConfirmationCode) {
      throw const AuthFailure('Código inválido ou expirado. Peça um novo.');
    }
    _users.remove(user.email);
    final password = _passwords.remove(user.email);
    _currentUser = user.copyWith(email: pending);
    _users[pending] = _currentUser!;
    if (password != null) _passwords[pending] = password;
    _pendingEmailChange = null;
    _authStateController.add(_currentUser);
    return true;
  }

  @override
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

  @override
  Future<void> signOut() async {
    await Future.delayed(const Duration(milliseconds: 100));
    _currentUser = null;
    _currentHouse = null;
    _authStateController.add(null);
    _houseStateController.add(null);
  }

  @override
  Future<UserProfile> updateProfile({
    required String fullName,
    String? email,
    String? pixKey,
  }) async {
    await Future.delayed(const Duration(milliseconds: 150));
    if (_currentUser == null) {
      throw const AuthFailure('Usuário não autenticado.');
    }

    final trimmedName = fullName.trim();
    final trimmedEmail = email?.trim().toLowerCase();
    final currentOldEmail = _currentUser!.email.toLowerCase();

    if (trimmedEmail != null &&
        trimmedEmail.isNotEmpty &&
        trimmedEmail != currentOldEmail) {
      if (_users.containsKey(trimmedEmail)) {
        throw const AuthFailure('Este e-mail já está em uso.');
      }
      final pass = _passwords.remove(currentOldEmail) ?? '123456';
      _passwords[trimmedEmail] = pass;
      _users.remove(currentOldEmail);
    }

    final updatedEmail = (trimmedEmail != null && trimmedEmail.isNotEmpty)
        ? trimmedEmail
        : _currentUser!.email;

    final updatedUser = _currentUser!.copyWith(
      fullName: trimmedName,
      email: updatedEmail,
      pixKey: pixKey != null ? pixKey.trim() : _currentUser!.pixKey,
    );

    _users[updatedEmail] = updatedUser;
    _currentUser = updatedUser;

    for (final houseId in _houseMembers.keys) {
      final members = _houseMembers[houseId]!;
      for (int i = 0; i < members.length; i++) {
        if (members[i].userId == updatedUser.id) {
          members[i] = HouseMemberInfo(
            id: members[i].id,
            houseId: members[i].houseId,
            userId: members[i].userId,
            role: members[i].role,
            joinedAt: members[i].joinedAt,
            profile: updatedUser,
          );
        }
      }
    }

    _authStateController.add(_currentUser);
    return updatedUser;
  }

  @override
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

  @override
  Future<House> createHouse({
    required String name,
    int cycleStartDay = 5,
  }) async {
    if (_currentUser == null) {
      throw const AuthFailure(
        'Você precisa estar autenticado para criar uma casa.',
      );
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
    final inviteCode =
        'LAR${DateTime.now().millisecondsSinceEpoch.toString().substring(7, 10)}';
    _invites[inviteCode] = houseId;

    _currentHouse = newHouse;
    _houseStateController.add(_currentHouse);

    return newHouse;
  }

  @override
  Future<House> updateHouse({
    required String houseId,
    String? name,
    int? cycleStartDay,
    String? pixKey,
    String? pixKeyType,
    String? pixKeyHolderName,
    String? pixKeyBank,
  }) async {
    await Future.delayed(const Duration(milliseconds: 150));
    final existing = _houses[houseId];
    if (existing == null) throw const NotFoundFailure('Casa não encontrada.');

    // Como no banco: a troca do dia vale a partir do fim do ciclo em andamento
    var schedule = existing.cycleSchedule;
    if (cycleStartDay != null && cycleStartDay != existing.cycleStartDay) {
      schedule = schedule.withChange(schedule.planChange(DateTime.now(), cycleStartDay));
    }

    final updated = existing.copyWith(
      name: name ?? existing.name,
      cycleStartDay: schedule.currentDay,
      cycleDayChanges: schedule.changes,
      pixKey: pixKey ?? existing.pixKey,
      pixKeyType: pixKeyType ?? existing.pixKeyType,
      pixKeyHolderName: pixKeyHolderName ?? existing.pixKeyHolderName,
      pixKeyBank: pixKeyBank ?? existing.pixKeyBank,
    );
    _houses[houseId] = updated;

    if (_currentHouse?.id == houseId) {
      _currentHouse = updated;
      _houseStateController.add(_currentHouse);
    }
    return updated;
  }

  @override
  Future<House> joinHouseWithInvite(String inviteCode) async {
    if (_currentUser == null) {
      throw const AuthFailure(
        'Você precisa estar autenticado para entrar em uma casa.',
      );
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

  @override
  Future<void> selectHouse(String houseId) async {
    final house = _houses[houseId];
    if (house == null) throw const NotFoundFailure('Casa não encontrada.');
    _currentHouse = house;
    _houseStateController.add(_currentHouse);
  }

  @override
  Future<List<HouseMemberInfo>> getHouseMembers(String houseId) async {
    return _houseMembers[houseId] ?? [];
  }

  @override
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
