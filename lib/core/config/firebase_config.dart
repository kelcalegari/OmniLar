import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Projeto Firebase do Omni Lar (`omnilar-ef002`), usado só para o push (FCM).
/// Estes valores são públicos: identificam o app, não dão acesso a nada. A
/// chave da conta de serviço, que envia os push, fica só nos secrets do
/// Supabase (função `notify`).
class FirebaseConfig {
  FirebaseConfig._();

  static const _web = FirebaseOptions(
    apiKey: 'AIzaSyAltqDtvDEqr5a78jMMpe8qNwJBzrhfWI8',
    authDomain: 'omnilar-ef002.firebaseapp.com',
    projectId: 'omnilar-ef002',
    storageBucket: 'omnilar-ef002.firebasestorage.app',
    messagingSenderId: '593321672478',
    appId: '1:593321672478:web:da7f4f7e9bb8c81ebc930f',
  );

  // Do google-services.json do app br.com.omnilar.app
  static const _android = FirebaseOptions(
    apiKey: 'AIzaSyAK4azWcN1KNZsrVaISMIweqzHIsUziJ-Q',
    projectId: 'omnilar-ef002',
    storageBucket: 'omnilar-ef002.firebasestorage.app',
    messagingSenderId: '593321672478',
    appId: '1:593321672478:android:afb8b32f2e50e05bbc930f',
  );

  /// Chave pública do Web Push (certificado VAPID do Cloud Messaging).
  static const webPushVapidKey =
      'BPhZLicdiJ6yHT69adhVG0sfU3UfTU_q6KeiSs4rUKzJhUf4iRR-5ei97P8wzWeDAF1_NOAt7SdvHKNHGyZUhZ0';

  /// Opções da plataforma atual; nulo onde o push não é usado (iOS nativo,
  /// desktop), já que o iPhone usa o site instalado.
  static FirebaseOptions? get currentPlatform {
    if (kIsWeb) return _web;
    if (defaultTargetPlatform == TargetPlatform.android) return _android;
    return null;
  }

  static bool _initialized = false;
  static bool get isInitialized => _initialized;

  /// Liga o Firebase. Uma falha aqui não impede o app de abrir: o sino
  /// continua funcionando, só o push fica indisponível.
  static Future<void> initialize() async {
    final options = currentPlatform;
    if (options == null || _initialized) return;
    try {
      await Firebase.initializeApp(options: options);
      _initialized = true;
    } catch (e) {
      debugPrint('Firebase indisponível: $e');
    }
  }
}
