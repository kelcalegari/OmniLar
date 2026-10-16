import 'push_environment_stub.dart' if (dart.library.js_interop) 'push_environment_web.dart' as impl;

/// O que o navegador permite para o push. Fora da web tudo é falso.
class PushEnvironment {
  /// iPhone ou iPad (no Safari ou em qualquer navegador, que no iOS é Safari).
  final bool isIos;

  /// Aberto pelo ícone da Tela de Início (site instalado).
  final bool isStandalone;

  /// O navegador tem a API de notificações. No iPhone ela só existe instalado.
  final bool hasNotificationApi;

  const PushEnvironment({
    required this.isIos,
    required this.isStandalone,
    required this.hasNotificationApi,
  });

  static PushEnvironment read() => impl.readPushEnvironment();

  /// Pede a permissão de notificação ao navegador: 'granted', 'denied' ou
  /// 'default'. A chamada sai na hora (antes de qualquer espera), porque o
  /// Safari só mostra o pedido dentro do toque do usuário.
  static Future<String> requestBrowserPermission() => impl.requestBrowserPermission();
}
