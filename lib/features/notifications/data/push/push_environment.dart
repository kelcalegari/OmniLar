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
}
