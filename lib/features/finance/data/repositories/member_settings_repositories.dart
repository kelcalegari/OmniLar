import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/utils/uuid.dart';
import '../../domain/entities/member_settings.dart';
import '../../domain/repositories/member_settings_repository.dart';

/// Ajustes guardados na própria linha do morador (RLS: só ele lê e grava).
class SupabaseMemberSettingsRepository implements MemberSettingsRepository {
  final SupabaseClient client;
  final String Function() getCurrentHouseId;

  SupabaseMemberSettingsRepository({required this.client, required this.getCurrentHouseId});

  String? get _userId => client.auth.currentUser?.id;

  @override
  Future<MemberSettings> load() async {
    final houseId = getCurrentHouseId();
    final userId = _userId;
    if (!isUuid(houseId) || !isUuid(userId)) return const MemberSettings();
    final row = await client
        .from('member_settings')
        .select('settings')
        .eq('house_id', houseId)
        .eq('user_id', userId!)
        .maybeSingle();
    return MemberSettings.fromJson(row?['settings']);
  }

  @override
  Future<MemberSettings> save(MemberSettings settings) async {
    final houseId = getCurrentHouseId();
    final userId = _userId;
    if (!isUuid(houseId) || !isUuid(userId)) return settings;
    // O banco só aceita ids de verdade; id local (ainda não sincronizado) fica de fora
    const idKeys = {MemberSettings.launchPaymentMethodKey, MemberSettings.launchCategoryKey};
    final json = settings.toJson()
      ..removeWhere((key, value) => idKeys.contains(key) && (value is! String || !isUuid(value)));
    final row = await client
        .from('member_settings')
        .upsert({'house_id': houseId, 'user_id': userId, 'settings': json})
        .select('settings')
        .single();
    return MemberSettings.fromJson(row['settings']);
  }
}

/// Modo demonstração: fica na memória do aparelho.
class InMemoryMemberSettingsRepository implements MemberSettingsRepository {
  MemberSettings _settings;

  InMemoryMemberSettingsRepository([this._settings = const MemberSettings()]);

  @override
  Future<MemberSettings> load() async => _settings;

  @override
  Future<MemberSettings> save(MemberSettings settings) async => _settings = settings;
}

/// Escolhe a fonte a cada chamada, como as outras do app.
class DynamicMemberSettingsRepository implements MemberSettingsRepository {
  final MemberSettingsRepository remote;
  final MemberSettingsRepository mock;
  final bool Function() isDemoMode;

  DynamicMemberSettingsRepository({required this.remote, required this.mock, required this.isDemoMode});

  MemberSettingsRepository get _active => isDemoMode() ? mock : remote;

  @override
  Future<MemberSettings> load() => _active.load();

  @override
  Future<MemberSettings> save(MemberSettings settings) => _active.save(settings);
}
