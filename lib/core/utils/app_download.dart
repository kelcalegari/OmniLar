import 'package:flutter/foundation.dart';
import 'app_download_stub.dart' if (dart.library.js_interop) 'app_download_web.dart' as impl;

class AppDownloadConfig {
  static const String apkDownloadUrl =
      'https://rygxmpwzofgieodvhpcy.supabase.co/storage/v1/object/public/releases/OmniLar-arm64-release.apk';

  static void downloadApk() {
    if (kIsWeb) {
      impl.triggerApkDownload(apkDownloadUrl);
    }
  }
}
