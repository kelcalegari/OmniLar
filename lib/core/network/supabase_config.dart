import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseConfig {
  SupabaseConfig._();

  // Credenciais padrão da nuvem (podem ser sobrescritas via --dart-define)
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://rygxmpwzofgieodvhpcy.supabase.co',
  );

  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable_GshamuXeZLHEPF1bch5SgQ_eVXv_ckW',
  );

  static bool get isConfigured => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  static bool _isInitialized = false;

  static bool get isInitialized => _isInitialized;

  static bool get isRunningTests =>
      !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');

  /// Inicializa o Supabase Flutter de forma resiliente:
  /// Se for ambiente de testes automatizados ou falhar na conexão remota, a aplicação segue em modo mock local.
  static Future<void> initialize() async {
    if (isRunningTests || !isConfigured) {
      debugPrint('Ambiente de testes/mock. Rodando com datasources locais.');
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
