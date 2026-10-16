import 'package:flutter/foundation.dart';

/// Configuração do "Continuar com Google".
///
/// Os IDs de cliente OAuth vêm do Google Cloud (não são segredos) e podem ser
/// passados com --dart-define. Enquanto o provedor Google não estiver ligado
/// no Supabase, o botão fica escondido.
class GoogleAuthConfig {
  GoogleAuthConfig._();

  /// Liga o botão. Web: só depende do provedor Google ligado no Supabase.
  static const bool enabled = bool.fromEnvironment(
    'GOOGLE_SIGN_IN',
    defaultValue: false,
  );

  /// ID do cliente "Aplicativo da Web": no Android e no iOS é o
  /// `serverClientId`, para o token do Google valer no Supabase.
  static const String webClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
  );

  /// ID do cliente iOS (o Android usa o pacote e o SHA-1 cadastrados).
  static const String iosClientId = String.fromEnvironment(
    'GOOGLE_IOS_CLIENT_ID',
  );

  static bool get isAvailable {
    if (!enabled) return false;
    if (kIsWeb) return true;
    if (webClientId.isEmpty) return false;
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return iosClientId.isNotEmpty;
    }
    return defaultTargetPlatform == TargetPlatform.android;
  }
}
