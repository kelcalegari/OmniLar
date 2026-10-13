import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'clipboard_fallback_stub.dart'
    if (dart.library.js_interop) 'clipboard_fallback_web.dart';

/// Copia [text] e diz se copiou de verdade.
///
/// No navegador o `Clipboard` do Flutter falha quando a página não está em
/// contexto seguro (http fora de localhost); nesse caso tenta o método antigo.
Future<bool> copyToClipboard(String text) async {
  try {
    await Clipboard.setData(ClipboardData(text: text));
    return true;
  } catch (_) {
    return legacyCopyText(text);
  }
}

/// Copia [text] e só mostra [onCopied] se a cópia aconteceu; senão avisa da falha.
Future<void> copyWithFeedback(
  BuildContext context,
  String text, {
  required SnackBar onCopied,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final ok = await copyToClipboard(text);
  messenger.showSnackBar(
    ok
        ? onCopied
        : const SnackBar(
            content: Text(
              'Não foi possível copiar. Selecione o texto e copie manualmente.',
            ),
          ),
  );
}
