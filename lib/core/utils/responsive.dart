import 'package:flutter/material.dart';

const double kMobileBreakpoint = 768.0;
const double kDesktopBreakpoint = 1024.0;
const double kUltraWideBreakpoint = 1360.0;
const double kMaxContentWidth = 1600.0;

extension ResponsiveContext on BuildContext {
  double get screenWidth => MediaQuery.sizeOf(this).width;
  double get screenHeight => MediaQuery.sizeOf(this).height;

  bool get isMobile => screenWidth < kMobileBreakpoint;
  bool get isWideScreen => screenWidth >= kMobileBreakpoint;
  bool get isTablet => screenWidth >= kMobileBreakpoint && screenWidth < kDesktopBreakpoint;
  bool get isDesktop => screenWidth >= kDesktopBreakpoint;
  bool get isUltraWide => screenWidth >= kUltraWideBreakpoint;
}

/// Exibe um modal adaptativo:
/// - No Celular (Mobile): sobe como ModalBottomSheet da base da tela.
/// - No PC/Desktop/Web: abre como Dialog centralizado com largura máxima controlada.
Future<T?> showAdaptiveModal<T>({
  required BuildContext context,
  required Widget child,
  double maxWidth = 540.0,
  bool isDismissible = true,
}) {
  if (context.isMobile) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      isDismissible: isDismissible,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => child,
    );
  } else {
    return showDialog<T>(
      context: context,
      barrierDismissible: isDismissible,
      builder: (dialogCtx) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: maxWidth,
              maxHeight: MediaQuery.sizeOf(dialogCtx).height * 0.88,
            ),
            child: child,
          ),
        );
      },
    );
  }
}
