import 'dart:js_interop';
import 'dart:js_interop_unsafe';

@JS('navigator')
external JSObject get _navigator;

@JS('window')
external JSObject get _window;

/// Resultado de uma tentativa de abrir o menu de compartilhamento do sistema.
enum NativeShareResult { shared, cancelled, unsupported }

/// Abre o menu de compartilhamento do sistema (Web Share API) com [text].
Future<NativeShareResult> nativeShareText(String text) async {
  if (!_navigator.has('share')) return NativeShareResult.unsupported;
  final data = JSObject()..setProperty('text'.toJS, text.toJS);
  if (_navigator.has('canShare')) {
    final can = _navigator.callMethod<JSBoolean>('canShare'.toJS, data);
    if (!can.toDart) return NativeShareResult.unsupported;
  }
  try {
    await _navigator.callMethod<JSPromise<JSAny?>>('share'.toJS, data).toDart;
    return NativeShareResult.shared;
  } catch (e) {
    // Fechar o menu sem escolher gera AbortError: não é falha.
    if (e.toString().contains('AbortError')) {
      return NativeShareResult.cancelled;
    }
    return NativeShareResult.unsupported;
  }
}

/// Abre o WhatsApp (app ou web) com [text] pronto para escolher o contato.
bool openWhatsAppText(String text) {
  final url = 'https://wa.me/?text=${Uri.encodeComponent(text)}';
  try {
    _window.callMethod<JSAny?>('open'.toJS, url.toJS, '_blank'.toJS);
    return true;
  } catch (_) {
    return false;
  }
}

const bool canOpenWhatsApp = true;
