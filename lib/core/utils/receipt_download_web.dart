import 'package:web/web.dart' as web;

void triggerReceiptDownload(String url, String fileName) {
  final anchor = web.document.createElement('a') as web.HTMLAnchorElement;
  anchor.href = url;
  anchor.download = fileName;
  anchor.target = '_blank';
  web.document.body?.appendChild(anchor);
  anchor.click();
  anchor.remove();
}
