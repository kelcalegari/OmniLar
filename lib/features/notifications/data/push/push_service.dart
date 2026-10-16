import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/firebase_config.dart';
import '../../../auth/domain/entities/user_profile.dart';
import 'push_environment.dart';

/// Situação do push neste aparelho, para a tela "Ativar notificações".
enum PushStatus {
  /// Navegador ou plataforma sem push (ou o Firebase não carregou).
  unsupported,

  /// iPhone fora do site instalado: precisa adicionar à Tela de Início.
  needsInstall,

  /// Ainda não pedimos a permissão.
  notDetermined,

  /// O usuário negou; só reativa nos ajustes do aparelho ou do navegador.
  denied,

  /// Permitido e com o aparelho registrado.
  enabled,
}

/// Push pelo FCM (Android, navegador e iPhone com o site instalado). O app só
/// pede a permissão e grava o token do aparelho em `device_tokens`; quem
/// envia é a função `notify` do Supabase.
class PushService {
  final SupabaseClient? client;
  final bool Function() isDemoMode;

  /// Abre a rota do deeplink quando o usuário toca num push (Android).
  void Function(String deeplink)? onOpenDeeplink;

  StreamSubscription<String>? _tokenRefresh;
  StreamSubscription<RemoteMessage>? _opened;
  String? _currentUserId;

  PushService({required this.client, required this.isDemoMode});

  PushEnvironment get environment => PushEnvironment.read();

  bool get _firebaseReady => FirebaseConfig.isInitialized && FirebaseConfig.currentPlatform != null;

  String get _platform {
    if (!kIsWeb) return 'android';
    return environment.isIos ? 'ios_pwa' : 'web';
  }

  Future<PushStatus> status() async {
    if (kIsWeb) {
      final env = environment;
      if (env.isIos && !env.isStandalone) return PushStatus.needsInstall;
      if (!env.hasNotificationApi) return PushStatus.unsupported;
    }
    if (!_firebaseReady || isDemoMode()) return PushStatus.unsupported;
    try {
      final settings = await FirebaseMessaging.instance.getNotificationSettings();
      return _fromAuthorization(settings.authorizationStatus);
    } catch (_) {
      return PushStatus.unsupported;
    }
  }

  PushStatus _fromAuthorization(AuthorizationStatus status) => switch (status) {
        AuthorizationStatus.authorized || AuthorizationStatus.provisional => PushStatus.enabled,
        AuthorizationStatus.denied || AuthorizationStatus.deniedPermanently => PushStatus.denied,
        AuthorizationStatus.notDetermined => PushStatus.notDetermined,
      };

  /// Pede a permissão e registra o aparelho. Chamar só a partir de um toque do
  /// usuário: sem o toque, o Safari do iPhone bloqueia o pedido.
  Future<PushStatus> enable() async {
    final current = await status();
    if (current == PushStatus.unsupported || current == PushStatus.needsInstall) return current;
    final settings = await FirebaseMessaging.instance.requestPermission();
    final result = _fromAuthorization(settings.authorizationStatus);
    if (result == PushStatus.enabled) await _registerToken();
    return result;
  }

  /// Começa a acompanhar a sessão: com permissão já dada, registra o aparelho
  /// para quem entrou; ao sair, o aparelho deixa de receber.
  void start(Stream<UserProfile?> authChanges) {
    if (!_firebaseReady) return;
    authChanges.listen((user) async {
      if (user == null) {
        await _unregister();
      } else if (user.id != _currentUserId && !isDemoMode()) {
        _currentUserId = user.id;
        if (await status() == PushStatus.enabled) await _registerToken();
      }
    });

    // Token clássico do FCM (envio pela API HTTP v1 com message.token). A API
    // nova (register/onRegistered) devolve o id da instalação para outro modo
    // de envio; fica para quando a função notify for migrada.
    // ignore: deprecated_member_use
    _tokenRefresh ??= FirebaseMessaging.instance.onTokenRefresh.listen((token) {
      if (_currentUserId != null) _saveToken(token);
    });

    if (!kIsWeb) {
      // No navegador o service worker abre o link sozinho
      _opened ??= FirebaseMessaging.onMessageOpenedApp.listen(_openFromMessage);
      FirebaseMessaging.instance.getInitialMessage().then((m) {
        if (m != null) _openFromMessage(m);
      });
    }
  }

  void _openFromMessage(RemoteMessage message) {
    final link = message.data['deeplink'] as String?;
    if (link != null && link.startsWith('/')) onOpenDeeplink?.call(link);
  }

  Future<void> _registerToken() async {
    try {
      // ignore: deprecated_member_use
      final token = await FirebaseMessaging.instance.getToken(
        vapidKey: kIsWeb ? FirebaseConfig.webPushVapidKey : null,
      );
      if (token != null) await _saveToken(token);
    } catch (e) {
      debugPrint('Não foi possível registrar o aparelho para push: $e');
    }
  }

  Future<void> _saveToken(String token) async {
    final supabase = client;
    final userId = supabase?.auth.currentUser?.id;
    if (supabase == null || userId == null || isDemoMode()) return;
    try {
      await supabase.from('device_tokens').upsert({
        'user_id': userId,
        'token': token,
        'platform': _platform,
        'last_seen_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'token');
      _currentUserId = userId;
    } catch (e) {
      debugPrint('Não foi possível gravar o aparelho para push: $e');
    }
  }

  /// Ao sair da conta: o token é invalidado no FCM, e a função `notify` apaga
  /// a linha na próxima tentativa de envio (a sessão já pode ter acabado).
  Future<void> _unregister() async {
    if (_currentUserId == null) return;
    _currentUserId = null;
    try {
      // ignore: deprecated_member_use
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {}
  }
}
