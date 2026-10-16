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

  /// Permitido, mas o aparelho não foi registrado (o motivo fica em
  /// [PushService.lastError]).
  failed,
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

  /// Motivo da última falha ao registrar o aparelho, para mostrar na tela.
  String? lastError;

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
    // No navegador o pedido sai antes de qualquer espera: depois de um await o
    // Safari (e o iPhone com o site instalado) já não conta como toque e
    // ignora o pedido sem mostrar nada.
    Future<String>? browserRequest;
    if (kIsWeb) {
      final env = environment;
      if (env.hasNotificationApi && !(env.isIos && !env.isStandalone)) {
        browserRequest = PushEnvironment.requestBrowserPermission()
            .catchError((Object e) => 'error: $e');
      }
    }

    final current = await status();
    if (current == PushStatus.unsupported || current == PushStatus.needsInstall) return current;

    final PushStatus result;
    if (browserRequest != null) {
      final permission = await browserRequest;
      if (permission.startsWith('error')) {
        lastError = 'Navegador: $permission';
        return PushStatus.failed;
      }
      result = switch (permission) {
        'granted' => PushStatus.enabled,
        'denied' => PushStatus.denied,
        _ => PushStatus.notDetermined,
      };
    } else {
      final settings = await FirebaseMessaging.instance.requestPermission();
      result = _fromAuthorization(settings.authorizationStatus);
    }
    if (result != PushStatus.enabled) return result;
    return await _registerToken() ? PushStatus.enabled : PushStatus.failed;
  }

  /// Com a permissão já dada, confere o registro deste aparelho (abrir os
  /// Ajustes refaz o registro e mostra uma falha, se houver).
  Future<PushStatus> refresh() async {
    final current = await status();
    if (current != PushStatus.enabled) return current;
    return await _registerToken() ? PushStatus.enabled : PushStatus.failed;
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

  /// Pede o token ao FCM e grava. Devolve se deu certo; senão, o motivo fica
  /// em [lastError].
  Future<bool> _registerToken() async {
    try {
      // ignore: deprecated_member_use
      final token = await FirebaseMessaging.instance.getToken(
        vapidKey: kIsWeb ? FirebaseConfig.webPushVapidKey : null,
      );
      if (token == null || token.isEmpty) {
        lastError = 'O Firebase não devolveu o código deste aparelho.';
        return false;
      }
      return await _saveToken(token);
    } catch (e) {
      lastError = 'Firebase: $e';
      debugPrint('Não foi possível registrar o aparelho para push: $e');
      return false;
    }
  }

  Future<bool> _saveToken(String token) async {
    final supabase = client;
    final userId = supabase?.auth.currentUser?.id;
    if (supabase == null || userId == null || isDemoMode()) {
      lastError = 'Sem sessão: entre na conta e tente de novo.';
      return false;
    }
    try {
      await supabase.from('device_tokens').upsert({
        'user_id': userId,
        'token': token,
        'platform': _platform,
        'last_seen_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'token');
      _currentUserId = userId;
      lastError = null;
      return true;
    } catch (e) {
      lastError = 'Banco: $e';
      debugPrint('Não foi possível gravar o aparelho para push: $e');
      return false;
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
