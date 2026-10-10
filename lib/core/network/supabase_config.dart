import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseConfig {
  SupabaseConfig._();

  // Em produção, esses valores são fornecidos via variáveis de ambiente / flutter build --dart-define
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: '',
  );

  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '',
  );

  static bool get isConfigured => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  static bool _isInitialized = false;

  static bool get isInitialized => _isInitialized;

  /// Inicializa o Supabase Flutter de forma resiliente:
  /// Se não estiver configurado ou falhar na conexão remota, a aplicação segue em modo mock local.
  static Future<void> initialize() async {
    if (!isConfigured) {
      debugPrint('Supabase não configurado. Rodando com datasources locais (Mock).');
      _isInitialized = false;
      return;
    }

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
