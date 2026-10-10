import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // Cores Principais (Marca)
  static const Color primary = Color(0xFF0F766E); // Teal 700 - Elegante e moderno
  static const Color primaryLight = Color(0xFF14B8A6); // Teal 500
  static const Color primaryDark = Color(0xFF115E59); // Teal 800
  static const Color accent = Color(0xFF6366F1); // Indigo 500 - Toque vibrante

  // Semântica Financeira (P2P / Saldo)
  static const Color debtRed = Color(0xFFE11D48); // Rose 600 - Eu devo (vermelho vivo, não agressivo)
  static const Color debtRedLight = Color(0xFFFFF1F2); // Rose 50
  static const Color creditGreen = Color(0xFF059669); // Emerald 600 - Me devem (verde positivo)
  static const Color creditGreenLight = Color(0xFFECFDF5); // Emerald 50

  // Status de Fôlego da Casa
  static const Color folegoPositive = Color(0xFF10B981); // Verde saudável
  static const Color folegoWarning = Color(0xFFF59E0B); // Âmbar / Atenção
  static const Color folegoDanger = Color(0xFFEF4444); // Vermelho / Comprometido

  // Tons Neutros - Tema Claro
  static const Color backgroundLight = Color(0xFFF8FAFC); // Slate 50
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color cardLight = Color(0xFFFFFFFF);
  static const Color borderLight = Color(0xFFE2E8F0); // Slate 200
  static const Color textPrimaryLight = Color(0xFF0F172A); // Slate 900
  static const Color textSecondaryLight = Color(0xFF64748B); // Slate 500
  static const Color textTertiaryLight = Color(0xFF94A3B8); // Slate 400

  // Tons Neutros - Tema Escuro
  static const Color backgroundDark = Color(0xFF090D16); // Super dark blue/slate
  static const Color surfaceDark = Color(0xFF111827); // Gray 900
  static const Color cardDark = Color(0xFF1E293B); // Slate 800
  static const Color borderDark = Color(0xFF334155); // Slate 700
  static const Color textPrimaryDark = Color(0xFFF8FAFC); // Slate 50
  static const Color textSecondaryDark = Color(0xFF94A3B8); // Slate 400
  static const Color textTertiaryDark = Color(0xFF64748B); // Slate 500
}
