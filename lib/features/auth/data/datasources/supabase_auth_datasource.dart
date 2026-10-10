import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/errors/failures.dart';
import '../../domain/entities/user_profile.dart';
import '../../domain/entities/house.dart';
import '../../domain/entities/house_member_info.dart';
import 'auth_datasource.dart';

class SupabaseAuthDataSource implements AuthDataSource {
  final SupabaseClient _client;
  final _authStateController = StreamController<UserProfile?>.broadcast();
  final _houseStateController = StreamController<House?>.broadcast();

  UserProfile? _currentUser;
  House? _currentHouse;

  SupabaseAuthDataSource(this._client) {
    _initAuthStateListener();
  }

  void _initAuthStateListener() {
    _client.auth.onAuthStateChange.listen((data) async {
      final user = data.session?.user;
      if (user == null) {
        _currentUser = null;
        _currentHouse = null;
        _authStateController.add(null);
        _houseStateController.add(null);
      } else {
        await _loadProfileAndHouse(user);
      }
    });

    final initialUser = _client.auth.currentUser;
    if (initialUser != null) {
      _loadProfileAndHouse(initialUser);
    }
  }

  Future<void> _loadProfileAndHouse(User user) async {
    try {
      final profileRow = await _client
          .from('profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();

      final fullName = (profileRow != null && profileRow['full_name'] != null)
          ? profileRow['full_name'] as String
          : (user.userMetadata?['full_name'] as String? ?? user.email ?? 'Usuário');

      _currentUser = UserProfile(
        id: user.id,
        email: user.email ?? '',
        fullName: fullName,
        avatarUrl: profileRow?['avatar_url'] as String?,
        phone: profileRow?['phone'] as String?,
      );
      _authStateController.add(_currentUser);

      final houses = await getUserHouses();
      if (houses.isNotEmpty) {
        _currentHouse = houses.first;
        _houseStateController.add(_currentHouse);
      } else {
        _currentHouse = null;
        _houseStateController.add(null);
      }
    } catch (_) {
      _currentUser = UserProfile(
        id: user.id,
        email: user.email ?? '',
        fullName: user.userMetadata?['full_name'] as String? ?? user.email ?? 'Usuário',
      );
      _authStateController.add(_currentUser);
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
  Future<UserProfile> signInWithEmailPassword(String email, String password) async {
    try {
      final res = await _client.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );

      final user = res.user;
      if (user == null) {
        throw const AuthFailure('Falha na autenticação: usuário não encontrado.');
      }

      await _loadProfileAndHouse(user);
      return _currentUser ?? UserProfile(id: user.id, email: user.email ?? '', fullName: email);
    } on AuthException catch (e) {
      throw AuthFailure(e.message);
    } catch (e) {
      throw AuthFailure('Erro ao fazer login: $e');
    }
  }

  @override
  Future<UserProfile> signUpWithEmailPassword({
    required String email,
    required String password,
    required String fullName,
  }) async {
    try {
      final res = await _client.auth.signUp(
        email: email.trim(),
        password: password,
        data: {'full_name': fullName.trim()},
      );

      final user = res.user;
      if (user == null) {
        throw const AuthFailure('Falha ao criar conta: tente novamente.');
      }

      // Upsert inicial no profile
      await _client.from('profiles').upsert({
        'id': user.id,
        'full_name': fullName.trim(),
      });

      if (res.session == null) {
        try {
          final loginRes = await _client.auth.signInWithPassword(
            email: email.trim(),
            password: password,
          );
          if (loginRes.user != null) {
            await _loadProfileAndHouse(loginRes.user!);
            return _currentUser ?? UserProfile(id: loginRes.user!.id, email: email, fullName: fullName);
          }
        } catch (_) {}
      }

      await _loadProfileAndHouse(user);
      return _currentUser ?? UserProfile(id: user.id, email: user.email ?? '', fullName: fullName);
    } on AuthException catch (e) {
      throw AuthFailure(e.message);
    } catch (e) {
      throw AuthFailure('Erro ao cadastrar usuário: $e');
    }
  }

  @override
  Future<void> signInDemo({required String memberId}) async {
    // Modo demo com sessão local provisória caso sem rede Supabase
    _currentUser = UserProfile(
      id: memberId,
      email: memberId == 'member_carlos' ? 'carlos@omnilar.com' : 'marina@omnilar.com',
      fullName: memberId == 'member_carlos' ? 'Carlos Eduardo' : 'Marina Silva',
    );
    _authStateController.add(_currentUser);

    final houses = await getUserHouses();
    _currentHouse = houses.isNotEmpty ? houses.first : const House(
      id: 'house_nossa_casa',
      name: 'Nossa Casa',
      cycleStartDay: 5,
      timezone: 'America/Sao_Paulo',
      createdBy: 'member_carlos',
    );
    _houseStateController.add(_currentHouse);
  }

  @override
  Future<void> signOut() async {
    await _client.auth.signOut();
    _currentUser = null;
    _currentHouse = null;
    _authStateController.add(null);
    _houseStateController.add(null);
  }

  @override
  Future<List<House>> getUserHouses() async {
    final userId = _currentUser?.id ?? _client.auth.currentUser?.id;
    if (userId == null) return [];

    try {
      final rows = await _client
          .from('house_members')
          .select('house:houses(*)')
          .eq('user_id', userId);

      final houses = <House>[];
      for (final r in rows) {
        final h = r['house'] as Map<String, dynamic>?;
        if (h != null) {
          houses.add(House(
            id: h['id'] as String,
            name: h['name'] as String,
            cycleStartDay: (h['cycle_start_day'] as num?)?.toInt() ?? 5,
            timezone: h['timezone'] as String? ?? 'America/Sao_Paulo',
            createdBy: h['created_by'] as String? ?? userId,
          ));
        }
      }
      return houses;
    } catch (_) {
      return [];
    }
  }

  @override
  Future<House> createHouse({
    required String name,
    int cycleStartDay = 5,
  }) async {
    final userId = _currentUser?.id ?? _client.auth.currentUser?.id;
    if (userId == null) {
      throw const AuthFailure('Usuário precisa estar autenticado para criar uma casa.');
    }

    try {
      // 1. Tenta criar através da RPC atômica segura (evita conflito de RLS entre houses e house_members)
      try {
        final rpcResult = await _client.rpc('create_house_with_owner', params: {
          'p_name': name.trim(),
          'p_cycle_start_day': cycleStartDay,
        });

        if (rpcResult != null) {
          final houseMap = rpcResult as Map<String, dynamic>;
          final house = House(
            id: houseMap['id'] as String,
            name: houseMap['name'] as String,
            cycleStartDay: (houseMap['cycle_start_day'] as num?)?.toInt() ?? cycleStartDay,
            timezone: houseMap['timezone'] as String? ?? 'America/Sao_Paulo',
            createdBy: userId,
          );

          _currentHouse = house;
          _houseStateController.add(_currentHouse);
          return house;
        }
      } catch (_) {
        // Segue para fallback direto caso a RPC ainda não tenha sido executada no SQL Editor
      }

      // 2. Inserção direta nas tabelas
      final houseRow = await _client.from('houses').insert({
        'name': name.trim(),
        'cycle_start_day': cycleStartDay,
        'created_by': userId,
      }).select().single();

      final houseId = houseRow['id'] as String;

      // Adiciona o criador como membro owner
      await _client.from('house_members').insert({
        'house_id': houseId,
        'user_id': userId,
        'role': 'owner',
        'default_split_percent': 50.0,
      });

      final house = House(
        id: houseId,
        name: houseRow['name'] as String,
        cycleStartDay: (houseRow['cycle_start_day'] as num?)?.toInt() ?? cycleStartDay,
        timezone: houseRow['timezone'] as String? ?? 'America/Sao_Paulo',
        createdBy: userId,
      );

      _currentHouse = house;
      _houseStateController.add(_currentHouse);
      return house;
    } catch (e) {
      throw ServerFailure('Erro ao criar casa: $e');
    }
  }

  @override
  Future<House> joinHouseWithInvite(String inviteCode) async {
    final userId = _currentUser?.id ?? _client.auth.currentUser?.id;
    if (userId == null) {
      throw const AuthFailure('Usuário precisa estar autenticado.');
    }

    try {
      // Procura convite ativo
      final invite = await _client
          .from('house_invites')
          .select()
          .eq('code', inviteCode.trim().toUpperCase())
          .maybeSingle();

      if (invite == null) {
        throw const AuthFailure('Código de convite inválido ou expirado.');
      }

      final houseId = invite['house_id'] as String;

      await _client.from('house_members').insert({
        'house_id': houseId,
        'user_id': userId,
        'role': 'member',
        'default_split_percent': 50.0,
      });

      final houseRow = await _client.from('houses').select().eq('id', houseId).single();
      final house = House(
        id: houseRow['id'] as String,
        name: houseRow['name'] as String,
        cycleStartDay: (houseRow['cycle_start_day'] as num?)?.toInt() ?? 5,
        timezone: houseRow['timezone'] as String? ?? 'America/Sao_Paulo',
        createdBy: houseRow['created_by'] as String? ?? '',
      );

      _currentHouse = house;
      _houseStateController.add(_currentHouse);
      return house;
    } catch (e) {
      if (e is AuthFailure) rethrow;
      throw ServerFailure('Erro ao entrar na casa: $e');
    }
  }

  @override
  Future<void> selectHouse(String houseId) async {
    final houses = await getUserHouses();
    final match = houses.where((h) => h.id == houseId).firstOrNull;
    if (match != null) {
      _currentHouse = match;
      _houseStateController.add(_currentHouse);
    }
  }

  @override
  Future<List<HouseMemberInfo>> getHouseMembers(String houseId) async {
    try {
      final rows = await _client
          .from('house_members')
          .select('id, house_id, user_id, role, joined_at, profile:profiles(*)')
          .eq('house_id', houseId);

      return rows.map((r) {
        final prof = r['profile'] as Map<String, dynamic>?;
        return HouseMemberInfo(
          id: r['id'] as String,
          houseId: r['house_id'] as String,
          userId: r['user_id'] as String,
          role: r['role'] as String? ?? 'member',
          joinedAt: DateTime.tryParse(r['joined_at'] as String? ?? '') ?? DateTime.now(),
          profile: UserProfile(
            id: r['user_id'] as String,
            email: prof?['email'] as String? ?? '',
            fullName: prof?['full_name'] as String? ?? 'Membro',
            avatarUrl: prof?['avatar_url'] as String?,
            phone: prof?['phone'] as String?,
          ),
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Future<String> createHouseInvite(String houseId) async {
    try {
      final code = 'LAR${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';
      await _client.from('house_invites').insert({
        'house_id': houseId,
        'code': code,
      });
      return code;
    } catch (e) {
      return 'LAR${houseId.hashCode.abs().toString().padLeft(6, '0').substring(0, 6)}';
    }
  }
}
