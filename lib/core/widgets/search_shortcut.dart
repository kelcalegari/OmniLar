import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// `Ctrl + F` (ou `Cmd + F`) leva ao campo de busca da tela aberta.
///
/// A tela com busca registra o [FocusNode] do campo enquanto existe. Sem campo
/// registrado na rota visível, a tecla segue adiante (a busca do navegador).
class SearchShortcut {
  SearchShortcut._();

  static final List<FocusNode> _fields = [];

  static void register(FocusNode node) {
    _fields
      ..remove(node)
      ..add(node);
  }

  static void unregister(FocusNode node) => _fields.remove(node);

  /// Foca o campo mais recente que está na rota visível; diz se achou um.
  static bool focusSearch() {
    for (final node in _fields.reversed) {
      final context = node.context;
      if (context == null || !context.mounted || !node.canRequestFocus) continue;
      if (!(ModalRoute.of(context)?.isCurrent ?? true)) continue;
      // Aba escondida (as abas do app ficam vivas, só desligadas): não conta
      if (!TickerMode.valuesOf(context).enabled) continue;
      node.requestFocus();
      return true;
    }
    return false;
  }

  static bool _isShortcut(KeyEvent event) {
    if (event is! KeyDownEvent || event.logicalKey != LogicalKeyboardKey.keyF) return false;
    final keyboard = HardwareKeyboard.instance;
    return (keyboard.isControlPressed || keyboard.isMetaPressed) && !keyboard.isAltPressed && !keyboard.isShiftPressed;
  }

  /// Envolve o app (no `builder` do `MaterialApp`) e atende a tecla.
  static Widget listener({required Widget child}) => Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: (_, event) =>
            _isShortcut(event) && focusSearch() ? KeyEventResult.handled : KeyEventResult.ignored,
        child: child,
      );
}
