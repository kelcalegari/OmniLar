import 'package:flutter/material.dart';

import 'clipboard_helper.dart';
import 'share_stub.dart' if (dart.library.js_interop) 'share_web.dart';

/// Compartilha [text]: abre o menu do sistema quando o navegador tem um;
/// senão oferece enviar pelo WhatsApp ou copiar (mostrando [onCopied]).
Future<void> shareText(
  BuildContext context,
  String text, {
  required SnackBar onCopied,
}) async {
  final result = await nativeShareText(text);
  if (result != NativeShareResult.unsupported || !context.mounted) return;

  if (!canOpenWhatsApp) {
    await copyWithFeedback(context, text, onCopied: onCopied);
    return;
  }

  final choice = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.chat_rounded),
            title: const Text('Enviar no WhatsApp'),
            onTap: () => Navigator.pop(sheetContext, 'whatsapp'),
          ),
          ListTile(
            leading: const Icon(Icons.copy_rounded),
            title: const Text('Copiar texto'),
            onTap: () => Navigator.pop(sheetContext, 'copy'),
          ),
        ],
      ),
    ),
  );
  if (!context.mounted) return;
  if (choice == 'whatsapp' && openWhatsAppText(text)) return;
  if (choice != null) {
    await copyWithFeedback(context, text, onCopied: onCopied);
  }
}
