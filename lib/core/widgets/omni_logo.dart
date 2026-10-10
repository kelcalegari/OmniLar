import 'package:flutter/material.dart';

enum OmniLogoVariant {
  horizontal,
  iconOnly,
  fullVertical,
}

/// Widget unificado do Logo OmniLar com suporte a fundo transparente,
/// variações horizontais, verticais e ícone puro, e modos claro/escuro.
class OmniLogo extends StatelessWidget {
  final double? width;
  final double? height;
  final OmniLogoVariant variant;
  final bool? isDark;

  const OmniLogo({
    super.key,
    this.width,
    this.height,
    this.variant = OmniLogoVariant.horizontal,
    this.isDark,
  });

  const OmniLogo.horizontal({
    super.key,
    this.width,
    this.height = 36,
    this.isDark,
  }) : variant = OmniLogoVariant.horizontal;

  const OmniLogo.icon({
    super.key,
    this.width = 44,
    this.height = 44,
    this.isDark,
  }) : variant = OmniLogoVariant.iconOnly;

  const OmniLogo.vertical({
    super.key,
    this.width = 120,
    this.height = 120,
    this.isDark,
  }) : variant = OmniLogoVariant.fullVertical;

  @override
  Widget build(BuildContext context) {
    final effectiveIsDark = isDark ?? (Theme.of(context).brightness == Brightness.dark);

    String assetPath;
    switch (variant) {
      case OmniLogoVariant.horizontal:
        assetPath = effectiveIsDark
            ? 'assets/images/logos/logo_horizontal_dark.png'
            : 'assets/images/logos/logo_horizontal_light.png';
        break;
      case OmniLogoVariant.iconOnly:
        assetPath = effectiveIsDark
            ? 'assets/images/logos/icon_dark.png'
            : 'assets/images/logos/icon_light.png';
        break;
      case OmniLogoVariant.fullVertical:
        assetPath = effectiveIsDark
            ? 'assets/images/logos/logo_vertical_dark.png'
            : 'assets/images/logos/logo_vertical_light.png';
        break;
    }

    return Image.asset(
      assetPath,
      width: width,
      height: height,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) {
        return Icon(
          Icons.home_work_rounded,
          size: height ?? 32,
          color: Theme.of(context).colorScheme.primary,
        );
      },
    );
  }
}
