import 'package:flutter/material.dart';
import '../utils/app_haptics.dart';

/// Controlador global reativo para ocultar ou exibir valores monetários no app
class PrivacyController extends ValueNotifier<bool> {
  PrivacyController() : super(false); // false = valores visíveis, true = ocultos

  void toggle() {
    value = !value;
    AppHaptics.light();
  }
}

final privacyController = PrivacyController();

/// Botão de alternância com ícone de olho (Visível / Oculto)
class PrivacyToggleButton extends StatelessWidget {
  const PrivacyToggleButton({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: privacyController,
      builder: (context, isHidden, _) {
        return IconButton(
          icon: Icon(
            isHidden ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            size: 20,
          ),
          tooltip: isHidden ? 'Exibir valores' : 'Ocultar valores',
          onPressed: privacyController.toggle,
        );
      },
    );
  }
}

/// Widget utilitário que oculta ou exibe qualquer texto de valor
class PrivacySensitiveText extends StatelessWidget {
  final String formattedValue;
  final TextStyle? style;
  final String placeholder;

  const PrivacySensitiveText(
    this.formattedValue, {
    super.key,
    this.style,
    this.placeholder = 'R\$ •••••',
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: privacyController,
      builder: (context, isHidden, _) {
        return Text(
          isHidden ? placeholder : formattedValue,
          style: style,
        );
      },
    );
  }
}
