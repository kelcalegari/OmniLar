import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../features/finance/presentation/pages/add_expense_page.dart';
import '../utils/responsive.dart';

class NewExpenseIntent extends Intent {
  const NewExpenseIntent();
}

class CloseModalIntent extends Intent {
  const CloseModalIntent();
}

/// Envolve a árvore de widgets no desktop/web para fornecer atalhos de produtividade:
/// - Ctrl + N / Cmd + N: Abrir modal de novo lançamento de despesa.
/// - Esc: Fechar modais ou diálogos abertos.
class DesktopShortcutsWrapper extends StatelessWidget {
  final Widget child;

  const DesktopShortcutsWrapper({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyN): const NewExpenseIntent(),
        LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.keyN): const NewExpenseIntent(),
        LogicalKeySet(LogicalKeyboardKey.escape): const CloseModalIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          NewExpenseIntent: CallbackAction<NewExpenseIntent>(
            onInvoke: (intent) {
              final navState = Navigator.maybeOf(context);
              if (navState != null) {
                showAdaptiveModal(
                  context: context,
                  maxWidth: 540,
                  child: const AddExpensePage(),
                );
              }
              return null;
            },
          ),
          CloseModalIntent: CallbackAction<CloseModalIntent>(
            onInvoke: (intent) {
              final navState = Navigator.maybeOf(context);
              if (navState != null && navState.canPop()) {
                navState.maybePop();
              }
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: child,
        ),
      ),
    );
  }
}
