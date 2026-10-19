import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/entities/csv_mapping.dart';

/// Onde a casa guarda como ler o CSV de cada cartão ou conta
/// (`houses.csv_mappings`, 0101), para valer em todos os aparelhos.
abstract class CsvMappingRemote {
  /// Casa atual; quando muda, os mapeamentos lidos deixam de valer.
  String? get houseKey;

  /// Mapeamentos da casa (JSON de [CsvMapping] por id da forma de pagamento);
  /// null quando não há como ler (demo, sem conexão, banco sem a 0101).
  Future<Map<String, String>?> loadAll();

  Future<void> save(String paymentMethodId, String mappingJson);
}

class SupabaseCsvMappingRemote implements CsvMappingRemote {
  final SupabaseClient client;
  final String? Function() getCurrentHouseId;
  final bool Function() isDemoMode;

  SupabaseCsvMappingRemote({
    required this.client,
    required this.getCurrentHouseId,
    required this.isDemoMode,
  });

  static final _uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    caseSensitive: false,
  );

  @override
  String? get houseKey => _houseId;

  String? get _houseId {
    final id = getCurrentHouseId();
    return !isDemoMode() && id != null && _uuid.hasMatch(id) ? id : null;
  }

  @override
  Future<Map<String, String>?> loadAll() async {
    final houseId = _houseId;
    if (houseId == null) return null;
    final row = await client.from('houses').select('csv_mappings').eq('id', houseId).maybeSingle();
    final raw = row?['csv_mappings'];
    if (raw is! Map) return const {};
    return {
      for (final entry in raw.entries)
        if (entry.value is Map) entry.key.toString(): jsonEncode(entry.value),
    };
  }

  @override
  Future<void> save(String paymentMethodId, String mappingJson) async {
    final houseId = _houseId;
    if (houseId == null || !_uuid.hasMatch(paymentMethodId)) return;
    await client.rpc('save_csv_mapping', params: {
      'p_house_id': houseId,
      'p_payment_method_id': paymentMethodId,
      'p_mapping': jsonDecode(mappingJson),
    });
  }
}

/// Como ler o CSV de cada cartão ou conta. Vale o da casa (compartilhado entre
/// aparelhos); sem ele, o que este aparelho já tinha guardado, que é então
/// enviado à casa. Ao salvar, grava nos dois.
class CsvMappingStore {
  final FlutterSecureStorage? _storage;
  final CsvMappingRemote? _remote;

  /// Cópia em memória: vale também quando o armazenamento não está disponível
  /// (modo demo na web, testes).
  final Map<String, CsvMapping> _cache = {};

  /// Mapeamentos da casa, lidos uma vez por vez que o app abre.
  Map<String, String>? _remoteMappings;
  bool _remoteTried = false;
  String? _remoteHouse;

  CsvMappingStore([this._storage, this._remote]);

  static String _key(String paymentMethodId) => 'omnilar_csv_mapping_$paymentMethodId';

  Future<Map<String, String>?> _fromHouse() async {
    if (_remote == null) return null;
    if (_remoteHouse != _remote.houseKey) {
      _remoteHouse = _remote.houseKey;
      _remoteMappings = null;
      _remoteTried = false;
    }
    if (_remoteTried) return _remoteMappings;
    try {
      _remoteMappings = await _remote.loadAll();
      _remoteTried = _remoteMappings != null;
    } catch (_) {
      // Sem conexão ou banco sem a 0101: segue com o do aparelho e tenta de novo depois
    }
    return _remoteMappings;
  }

  Future<CsvMapping?> load(String paymentMethodId) async {
    final cached = _cache[paymentMethodId];
    if (cached != null) return cached;
    final house = await _fromHouse();
    final shared = CsvMapping.fromJson(house?[paymentMethodId]);
    if (shared != null) {
      _cache[paymentMethodId] = shared;
      return shared;
    }
    try {
      final mapping = CsvMapping.fromJson(await _storage?.read(key: _key(paymentMethodId)));
      if (mapping != null) {
        _cache[paymentMethodId] = mapping;
        // Migração suave: o que só existia neste aparelho passa a ser da casa
        if (house != null) await _sendToHouse(paymentMethodId, mapping);
      }
      return mapping;
    } catch (_) {
      return null;
    }
  }

  Future<void> save(String paymentMethodId, CsvMapping mapping) async {
    _cache[paymentMethodId] = mapping;
    await _sendToHouse(paymentMethodId, mapping);
    try {
      await _storage?.write(key: _key(paymentMethodId), value: mapping.toJson());
    } catch (_) {
      // Fica só na memória enquanto o app estiver aberto
    }
  }

  Future<void> _sendToHouse(String paymentMethodId, CsvMapping mapping) async {
    final remote = _remote;
    if (remote == null) return;
    try {
      await remote.save(paymentMethodId, mapping.toJson());
      _remoteMappings = {...?_remoteMappings, paymentMethodId: mapping.toJson()};
    } catch (_) {
      // Sem conexão: fica no aparelho e é enviado na próxima vez que for lido
    }
  }
}
