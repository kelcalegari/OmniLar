import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/omni_logo.dart';
import '../../../auth/presentation/cubit/auth_cubit.dart';
import '../../../auth/presentation/cubit/auth_state.dart';
import '../../../finance/presentation/cubit/finance_cubit.dart';

class SplashPage extends StatefulWidget {
  /// Página que estava aberta antes de recarregar (web).
  final String? returnTo;

  const SplashPage({super.key, this.returnTo});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeIn,
    );

    _scaleAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutBack,
      ),
    );

    _controller.forward();
    _runWarmupAndNavigate();
  }

  Future<void> _runWarmupAndNavigate() async {
    // 1. Duração mínima confortável para a animação do logo
    final minTimer = Future.delayed(const Duration(milliseconds: 850));

    // 2. Dispara e aguarda checagem de autenticação e aquecimento do ciclo financeiro
    final authCubit = sl<AuthCubit>();
    final from = widget.returnTo;
    authCubit.checkAuthStatus();

    // Sessão salva ainda carregando perfil e casa: espera a resposta antes de decidir o destino
    if (authCubit.state.status == AuthStatus.initial) {
      try {
        await authCubit.stream
            .firstWhere((s) => s.status != AuthStatus.initial)
            .timeout(const Duration(seconds: 10));
      } catch (_) {
        authCubit.checkAuthStatus();
      }
      if (!mounted) return;
    }

    // Se já estiver com sessão e casa ativa, pré-carrega os dados do ciclo
    Future<void>? financeFuture;
    if (authCubit.state.isAuthenticated && authCubit.state.hasHouse) {
      // A abertura não fica presa na carga: a Home termina de carregar sozinha
      financeFuture = sl<FinanceCubit>()
          .loadCycleData()
          .timeout(const Duration(seconds: 4))
          .catchError((_) {});
    }

    // Aguarda em paralelo o tempo da animação e a carga de dados
    await Future.wait([
      minTimer,
      if (financeFuture != null) financeFuture,
    ]);

    if (!mounted) return;

    // 3. Navegação suave direta ao destino correto
    final authState = authCubit.state;
    if (authState.isAuthenticated && authState.hasHouse) {
      // Volta para a página que estava aberta antes de recarregar
      final canReturn = from != null &&
          from.startsWith('/') &&
          !from.startsWith('//') &&
          !from.startsWith('/splash');
      context.go(canReturn ? from : '/casa');
    } else if (authState.isAuthenticated && !authState.hasHouse) {
      context.go('/onboarding/house');
    } else {
      context.go(kIsWeb ? '/landing' : '/login');
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
      body: Center(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: ScaleTransition(
            scale: _scaleAnimation,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const OmniLogo.vertical(
                  width: 140,
                  height: 140,
                ),
                const SizedBox(height: 16),
                Text(
                  'Gestão Financeira & Harmonia do Lar',
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondaryLight,
                  ),
                ),
                const SizedBox(height: 36),
                SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
