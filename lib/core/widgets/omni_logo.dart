import 'package:flutter/material.dart';

enum OmniLogoVariant {
  horizontal,
  iconOnly,
  fullVertical,
}

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
            ? 'assets/images/logos/logo_horizontal_dark.jpg'
            : 'assets/images/logos/logo_horizontal_light.jpg';
        break;
      case OmniLogoVariant.iconOnly:
        assetPath = effectiveIsDark
            ? 'assets/images/logos/app_icon_dark.jpg'
            : 'assets/images/logos/app_icon_light.jpg';
        break;
      case OmniLogoVariant.fullVertical:
        assetPath = 'assets/images/logos/logo_clean.jpg';
        break;
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(variant == OmniLogoVariant.iconOnly ? 10 : 0),
      child: Image.asset(
        assetPath,
        width: width,
        height: height,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          // Fallback gracioso caso a imagem não carregue
          return Icon(
            Icons.home_work_rounded,
            size: height ?? 32,
            color: Theme.of(context).colorScheme.primary,
          );
        },
      ),
    );
  }
}
