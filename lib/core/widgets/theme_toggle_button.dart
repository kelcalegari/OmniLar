import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../theme/theme_cubit.dart';
import '../utils/responsive.dart';

class ThemeToggleButton extends StatelessWidget {
  final bool showTooltip;

  const ThemeToggleButton({
    super.key,
    this.showTooltip = true,
  });

  @override
  Widget build(BuildContext context) {
    ThemeCubit? cubit;
    try {
      cubit = context.watch<ThemeCubit>();
    } catch (_) {
      cubit = null;
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return IconButton(
      tooltip: showTooltip ? (isDark ? 'Mudar para Modo Claro' : 'Mudar para Modo Escuro') : null,
      icon: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        transitionBuilder: (child, anim) => RotationTransition(
          turns: anim,
          child: FadeTransition(opacity: anim, child: child),
        ),
        child: Icon(
          isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
          key: ValueKey(isDark),
          color: isDark ? Colors.amber : null,
        ),
      ),
      onPressed: cubit != null ? () => cubit!.toggleTheme(context) : null,
      onLongPress: () => showThemeSelectionDialog(context),
    );
  }
}

/// Modal acessível para escolher entre Claro, Escuro e Sistema
void showThemeSelectionDialog(BuildContext context) {
  ThemeCubit? cubit;
  try {
    cubit = context.read<ThemeCubit>();
  } catch (_) {
    cubit = null;
  }
  final currentMode = cubit?.state ?? ThemeMode.system;

  showAdaptiveModal(
    context: context,
    maxWidth: 420,
    child: Builder(
      builder: (modalCtx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Row(
                  children: [
                    Icon(Icons.palette_rounded, color: Colors.blueAccent, size: 24),
                    SizedBox(width: 10),
                    Text(
                      'Aparência & Tema',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'Escolha a forma como o Omni Lar é exibido.',
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
                const SizedBox(height: 16),

                _buildOption(
                  context: modalCtx,
                  mode: ThemeMode.light,
                  current: currentMode,
                  icon: Icons.light_mode_rounded,
                  iconColor: Colors.amber,
                  title: 'Modo Claro',
                  subtitle: 'Cores claras e alto brilho para o dia',
                  cubit: cubit,
                ),
                const SizedBox(height: 8),

                _buildOption(
                  context: modalCtx,
                  mode: ThemeMode.dark,
                  current: currentMode,
                  icon: Icons.dark_mode_rounded,
                  iconColor: Colors.indigoAccent,
                  title: 'Modo Escuro',
                  subtitle: 'Tons escuros confortáveis para a visão',
                  cubit: cubit,
                ),
                const SizedBox(height: 8),

                _buildOption(
                  context: modalCtx,
                  mode: ThemeMode.system,
                  current: currentMode,
                  icon: Icons.settings_brightness_rounded,
                  iconColor: Colors.teal,
                  title: 'Padrão do Sistema',
                  subtitle: 'Acompanha o modo configurado no dispositivo',
                  cubit: cubit,
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    ),
  );
}

Widget _buildOption({
  required BuildContext context,
  required ThemeMode mode,
  required ThemeMode current,
  required IconData icon,
  required Color iconColor,
  required String title,
  required String subtitle,
  required ThemeCubit? cubit,
}) {
  final isSelected = mode == current;
  final theme = Theme.of(context);

  return InkWell(
    onTap: () {
      cubit?.setThemeMode(mode);
      // Fecha APENAS o modal usando o modalCtx interno
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    },
    borderRadius: BorderRadius.circular(12),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isSelected ? theme.colorScheme.primary.withValues(alpha: 0.12) : theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected ? theme.colorScheme.primary : Colors.grey.withValues(alpha: 0.2),
          width: isSelected ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isSelected ? theme.colorScheme.primary : null,
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
          if (isSelected)
            Icon(Icons.check_circle_rounded, color: theme.colorScheme.primary, size: 20),
        ],
      ),
    ),
  );
}
