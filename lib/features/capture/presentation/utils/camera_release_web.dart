import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

final _cameras = <web.MediaStream>[];
var _watching = false;

void watchBrowserCamera() {
  if (_watching) return;
  final devices = (web.window.navigator as JSObject).getProperty<JSObject?>('mediaDevices'.toJS);
  if (devices == null) return;
  final original = devices.getProperty<JSFunction?>('getUserMedia'.toJS);
  if (original == null) return;
  _watching = true;

  JSPromise<JSAny?> getUserMedia(JSAny? constraints) {
    final promise = original.callAsFunction(devices, constraints) as JSPromise<JSAny?>;
    promise.toDart.then((stream) {
      if (stream != null && stream.isA<web.MediaStream>()) _cameras.add(stream as web.MediaStream);
    }, onError: (_) {});
    return promise;
  }

  devices.setProperty('getUserMedia'.toJS, getUserMedia.toJS);
}

void releaseBrowserCamera() {
  for (final stream in _cameras) {
    for (final track in stream.getTracks().toDart) {
      track.stop();
    }
  }
  _cameras.clear();
}
