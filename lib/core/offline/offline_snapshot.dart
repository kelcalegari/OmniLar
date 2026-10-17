import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Cópia local para abrir sem internet (decisão 12 de plano_proximas_frentes.md).
///
/// As leituras do Supabase passam por aqui com as linhas ainda cruas: quando o
/// servidor responde, a resposta é guardada no aparelho (cifrada, por usuário)
/// e devolvida; quando falha, volta a última cópia guardada e [showingSince]
/// passa a ter a hora dela, para a faixa "Sem internet". Gravações não passam
/// por aqui: elas continuam na fila offline.
class OfflineSnapshot {
  OfflineSnapshot({SnapshotStorage? storage, required this.currentUserId})
      : _storage = storage ?? const SecureSnapshotStorage();

  /// Instância do app; trocada nos testes.
  static OfflineSnapshot instance = OfflineSnapshot(currentUserId: () => null);

  static const _prefix = 'omnilar_snapshot_';

  final SnapshotStorage _storage;

  /// Conta logada: a cópia é guardada separada por usuário.
  final String? Function() currentUserId;

  /// Hora da cópia mais antiga em uso agora; null quando tudo veio do servidor.
  final ValueNotifier<DateTime?> showingSince = ValueNotifier(null);

  final Map<String, DateTime> _staleKeys = {};

  /// Várias linhas (o retorno de um `select`).
  Future<List<Map<String, dynamic>>> rows(
    String key,
    Future<List<Map<String, dynamic>>> Function() fetch,
  ) async {
    final data = await _readThrough(key, fetch);
    return [for (final row in data as List) Map<String, dynamic>.from(row as Map)];
  }

  /// Uma linha ou nenhuma (o retorno de um `maybeSingle`).
  Future<Map<String, dynamic>?> row(
    String key,
    Future<Map<String, dynamic>?> Function() fetch,
  ) async {
    final data = await _readThrough(key, fetch);
    return data == null ? null : Map<String, dynamic>.from(data as Map);
  }

  Future<Object?> _readThrough(String key, Future<Object?> Function() fetch) async {
    final userId = currentUserId();
    if (userId == null) return fetch();
    final storageKey = '$_prefix${userId}_$key';
    try {
      final data = await fetch();
      _markFresh(key);
      unawaited(_save(storageKey, data));
      return data;
    } catch (e) {
      final cached = await _read(storageKey);
      if (cached == null) rethrow;
      _markStale(key, cached.savedAt);
      return cached.data;
    }
  }

  Future<void> _save(String storageKey, Object? data) async {
    try {
      await _storage.write(
        storageKey,
        jsonEncode({'savedAt': DateTime.now().toUtc().toIso8601String(), 'data': data}),
      );
    } catch (_) {}
  }

  Future<({DateTime savedAt, Object? data})?> _read(String storageKey) async {
    try {
      final raw = await _storage.read(storageKey);
      if (raw == null) return null;
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final savedAt = DateTime.tryParse(json['savedAt'] as String? ?? '')?.toLocal();
      if (savedAt == null) return null;
      return (savedAt: savedAt, data: json['data']);
    } catch (_) {
      return null;
    }
  }

  void _markStale(String key, DateTime savedAt) {
    _staleKeys[key] = savedAt;
    _publish();
  }

  void _markFresh(String key) {
    if (_staleKeys.remove(key) != null) _publish();
  }

  void _publish() {
    showingSince.value =
        _staleKeys.isEmpty ? null : _staleKeys.values.reduce((a, b) => a.isBefore(b) ? a : b);
  }

  /// Apaga as cópias de todos os usuários deste aparelho (ao sair da conta).
  Future<void> clearAll() async {
    _staleKeys.clear();
    _publish();
    try {
      for (final key in (await _storage.keys()).where((k) => k.startsWith(_prefix))) {
        await _storage.delete(key);
      }
    } catch (_) {}
  }
}

/// Onde a cópia fica guardada.
abstract class SnapshotStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
  Future<Iterable<String>> keys();
}

/// Armazenamento cifrado do aparelho (no navegador, o armazenamento local
/// cifrado), o mesmo da fila offline.
class SecureSnapshotStorage implements SnapshotStorage {
  const SecureSnapshotStorage([this._storage = const FlutterSecureStorage()]);

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) => _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);

  @override
  Future<Iterable<String>> keys() async => (await _storage.readAll()).keys;
}
