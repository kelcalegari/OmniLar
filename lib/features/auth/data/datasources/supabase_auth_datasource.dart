import '../../../../core/domain/value_objects/cycle_schedule.dart';
import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
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
  bool _isDemoMode = false;
  bool _isRestoringSession = false;

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
      // Sessão salva: só avisa quem escuta depois que perfil e casa chegarem
      _isRestoringSession = true;
      // Com limite de tempo: rede lenta não pode prender o app na tela de abertura
      _loadProfileAndHouse(initialUser)
          .timeout(const Duration(seconds: 8))
          .catchError((_) {})
          .whenComplete(() {
        _isRestoringSession = false;
        _authStateController.add(_currentUser);
      });
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
          : (user.userMetadata?['full_name'] as String? ??
                user.email ??
                'Usuário');

      _currentUser = UserProfile(
        id: user.id,
        email: user.email ?? '',
        fullName: fullName,
        avatarUrl: profileRow?['avatar_url'] as String?,
        phone: profileRow?['phone'] as String?,
        pixKey: profileRow?['pix_key'] as String?,
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
        fullName:
            user.userMetadata?['full_name'] as String? ??
            user.email ??
            'Usuário',
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
  bool get isDemoMode => _isDemoMode;

  @override
  bool get isRestoringSession => _isRestoringSession;

  @override
  Future<UserProfile> signInWithEmailPassword(
    String email,
    String password,
  ) async {
    _isDemoMode = false;
    try {
      final res = await _client.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );

      final user = res.user;
      if (user == null) {
        throw const AuthFailure(
          'Falha na autenticação: usuário não encontrado.',
        );
      }

      await _loadProfileAndHouse(user);
      return _currentUser ??
          UserProfile(id: user.id, email: user.email ?? '', fullName: email);
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
    _isDemoMode = false;
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
            return _currentUser ??
                UserProfile(
                  id: loginRes.user!.id,
                  email: email,
                  fullName: fullName,
                );
          }
        } catch (_) {}
      }

      await _loadProfileAndHouse(user);
      return _currentUser ??
          UserProfile(id: user.id, email: user.email ?? '', fullName: fullName);
    } on AuthException catch (e) {
      throw AuthFailure(e.message);
    } catch (e) {
      throw AuthFailure('Erro ao cadastrar usuário: $e');
    }
  }

  @override
  Future<void> signInDemo({required String memberId}) async {
    _isDemoMode = true;
    // Modo demo com sessão local provisória caso sem rede Supabase
    _currentUser = UserProfile(
      id: memberId,
      email: memberId == 'member_carlos'
          ? 'carlos@omnilar.com'
          : 'marina@omnilar.com',
      fullName: memberId == 'member_carlos' ? 'Carlos Eduardo' : 'Marina Silva',
    );
    _authStateController.add(_currentUser);

    final houses = await getUserHouses();
    _currentHouse = houses.isNotEmpty
        ? houses.first
        : const House(
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
    _isDemoMode = false;
    await _client.auth.signOut();
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
    final trimmedName = fullName.trim();
    final trimmedEmail = email?.trim();
    final trimmedPixKey = pixKey?.trim();

    if (_isDemoMode) {
      final updatedEmail = (trimmedEmail != null && trimmedEmail.isNotEmpty)
          ? trimmedEmail
          : (_currentUser?.email ?? '');
      _currentUser =
          _currentUser?.copyWith(
            fullName: trimmedName,
            email: updatedEmail,
            pixKey: pixKey != null ? (trimmedPixKey!.isEmpty ? null : trimmedPixKey) : _currentUser?.pixKey,
          ) ??
          UserProfile(
            id: 'member_demo',
            email: updatedEmail,
            fullName: trimmedName,
            pixKey: (trimmedPixKey != null && trimmedPixKey.isNotEmpty) ? trimmedPixKey : null,
          );
      _authStateController.add(_currentUser);
      return _currentUser!;
    }

    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthFailure('Usuário não autenticado.');
    }

    try {
      final emailChanged =
          trimmedEmail != null &&
          trimmedEmail.isNotEmpty &&
          trimmedEmail.toLowerCase() != (user.email ?? '').toLowerCase();

      String activeEmail = _currentUser?.email ?? user.email ?? '';

      if (emailChanged) {
        final updateRes = await _client.auth.updateUser(
          UserAttributes(email: trimmedEmail, data: {'full_name': trimmedName}),
        );
        if (updateRes.user?.email != null) {
          activeEmail = updateRes.user!.email!;
        }
      } else {
        await _client.auth.updateUser(
          UserAttributes(data: {'full_name': trimmedName}),
        );
      }

      final updateData = <String, dynamic>{
        'full_name': trimmedName,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
      if (emailChanged && activeEmail == trimmedEmail) {
        updateData['email'] = trimmedEmail;
      }
      if (pixKey != null) {
        updateData['pix_key'] = trimmedPixKey!.isEmpty ? null : trimmedPixKey;
      }

      try {
        await _client.from('profiles').update(updateData).eq('id', user.id);
      } catch (errProfile) {
        debugPrint('[updateProfile] Aviso ao atualizar profiles: $errProfile');
      }

      _currentUser =
          _currentUser?.copyWith(
            fullName: trimmedName,
            email: activeEmail,
            pixKey: pixKey != null ? (trimmedPixKey!.isEmpty ? null : trimmedPixKey) : _currentUser?.pixKey,
          ) ??
          UserProfile(
            id: user.id,
            email: activeEmail,
            fullName: trimmedName,
            pixKey: (trimmedPixKey != null && trimmedPixKey.isNotEmpty) ? trimmedPixKey : null,
          );

      _authStateController.add(_currentUser);
      return _currentUser!;
    } on AuthException catch (e) {
      throw AuthFailure(e.message);
    } catch (e) {
      if (e is Failure) rethrow;
      throw ServerFailure('Erro ao atualizar perfil: $e');
    }
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
          houses.add(
            House(
              id: h['id'] as String,
              name: h['name'] as String,
              cycleStartDay: (h['cycle_start_day'] as num?)?.toInt() ?? 5,
              cycleDayChanges: CycleDayChange.listFromJson(h['cycle_day_schedule']),
              timezone: h['timezone'] as String? ?? 'America/Sao_Paulo',
              createdBy: h['created_by'] as String? ?? userId,
              pixKey: h['pix_key'] as String?,
              pixKeyType: h['pix_key_type'] as String?,
              pixKeyHolderName: h['pix_key_holder_name'] as String?,
              pixKeyBank: h['pix_key_bank'] as String?,
            ),
          );
        }
      }
      return houses;
    } catch (_) {
      return [];
    }
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
    try {
      // O dia de início do ciclo não é gravado direto: a troca vale a partir do
      // fim do ciclo em andamento, e o banco guarda desde quando.
      final current = _currentHouse?.id == houseId ? _currentHouse : null;
      if (cycleStartDay != null && cycleStartDay != current?.cycleStartDay) {
        final schedule = current?.cycleSchedule ?? CycleSchedule(cycleStartDay);
        final change = schedule.planChange(DateTime.now(), cycleStartDay);
        await _client.rpc('change_house_cycle_start_day', params: {
          'p_house_id': houseId,
          'p_new_day': cycleStartDay,
          'p_from': change.from.toIso8601String().split('T')[0],
        });
      }

      final updates = <String, dynamic>{
        if (name != null) 'name': name.trim(),
        if (pixKey != null) 'pix_key': pixKey.trim().isEmpty ? null : pixKey.trim(),
        if (pixKeyType != null) 'pix_key_type': pixKeyType,
        if (pixKeyHolderName != null) 'pix_key_holder_name': pixKeyHolderName.trim().isEmpty ? null : pixKeyHolderName.trim(),
        if (pixKeyBank != null) 'pix_key_bank': pixKeyBank.trim().isEmpty ? null : pixKeyBank.trim(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };

      final updatedRow = await _client
          .from('houses')
          .update(updates)
          .eq('id', houseId)
          .select()
          .single();

      final updatedHouse = House(
        id: updatedRow['id'] as String,
        name: updatedRow['name'] as String,
        cycleStartDay: (updatedRow['cycle_start_day'] as num?)?.toInt() ?? 5,
        cycleDayChanges: CycleDayChange.listFromJson(updatedRow['cycle_day_schedule']),
        timezone: updatedRow['timezone'] as String? ?? 'America/Sao_Paulo',
        createdBy: updatedRow['created_by'] as String?,
        pixKey: updatedRow['pix_key'] as String?,
        pixKeyType: updatedRow['pix_key_type'] as String?,
        pixKeyHolderName: updatedRow['pix_key_holder_name'] as String?,
        pixKeyBank: updatedRow['pix_key_bank'] as String?,
      );

      if (_currentHouse?.id == houseId) {
        _currentHouse = updatedHouse;
        _houseStateController.add(_currentHouse);
      }

      return updatedHouse;
    } catch (e) {
      throw ServerFailure('Erro ao atualizar dados da casa: $e');
    }
  }

  @override
  Future<House> createHouse({
    required String name,
    int cycleStartDay = 5,
  }) async {
    final userId = _currentUser?.id ?? _client.auth.currentUser?.id;
    if (userId == null) {
      throw const AuthFailure(
        'Usuário precisa estar autenticado para criar uma casa.',
      );
    }

    try {
      // 1. Tenta criar através da RPC atômica segura (evita conflito de RLS entre houses e house_members)
      try {
        final rpcResult = await _client.rpc(
          'create_house_with_owner',
          params: {'p_name': name.trim(), 'p_cycle_start_day': cycleStartDay},
        );

        if (rpcResult != null) {
          final houseMap = rpcResult as Map<String, dynamic>;
          final house = House(
            id: houseMap['id'] as String,
            name: houseMap['name'] as String,
            cycleStartDay:
                (houseMap['cycle_start_day'] as num?)?.toInt() ?? cycleStartDay,
            cycleDayChanges: CycleDayChange.listFromJson(houseMap['cycle_day_schedule']),
            timezone: houseMap['timezone'] as String? ?? 'America/Sao_Paulo',
            createdBy: userId,
            pixKey: houseMap['pix_key'] as String?,
            pixKeyType: houseMap['pix_key_type'] as String?,
            pixKeyHolderName: houseMap['pix_key_holder_name'] as String?,
            pixKeyBank: houseMap['pix_key_bank'] as String?,
          );

          _currentHouse = house;
          _houseStateController.add(_currentHouse);
          return house;
        }
      } catch (rpcErr) {
        debugPrint(
          '[createHouse] RPC create_house_with_owner não disponível ou falhou: $rpcErr',
        );
        // Segue para fallback direto caso a RPC ainda não tenha sido executada no SQL Editor
      }

      // 2. Inserção direta nas tabelas
      final houseRow = await _client
          .from('houses')
          .insert({
            'name': name.trim(),
            'cycle_start_day': cycleStartDay,
            'created_by': userId,
          })
          .select()
          .single();

      final houseId = houseRow['id'] as String;

      // Adiciona o criador como membro owner de forma resiliente
      try {
        await _client.from('house_members').insert({
          'house_id': houseId,
          'user_id': userId,
          'role': 'owner',
          'default_split_percent': 100.0,
        });
      } catch (errMember) {
        // Se a coluna default_split_percent não existir no schema cache, insere sem ela
        if (errMember.toString().contains('default_split_percent') ||
            (errMember is PostgrestException && errMember.code == 'PGRST204')) {
          await _client.from('house_members').insert({
            'house_id': houseId,
            'user_id': userId,
            'role': 'owner',
          });
        } else {
          rethrow;
        }
      }

      // 3. Inicializa lista de compras padrão
      try {
        await _client.from('shopping_lists').insert({
          'house_id': houseId,
          'name': 'Supermercado & Feira',
          'icon': 'shopping_cart_outlined',
          'is_default': true,
          'created_by': userId,
        });
      } catch (errList) {
        debugPrint(
          '[createHouse] Falha não impeditiva ao criar lista de compras padrão: $errList',
        );
      }

      // 4. Inicializa formas de pagamento padrão (Caixa da Casa, Pix, Dinheiro)
      try {
        await _client.from('payment_methods').insert([
          {
            'house_id': houseId,
            'name': 'Caixa da Casa',
            'type': 'account',
            'is_active': true,
            'created_by': userId,
          },
          {
            'house_id': houseId,
            'name': 'Pix',
            'type': 'pix',
            'is_active': true,
            'created_by': userId,
          },
          {
            'house_id': houseId,
            'name': 'Dinheiro em Espécie',
            'type': 'cash',
            'is_active': true,
            'created_by': userId,
          },
        ]);
      } catch (errPm) {
        debugPrint(
          '[createHouse] Falha não impeditiva ao criar formas de pagamento padrão: $errPm',
        );
      }

      // 5. Inicializa categorias essenciais
      try {
        await _client.from('categories').insert([
          {
            'house_id': houseId,
            'name': 'Supermercado',
            'icon': 'shopping_cart_outlined',
            'color_hex': '#10B981',
            'is_active': true,
            'created_by': userId,
          },
          {
            'house_id': houseId,
            'name': 'Moradia & Aluguel',
            'icon': 'home_outlined',
            'color_hex': '#3B82F6',
            'is_active': true,
            'created_by': userId,
          },
          {
            'house_id': houseId,
            'name': 'Contas (Luz, Água, Internet)',
            'icon': 'bolt_outlined',
            'color_hex': '#F59E0B',
            'is_active': true,
            'created_by': userId,
          },
          {
            'house_id': houseId,
            'name': 'Transporte & Carro',
            'icon': 'directions_car_outlined',
            'color_hex': '#EC4899',
            'is_active': true,
            'created_by': userId,
          },
          {
            'house_id': houseId,
            'name': 'Lazer & Restaurantes',
            'icon': 'restaurant_outlined',
            'color_hex': '#8B5CF6',
            'is_active': true,
            'created_by': userId,
          },
          {
            'house_id': houseId,
            'name': 'Saúde & Farmácia',
            'icon': 'local_hospital_outlined',
            'color_hex': '#EF4444',
            'is_active': true,
            'created_by': userId,
          },
        ]);
      } catch (errCat) {
        debugPrint(
          '[createHouse] Falha não impeditiva ao criar categorias padrão: $errCat',
        );
      }

      // 6. Inicializa a caixinha padrão (sem meta, saldo zero)
      try {
        await _client.from('savings_vaults').insert({
          'house_id': houseId,
          'name': 'Reserva da Casa',
          'icon': 'savings',
          'color_hex': '#10B981',
        });
      } catch (errVault) {
        debugPrint(
          '[createHouse] Falha não impeditiva ao criar caixinha padrão: $errVault',
        );
      }

      final house = House(
        id: houseId,
        name: houseRow['name'] as String,
        cycleStartDay:
            (houseRow['cycle_start_day'] as num?)?.toInt() ?? cycleStartDay,
        cycleDayChanges: CycleDayChange.listFromJson(houseRow['cycle_day_schedule']),
        timezone: houseRow['timezone'] as String? ?? 'America/Sao_Paulo',
        createdBy: userId,
        pixKey: houseRow['pix_key'] as String?,
        pixKeyType: houseRow['pix_key_type'] as String?,
        pixKeyHolderName: houseRow['pix_key_holder_name'] as String?,
        pixKeyBank: houseRow['pix_key_bank'] as String?,
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
      // A RPC valida o convite (validade e uso único) e registra a entrada na casa.
      final Map<String, dynamic> houseRow;
      try {
        houseRow = Map<String, dynamic>.from(
          await _client.rpc(
            'join_house_with_invite',
            params: {'p_code': inviteCode.trim().toUpperCase()},
          ) as Map,
        );
      } on PostgrestException catch (e) {
        if (e.message.contains('convite')) {
          throw const AuthFailure('Código de convite inválido ou expirado.');
        }
        rethrow;
      }

      final house = House(
        id: houseRow['id'] as String,
        name: houseRow['name'] as String,
        cycleStartDay: (houseRow['cycle_start_day'] as num?)?.toInt() ?? 5,
        cycleDayChanges: CycleDayChange.listFromJson(houseRow['cycle_day_schedule']),
        timezone: houseRow['timezone'] as String? ?? 'America/Sao_Paulo',
        createdBy: houseRow['created_by'] as String? ?? '',
        pixKey: houseRow['pix_key'] as String?,
        pixKeyType: houseRow['pix_key_type'] as String?,
        pixKeyHolderName: houseRow['pix_key_holder_name'] as String?,
        pixKeyBank: houseRow['pix_key_bank'] as String?,
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
          joinedAt:
              DateTime.tryParse(r['joined_at'] as String? ?? '')?.toLocal() ??
              DateTime.now(),
          profile: UserProfile(
            id: r['user_id'] as String,
            email: prof?['email'] as String? ?? '',
            fullName: prof?['full_name'] as String? ?? 'Membro',
            avatarUrl: prof?['avatar_url'] as String?,
            phone: prof?['phone'] as String?,
            pixKey: prof?['pix_key'] as String?,
          ),
        );
      }).toList();
    } catch (_) {
      try {
        final rows = await _client
            .from('house_members')
            .select('id, house_id, user_id, role, joined_at')
            .eq('house_id', houseId);

        final userIds = rows.map((r) => r['user_id'] as String).toList();
        final profiles = userIds.isNotEmpty
            ? await _client
                  .from('profiles')
                  .select()
                  .filter('id', 'in', userIds)
            : <Map<String, dynamic>>[];
        final profileMap = {for (final p in profiles) p['id'] as String: p};

        return rows.map((r) {
          final uId = r['user_id'] as String;
          final prof = profileMap[uId];
          return HouseMemberInfo(
            id: r['id'] as String,
            houseId: r['house_id'] as String,
            userId: uId,
            role: r['role'] as String? ?? 'member',
            joinedAt:
                DateTime.tryParse(r['joined_at'] as String? ?? '')?.toLocal() ??
                DateTime.now(),
            profile: UserProfile(
              id: uId,
              email: prof?['email'] as String? ?? '',
              fullName: prof?['full_name'] as String? ?? 'Membro',
              avatarUrl: prof?['avatar_url'] as String?,
              phone: prof?['phone'] as String?,
              pixKey: prof?['pix_key'] as String?,
            ),
          );
        }).toList();
      } catch (_) {
        return [];
      }
    }
  }

  @override
  Future<String> createHouseInvite(String houseId) async {
    try {
      final currentUserId = _currentUser?.id ?? _client.auth.currentUser?.id;
      final code = _generateInviteCode();
      await _client.from('house_invites').insert({
        'house_id': houseId,
        'code': code,
        'created_by': ?currentUserId,
        'expires_at': DateTime.now()
            .toUtc()
            .add(const Duration(days: 7))
            .toIso8601String(),
      });
      return code;
    } catch (e) {
      throw ServerFailure('Erro ao gerar convite: $e');
    }
  }

  /// Código de convite imprevisível (sem caracteres ambíguos como 0/O e 1/I).
  String _generateInviteCode() {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();
    final chars = List.generate(8, (_) => alphabet[random.nextInt(alphabet.length)]);
    return 'LAR${chars.join()}';
  }
}
