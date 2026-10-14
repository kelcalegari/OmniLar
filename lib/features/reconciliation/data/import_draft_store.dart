import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Rascunho guardado: quando foi salvo, de que arquivo e o conteúdo.
typedef ImportDraft = ({DateTime savedAt, String fileName, Map<String, dynamic> session});

/// Guarda, neste aparelho, a revisão em andamento de cada cartão ou conta.
class ImportDraftStore {
  final FlutterSecureStorage? _storage;

  /// Cópia em memória: vale também quando o armazenamento não está disponível.
  final Map<String, ImportDraft> _cache = {};
  final Set<String> _cleared = {};

  ImportDraftStore([this._storage]);

  static String _key(String paymentMethodId) => 'omnilar_import_draft_$paymentMethodId';

  Future<ImportDraft?> load(String paymentMethodId) async {
    final cached = _cache[paymentMethodId];
    if (cached != null) return cached;
    if (_cleared.contains(paymentMethodId)) return null;
    try {
      final text = await _storage?.read(key: _key(paymentMethodId));
      if (text == null) return null;
      final json = jsonDecode(text) as Map<String, dynamic>;
      final draft = (
        savedAt: DateTime.parse(json['savedAt'] as String),
        fileName: json['fileName'] as String,
        session: (json['session'] as Map).cast<String, dynamic>(),
      );
      _cache[paymentMethodId] = draft;
      return draft;
    } catch (_) {
      return null;
    }
  }

  Future<void> save(String paymentMethodId, String fileName, Map<String, dynamic> session) async {
    final draft = (savedAt: DateTime.now(), fileName: fileName, session: session);
    _cache[paymentMethodId] = draft;
    _cleared.remove(paymentMethodId);
    try {
      await _storage?.write(
        key: _key(paymentMethodId),
        value: jsonEncode({
          'savedAt': draft.savedAt.toIso8601String(),
          'fileName': fileName,
          'session': session,
        }),
      );
    } catch (_) {
      // Fica só na memória enquanto o app estiver aberto
    }
  }

  Future<void> clear(String paymentMethodId) async {
    _cache.remove(paymentMethodId);
    _cleared.add(paymentMethodId);
    try {
      await _storage?.delete(key: _key(paymentMethodId));
    } catch (_) {}
  }
}
