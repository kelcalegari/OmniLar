import 'package:flutter/services.dart';

/// Helper utilitário para feedback tátil (haptic feedback) em dispositivos móveis.
/// No Desktop ou Web, as chamadas são silenciosamente ignoradas pelo Flutter.
class AppHaptics {
  AppHaptics._();

  /// Toque suave: navegação entre abas, seleção de chips, abertura de modais.
  static void light() {
    HapticFeedback.lightImpact();
  }

  /// Toque médio: confirmação de formulários, salvamento de despesas, pagamento.
  static void medium() {
    HapticFeedback.mediumImpact();
  }

  /// Feedback de sucesso: conclusão de tarefas, quitação de parcelas ou liquidação.
  static void success() {
    HapticFeedback.mediumImpact();
  }

  /// Toque sutil de seleção: toggle de checkbox na lista de compras.
  static void selection() {
    HapticFeedback.selectionClick();
  }
}
