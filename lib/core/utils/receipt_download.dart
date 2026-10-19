import 'package:flutter/foundation.dart';
import 'receipt_download_stub.dart' if (dart.library.js_interop) 'receipt_download_web.dart' as impl;

void downloadReceiptFile(String url, String fileName) {
  if (kIsWeb) {
    impl.triggerReceiptDownload(url, fileName);
  }
}
