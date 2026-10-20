import 'package:flutter/material.dart';

import 'clipboard_helper.dart';
import 'share_stub.dart' if (dart.library.js_interop) 'share_web.dart';

/// Compartilha [text]: abre o menu do sistema quando o navegador tem um;
/// senão oferece enviar pelo WhatsApp ou copiar (mostrando [onCopied]).
/// Se [phone] for informado e o WhatsApp puder ser aberto, tenta disparar
/// diretamente para a conversa daquele número.
Future<void> shareText(
  BuildContext context,
  String text, {
  String? phone,
  required SnackBar onCopied,
}) async {
  // Se houver telefone direto e WhatsApp estiver disponível no ambiente, tenta abrir
  if (phone != null && phone.trim().isNotEmpty && canOpenWhatsApp) {
    if (openWhatsAppText(text, phone: phone)) return;
  }

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
            title: Text(phone != null && phone.trim().isNotEmpty
                ? 'Enviar no WhatsApp ($phone)'
                : 'Enviar no WhatsApp'),
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
  if (choice == 'whatsapp' && openWhatsAppText(text, phone: phone)) return;
  if (choice != null) {
    await copyWithFeedback(context, text, onCopied: onCopied);
  }
}
