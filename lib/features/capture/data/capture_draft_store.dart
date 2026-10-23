import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../domain/services/capture_draft_codec.dart';

/// Guarda, neste aparelho, a revisão em andamento da captura inteligente
/// (RN16 / RN19). Evita perder a proposta ou o que a pessoa já preencheu se
/// sair da tela ou fechar o app antes de confirmar.
class CaptureDraftStore {
  final FlutterSecureStorage? _storage;
  final String? Function()? getCurrentHouseId;

  /// Prazo de expiração automática de rascunhos parados (RN19).
  static const Duration expiration = Duration(days: 30);

  /// Cópia em memória: vale também quando o armazenamento não está disponível
  /// (e preserva o anexo em bytes durante a sessão mesmo se exceder 2 MB).
  final Map<String, CaptureDraft> _cache = {};
  final Set<String> _cleared = {};

  CaptureDraftStore([this._storage, this.getCurrentHouseId]);

  String _resolvedScope([String? houseId]) {
    final id = (houseId ?? getCurrentHouseId?.call() ?? '').trim();
    return id.isNotEmpty ? id : 'default';
  }

  static String _key(String scope) => 'omnilar_capture_draft_$scope';

  static bool isExpired(DateTime savedAt, [DateTime? now]) {
    final ref = now ?? DateTime.now();
    return ref.difference(savedAt) > expiration;
  }

  Future<CaptureDraft?> load([String? houseId]) async {
    final scope = _resolvedScope(houseId);
    final cached = _cache[scope];
    if (cached != null) {
      if (isExpired(cached.savedAt)) {
        await clear(scope);
        return null;
      }
      return cached;
    }
    if (_cleared.contains(scope)) return null;
    try {
      final text = await _storage?.read(key: _key(scope));
      if (text == null || text.isEmpty) return null;
      final json = (jsonDecode(text) as Map).cast<String, dynamic>();
      final draft = CaptureDraftCodec.fromJson(json);
      if (draft == null) return null;
      if (isExpired(draft.savedAt)) {
        await clear(scope);
        return null;
      }
      _cache[scope] = draft;
      return draft;
    } catch (_) {
      return null;
    }
  }

  Future<void> save(CaptureDraft draft, [String? houseId]) async {
    final scope = _resolvedScope(houseId);
    _cache[scope] = draft;
    _cleared.remove(scope);
    try {
      await _storage?.write(
        key: _key(scope),
        value: jsonEncode(CaptureDraftCodec.toJson(draft)),
      );
    } catch (_) {
      // Se o armazenamento seguro rejeitar pelo tamanho da imagem, salva sem o binário
      try {
        await _storage?.write(
          key: _key(scope),
          value: jsonEncode(CaptureDraftCodec.toJson(draft, includeAttachmentBytes: false)),
        );
      } catch (_) {
        // Fica só na memória enquanto o app estiver aberto
      }
    }
  }

  Future<void> clear([String? houseId]) async {
    final scope = _resolvedScope(houseId);
    _cache.remove(scope);
    _cleared.add(scope);
    try {
      await _storage?.delete(key: _key(scope));
    } catch (_) {}
  }
}
