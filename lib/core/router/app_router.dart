import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../di/service_locator.dart';
import '../widgets/desktop_shortcuts_wrapper.dart';
import '../widgets/scaffold_with_nav_bar.dart';
import '../../features/auth/presentation/cubit/auth_cubit.dart';
import '../../features/auth/presentation/cubit/auth_state.dart';
import '../../features/auth/presentation/pages/login_page.dart';
import '../../features/auth/presentation/pages/house_onboarding_page.dart';
import '../../features/splash/presentation/pages/splash_page.dart';
import '../../features/home/presentation/pages/home_page.dart';
import '../../features/home/presentation/pages/web_landing_page.dart';
import '../../features/p2p/presentation/pages/p2p_page.dart';
import '../../features/calendar/presentation/pages/calendar_page.dart';
import '../../features/reports/presentation/pages/reports_page.dart';
import '../../features/settings/presentation/pages/settings_page.dart';
import '../../features/settlement/presentation/pages/settlement_hub_page.dart';
import '../../features/finance/presentation/pages/savings_vaults_page.dart';
import '../../features/projects/presentation/cubit/projects_cubit.dart';
import '../../features/projects/presentation/pages/projects_hub_page.dart';
import '../../features/routine/presentation/pages/tasks_and_shopping_page.dart';

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

class AppRouter {
  static final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

  static final GoRouter router = GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: kIsWeb ? '/landing' : '/splash',
    refreshListenable: GoRouterRefreshStream(sl<AuthCubit>().stream),
    redirect: (context, state) {
      final authState = sl<AuthCubit>().state;
      final location = state.uri.path;
      final isSplash = location == '/splash';
      final isLanding = location == '/landing' || location == '/';
      final isLoggingIn = location == '/login';
      final isOnboarding = location == '/onboarding/house';

      // 0. Enquanto estiver na rota de Splash, deixa a SplashPage coordenar o warm-up suave
      if (isSplash) {
        return null;
      }

      // 1. Enquanto o AuthCubit estiver em inicialização (fora do Splash)
      if (authState.status == AuthStatus.initial) {
        if (kIsWeb) return isLanding ? null : '/landing';
        return '/splash';
      }

      // 2. Não autenticado -> na Web vai para a Landing Page (vitrine com Demo), no mobile vai para /login
      if (authState.status == AuthStatus.unauthenticated || !authState.isAuthenticated) {
        if (kIsWeb) {
          if (isLanding || isLoggingIn) return null;
          return '/landing';
        }
        if (isLanding) return '/landing';
        return isLoggingIn ? null : '/login';
      }

      // 3. Autenticado mas sem casa -> vai para /onboarding/house
      if (authState.isAuthenticated && !authState.hasHouse) {
        return isOnboarding ? null : '/onboarding/house';
      }

      // 4. Autenticado com casa ativa -> se estiver em rotas de entrada (login, onboarding ou landing no mobile), vai para /casa
      if (authState.isAuthenticated && authState.hasHouse) {
        if (isLoggingIn || isOnboarding || (isLanding && !kIsWeb)) {
          return '/casa';
        }
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/',
        redirect: (context, state) => kIsWeb ? '/landing' : '/splash',
      ),
      GoRoute(
        path: '/landing',
        name: 'landing',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const WebLandingPage(),
      ),
      GoRoute(
        path: '/splash',
        name: 'splash',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const SplashPage(),
      ),
      GoRoute(
        path: '/login',
        name: 'login',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const LoginPage(),
      ),
      GoRoute(
        path: '/onboarding/house',
        name: 'house_onboarding',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const HouseOnboardingPage(),
      ),
      // Shell com as 6 Abas Principais
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return DesktopShortcutsWrapper(
            child: ScaffoldWithNavBar(navigationShell: navigationShell),
          );
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
                    redirect: (context, state) => '/tarefas-compras?tab=compras',
                  ),
                  GoRoute(
                    path: 'caixinhas',
                    name: 'savings_vaults',
                    builder: (context, state) => const SavingsVaultsPage(),
                  ),
                  GoRoute(
                    path: 'projetos',
                    name: 'projects_hub',
                    builder: (context, state) => BlocProvider(
                      create: (_) => sl<ProjectsCubit>(),
                      child: const ProjectsHubPage(),
                    ),
                  ),
                ],
              ),
              // Aliases para compatibilidade retroativa
              GoRoute(
                path: '/fechamento',
                redirect: (context, state) => '/casa/fechamento',
              ),
              GoRoute(
                path: '/caixinhas',
                redirect: (context, state) => '/casa/caixinhas',
              ),
              GoRoute(
                path: '/projetos',
                redirect: (context, state) => '/casa/projetos',
              ),
            ],
          ),
          // Aba 2: Tarefas & Compras da Casa
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/tarefas-compras',
                name: 'tasks_and_shopping',
                pageBuilder: (context, state) {
                  final tabStr = state.uri.queryParameters['tab'];
                  final initialTab = tabStr == 'compras' ? 1 : 0;
                  return NoTransitionPage(
                    child: TasksAndShoppingPage(initialTabIndex: initialTab),
                  );
                },
              ),
              GoRoute(
                path: '/tarefas',
                redirect: (context, state) => '/tarefas-compras?tab=tarefas',
              ),
              GoRoute(
                path: '/compras',
                redirect: (context, state) => '/tarefas-compras?tab=compras',
              ),
            ],
          ),
          // Aba 3: Agenda (Compromissos)
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
          // Aba 4: Pessoal (P2P)
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
          // Aba 5: Relatórios
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
          // Aba 6: Ajustes
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
