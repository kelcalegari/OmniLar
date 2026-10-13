import 'dart:js_interop';
import 'dart:js_interop_unsafe';

@JS('document')
external JSObject get _document;

/// Copia pelo `document.execCommand('copy')`, que funciona em página sem
/// contexto seguro (http fora de localhost), onde `navigator.clipboard` não existe.
bool legacyCopyText(String text) {
  JSObject? area;
  final body = _document.getProperty<JSObject?>('body'.toJS);
  if (body == null) return false;
  try {
    area = _document.callMethod<JSObject>(
      'createElement'.toJS,
      'textarea'.toJS,
    );
    area.setProperty('value'.toJS, text.toJS);
    area.callMethod<JSAny?>('setAttribute'.toJS, 'readonly'.toJS, ''.toJS);
    final style = area.getProperty<JSObject>('style'.toJS);
    style.setProperty('position'.toJS, 'fixed'.toJS);
    style.setProperty('top'.toJS, '0'.toJS);
    style.setProperty('left'.toJS, '0'.toJS);
    style.setProperty('opacity'.toJS, '0'.toJS);
    body.callMethod<JSAny?>('appendChild'.toJS, area);
    area.callMethod<JSAny?>('focus'.toJS);
    area.callMethod<JSAny?>('select'.toJS);
    final ok = _document.callMethod<JSBoolean>('execCommand'.toJS, 'copy'.toJS);
    return ok.toDart;
  } catch (_) {
    return false;
  } finally {
    if (area != null) {
      try {
        body.callMethod<JSAny?>('removeChild'.toJS, area);
      } catch (_) {}
    }
  }
}
