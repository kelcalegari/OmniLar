import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseConfig {
  SupabaseConfig._();

  // Em produção, esses valores são fornecidos via variáveis de ambiente / flutter build --dart-define
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://omnilar-dev.supabase.co',
  );

  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.dummy_anon_key_for_offline_and_mock',
  );

  static bool _isInitialized = false;

  static bool get isInitialized => _isInitialized;

  /// Inicializa o Supabase Flutter de forma resiliente:
  /// Se falhar por falta de conexão remota, a aplicação segue em modo mock local.
  static Future<void> initialize() async {
    try {
      await Supabase.initialize(
        url: supabaseUrl,
        // ignore: deprecated_member_use
        anonKey: supabaseAnonKey,
        authOptions: const FlutterAuthClientOptions(
          authFlowType: AuthFlowType.pkce,
        ),
      );
      _isInitialized = true;
      debugPrint('Supabase inicializado com sucesso em $supabaseUrl');
    } catch (e) {
      debugPrint('Supabase remoto não disponível ($e). Rodando com datasources locais.');
      _isInitialized = false;
    }
  }

  static SupabaseClient? get client {
    if (!_isInitialized) return null;
    return Supabase.instance.client;
  }
}
