import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class ThemeCubit extends Cubit<ThemeMode> {
  ThemeCubit([super.initialMode = ThemeMode.system]);

  void setThemeMode(ThemeMode mode) {
    emit(mode);
  }

  void toggleTheme(BuildContext context) {
    final currentBrightness = Theme.of(context).brightness;
    if (state == ThemeMode.light) {
      emit(ThemeMode.dark);
    } else if (state == ThemeMode.dark) {
      emit(ThemeMode.light);
    } else {
      // Se estava em modo sistema, inverte o brilho atual
      emit(currentBrightness == Brightness.dark ? ThemeMode.light : ThemeMode.dark);
    }
  }

  bool isDark(BuildContext context) {
    if (state == ThemeMode.dark) return true;
    if (state == ThemeMode.light) return false;
    return Theme.of(context).brightness == Brightness.dark;
  }
}
