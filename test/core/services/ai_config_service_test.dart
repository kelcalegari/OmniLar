import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:omni_lar/core/services/ai_config_service.dart';

class MockFlutterSecureStorage extends Mock implements FlutterSecureStorage {}

void main() {
  group('AiConfigService (BYOK - Bring Your Own Key & Fallback)', () {
    late MockFlutterSecureStorage mockStorage;
    late AiConfigService service;
    late Map<String, String> storageMap;

    setUp(() {
      mockStorage = MockFlutterSecureStorage();
      storageMap = {};

      when(() => mockStorage.read(key: any(named: 'key'))).thenAnswer(
        (invocation) async => storageMap[invocation.namedArguments[#key] as String],
      );
      when(() => mockStorage.write(key: any(named: 'key'), value: any(named: 'value'))).thenAnswer(
        (invocation) async {
          storageMap[invocation.namedArguments[#key] as String] =
              invocation.namedArguments[#value] as String;
        },
      );
      when(() => mockStorage.delete(key: any(named: 'key'))).thenAnswer(
        (invocation) async {
          storageMap.remove(invocation.namedArguments[#key] as String);
        },
      );

      service = AiConfigService(mockStorage);
    });

    test('Inicia sem chave customizada e com modelo padrão gemini-3.1-flash-lite', () async {
      expect(await service.hasCustomKey(), isFalse);
      expect(await service.getUserApiKey(), isNull);
      expect(await service.getSelectedModel(), equals('gemini-3.1-flash-lite'));
    });

    test('Salva chave do usuário e modelo escolhido no cofre seguro', () async {
      await service.saveConfig(
        apiKey: 'AIzaSyTestKey12345',
        model: 'gemini-3.8-flash',
      );

      expect(await service.hasCustomKey(), isTrue);
      expect(await service.getUserApiKey(), equals('AIzaSyTestKey12345'));
      expect(await service.getSelectedModel(), equals('gemini-3.8-flash'));
      expect(storageMap[AiConfigService.keyStorageKey], equals('AIzaSyTestKey12345'));
      expect(storageMap[AiConfigService.modelStorageKey], equals('gemini-3.8-flash'));
    });

    test('Normaliza modelo inválido para o modelo padrão seguro', () async {
      await service.saveConfig(
        apiKey: 'AIzaSyTestKey12345',
        model: 'modelo_inexistente_xyz',
      );

      expect(await service.getSelectedModel(), equals(AiConfigService.defaultModel));
    });

    test('Remove chave e volta para cota padrão do sistema', () async {
      await service.saveConfig(
        apiKey: 'AIzaSyTestKey12345',
        model: 'gemini-2.0-flash',
      );
      expect(await service.hasCustomKey(), isTrue);

      await service.clearConfig();

      expect(await service.hasCustomKey(), isFalse);
      expect(await service.getUserApiKey(), isNull);
      expect(await service.getSelectedModel(), equals(AiConfigService.defaultModel));
      expect(storageMap.containsKey(AiConfigService.keyStorageKey), isFalse);
    });

    test('Validação de chave vazia retorna erro imediato sem chamar rede', () async {
      final result = await service.testApiKey('   ');
      expect(result.isValid, isFalse);
      expect(result.errorMessage, contains('não pode estar vazia'));
    });
  });
}
