import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../domain/entities/csv_mapping.dart';

/// Guarda, neste aparelho, como ler o CSV de cada cartão ou conta.
class CsvMappingStore {
  final FlutterSecureStorage? _storage;

  /// Cópia em memória: vale também quando o armazenamento não está disponível
  /// (modo demo na web, testes).
  final Map<String, CsvMapping> _cache = {};

  CsvMappingStore([this._storage]);

  static String _key(String paymentMethodId) => 'omnilar_csv_mapping_$paymentMethodId';

  Future<CsvMapping?> load(String paymentMethodId) async {
    final cached = _cache[paymentMethodId];
    if (cached != null) return cached;
    try {
      final mapping = CsvMapping.fromJson(await _storage?.read(key: _key(paymentMethodId)));
      if (mapping != null) _cache[paymentMethodId] = mapping;
      return mapping;
    } catch (_) {
      return null;
    }
  }

  Future<void> save(String paymentMethodId, CsvMapping mapping) async {
    _cache[paymentMethodId] = mapping;
    try {
      await _storage?.write(key: _key(paymentMethodId), value: mapping.toJson());
    } catch (_) {
      // Fica só na memória enquanto o app estiver aberto
    }
  }
}
