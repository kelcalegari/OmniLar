import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Serviço de gerenciamento da configuração de IA do usuário (modelo BYOK - Bring Your Own Key).
/// Armazena no cofre local criptografado (Keystore/Keychain) a chave do Google AI Studio e modelo preferido.
class AiConfigService {
  static const String keyStorageKey = 'omnilar_user_gemini_api_key';
  static const String modelStorageKey = 'omnilar_user_gemini_model';
  static const String defaultModel = 'gemini-3.1-flash-lite';

  static const List<String> supportedModels = [
    'gemini-3.1-flash-lite',
    'gemini-3.8-flash',
    'gemini-3.5-flash',
    'gemini-flash-latest',
  ];

  final FlutterSecureStorage? _secureStorage;

  AiConfigService([this._secureStorage]);

  /// Retorna a chave de API cadastrada pelo usuário, ou null se estiver usando a cota padrão do app.
  Future<String?> getUserApiKey() async {
    if (_secureStorage == null) return null;
    try {
      final key = await _secureStorage.read(key: keyStorageKey);
      if (key == null || key.trim().isEmpty) return null;
      return key.trim();
    } catch (_) {
      return null;
    }
  }

  /// Retorna o modelo selecionado pelo usuário (ou o padrão 'gemini-1.5-flash').
  Future<String> getSelectedModel() async {
    if (_secureStorage == null) return defaultModel;
    try {
      final model = await _secureStorage.read(key: modelStorageKey);
      if (model != null && supportedModels.contains(model.trim())) {
        return model.trim();
      }
      return defaultModel;
    } catch (_) {
      return defaultModel;
    }
  }

  /// Verifica se o usuário possui uma chave de API própria configurada.
  Future<bool> hasCustomKey() async {
    final key = await getUserApiKey();
    return key != null && key.isNotEmpty;
  }

  /// Salva a chave e modelo customizados do usuário no cofre seguro.
  Future<void> saveConfig({
    required String? apiKey,
    required String model,
  }) async {
    if (_secureStorage == null) return;
    try {
      if (apiKey != null && apiKey.trim().isNotEmpty) {
        await _secureStorage.write(key: keyStorageKey, value: apiKey.trim());
      } else {
        await _secureStorage.delete(key: keyStorageKey);
      }

      final validModel = supportedModels.contains(model.trim()) ? model.trim() : defaultModel;
      await _secureStorage.write(key: modelStorageKey, value: validModel);
    } catch (_) {}
  }

  /// Remove a chave própria do usuário, voltando a utilizar a cota padrão do sistema.
  Future<void> clearConfig() async {
    if (_secureStorage == null) return;
    try {
      await _secureStorage.delete(key: keyStorageKey);
      await _secureStorage.delete(key: modelStorageKey);
    } catch (_) {}
  }

  /// Testa a validade da chave de API fornecida enviando um ping simples para o Google AI Studio.
  Future<({bool isValid, String? errorMessage})> testApiKey(
    String apiKey, [
    String? model,
  ]) async {
    final cleanKey = apiKey.trim();
    if (cleanKey.isEmpty) {
      return (isValid: false, errorMessage: 'A chave de API não pode estar vazia.');
    }

    final targetModel = (model != null && supportedModels.contains(model.trim()))
        ? model.trim()
        : defaultModel;

    final url = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/$targetModel:generateContent?key=$cleanKey',
    );

    try {
      final payload = jsonEncode({
        'contents': [
          {
            'role': 'user',
            'parts': [
              {'text': 'ping'}
            ],
          }
        ],
      });
      // package:http funciona também no navegador (dart:io não existe na web)
      final response = await http.post(
        url,
        headers: const {'Content-Type': 'application/json'},
        body: payload,
      );
      final responseBody = utf8.decode(response.bodyBytes);

      if (response.statusCode == 200) {
        return (isValid: true, errorMessage: null);
      } else {
        try {
          final body = jsonDecode(responseBody);
          final message = body['error']?['message'] as String? ?? 'Chave inválida (${response.statusCode}).';
          if (response.statusCode == 429 ||
              message.contains('RESOURCE_EXHAUSTED') ||
              message.toLowerCase().contains('quota')) {
            return (
              isValid: false,
              errorMessage:
                  'Chave válida, mas sua cota/tokens do Google AI Studio estão esgotados no momento (Erro 429 / RESOURCE_EXHAUSTED). Aguarde 1 minuto ou confira seu limite no AI Studio.',
            );
          }
          return (isValid: false, errorMessage: message);
        } catch (_) {
          return (isValid: false, errorMessage: 'Erro na validação (${response.statusCode}).');
        }
      }
    } catch (e) {
      return (isValid: false, errorMessage: 'Erro de conexão ao validar chave: $e');
    }
  }
}
