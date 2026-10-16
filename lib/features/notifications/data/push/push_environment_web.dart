import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import 'push_environment.dart';

PushEnvironment readPushEnvironment() {
  final navigator = web.window.navigator;
  final userAgent = navigator.userAgent;
  // iPadOS se apresenta como Mac, mas tem tela de toque
  final isIos = RegExp(r'iPhone|iPad|iPod').hasMatch(userAgent) ||
      (userAgent.contains('Macintosh') && navigator.maxTouchPoints > 1);

  final legacyStandalone = (navigator as JSObject).getProperty<JSAny?>('standalone'.toJS);
  final isStandalone = web.window.matchMedia('(display-mode: standalone)').matches ||
      (legacyStandalone != null && legacyStandalone.isA<JSBoolean>() && (legacyStandalone as JSBoolean).toDart);

  return PushEnvironment(
    isIos: isIos,
    isStandalone: isStandalone,
    hasNotificationApi: globalContext.has('Notification') && globalContext.has('PushManager'),
  );
}
