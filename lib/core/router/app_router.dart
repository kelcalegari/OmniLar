import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../di/service_locator.dart';
import '../widgets/scaffold_with_nav_bar.dart';
import '../../features/auth/presentation/cubit/auth_cubit.dart';
import '../../features/auth/presentation/cubit/auth_state.dart';
import '../../features/auth/presentation/pages/login_page.dart';
import '../../features/auth/presentation/pages/house_onboarding_page.dart';
import '../../features/home/presentation/pages/home_page.dart';
import '../../features/p2p/presentation/pages/p2p_page.dart';
import '../../features/calendar/presentation/pages/calendar_page.dart';
import '../../features/reports/presentation/pages/reports_page.dart';
import '../../features/settings/presentation/pages/settings_page.dart';
import '../../features/settlement/presentation/pages/settlement_hub_page.dart';
import '../../features/shopping/presentation/pages/shopping_list_page.dart';
import '../../features/finance/presentation/pages/savings_vaults_page.dart';

class GoRouterRefreshStream extends ChangeNotifier {
  late final StreamSubscription<dynamic> _subscription;

  GoRouterRefreshStream(Stream<dynamic> stream) {
    notifyListeners();
    _subscription = stream.asBroadcastStream().listen((_) => notifyListeners());
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

class AppRouter {
  AppRouter._();

  static final GoRouter router = GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/casa',
    refreshListenable: GoRouterRefreshStream(sl<AuthCubit>().stream),
    redirect: (context, state) {
      final authState = sl<AuthCubit>().state;
      final location = state.uri.path;
      final isLoggingIn = location == '/login';
      final isOnboarding = location == '/onboarding/house';

      // 1. Não autenticado -> vai para /login
      if (authState.status == AuthStatus.unauthenticated || !authState.isAuthenticated) {
        return isLoggingIn ? null : '/login';
      }

      // 2. Autenticado mas sem casa -> vai para /onboarding/house
      if (authState.isAuthenticated && !authState.hasHouse) {
        return isOnboarding ? null : '/onboarding/house';
      }

      // 3. Autenticado com casa ativa -> não deixa ficar no login nem onboarding
      if (authState.isAuthenticated && authState.hasHouse) {
        if (isLoggingIn || isOnboarding) {
          return '/casa';
        }
      }

      return null;
    },
    routes: [
      // Rota de Autenticação (Fase 0)
      GoRoute(
        path: '/login',
        name: 'login',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const LoginPage(),
      ),
      // Rota de Onboarding da Casa (Fase 0)
      GoRoute(
        path: '/onboarding/house',
        name: 'house_onboarding',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const HouseOnboardingPage(),
      ),
      // Shell com as 5 Abas Principais
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return ScaffoldWithNavBar(navigationShell: navigationShell);
        },
        branches: [
          // Aba 1: A Casa
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/casa',
                name: 'home',
                pageBuilder: (context, state) => const NoTransitionPage(
                  child: HomePage(),
                ),
                routes: [
                  GoRoute(
                    path: 'fechamento',
                    name: 'settlement',
                    builder: (context, state) => const SettlementHubPage(),
                  ),
                  GoRoute(
                    path: 'compras',
                    name: 'shopping',
                    builder: (context, state) => const ShoppingListPage(),
                  ),
                  GoRoute(
                    path: 'caixinhas',
                    name: 'savings_vaults',
                    builder: (context, state) => const SavingsVaultsPage(),
                  ),
                ],
              ),
              // Aliases para compatibilidade retroativa com context.push('/fechamento'), context.push('/compras') e context.push('/caixinhas')
              GoRoute(
                path: '/fechamento',
                redirect: (context, state) => '/casa/fechamento',
              ),
              GoRoute(
                path: '/compras',
                redirect: (context, state) => '/casa/compras',
              ),
              GoRoute(
                path: '/caixinhas',
                redirect: (context, state) => '/casa/caixinhas',
              ),
            ],
          ),
          // Aba 2: Pessoal (P2P)
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/pessoal',
                name: 'p2p',
                pageBuilder: (context, state) => const NoTransitionPage(
                  child: P2PPage(),
                ),
              ),
            ],
          ),
          // Aba 3: Agenda
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/agenda',
                name: 'calendar',
                pageBuilder: (context, state) => const NoTransitionPage(
                  child: CalendarPage(),
                ),
              ),
            ],
          ),
          // Aba 4: Relatórios
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/relatorios',
                name: 'reports',
                pageBuilder: (context, state) => const NoTransitionPage(
                  child: ReportsPage(),
                ),
              ),
            ],
          ),
          // Aba 5: Ajustes
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/ajustes',
                name: 'settings',
                pageBuilder: (context, state) => const NoTransitionPage(
                  child: SettingsPage(),
                ),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}
