import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../di/service_locator.dart';
import '../utils/app_download.dart';
import '../widgets/desktop_shortcuts_wrapper.dart';
import '../widgets/scaffold_with_nav_bar.dart';
import '../../features/auth/domain/repositories/auth_repository.dart';
import '../../features/auth/presentation/cubit/auth_cubit.dart';
import '../../features/auth/presentation/cubit/auth_state.dart';
import '../../features/auth/presentation/pages/login_page.dart';
import '../../features/auth/presentation/pages/confirm_email_page.dart';
import '../../features/auth/presentation/pages/reset_password_page.dart';
import '../../features/auth/presentation/pages/house_onboarding_page.dart';
import '../../features/admin/presentation/cubit/account_access_cubit.dart';
import '../../features/admin/presentation/pages/account_pending_page.dart';
import '../../features/admin/presentation/pages/admin_page.dart';
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
import '../../features/reconciliation/presentation/pages/import_page.dart';
import '../../features/notifications/presentation/pages/notifications_page.dart';
import '../../features/legal/legal_page.dart';
import '../../features/legal/legal_texts.dart';
import '../../features/legal/terms_acceptance_page.dart';

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

  /// Navegador de cima, para diálogos pedidos fora de uma tela (consentimento da IA).
  static GlobalKey<NavigatorState> get rootNavigatorKey => _rootNavigatorKey;

  static final GoRouter router = GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: kIsWeb ? '/landing' : '/splash',
    refreshListenable: Listenable.merge([
      GoRouterRefreshStream(sl<AuthCubit>().stream),
      // Conta aprovada, recusada ou suspensa muda a rota na hora
      GoRouterRefreshStream(sl<AccountAccessCubit>().stream),
    ]),
    redirect: (context, state) {
      final authState = sl<AuthCubit>().state;
      final location = state.uri.path;
      final isSplash = location == '/splash';
      final isLanding = location == '/landing' || location == '/';
      // Inclui as telas filhas do login (confirmação de e-mail)
      final isLoggingIn = location == '/login' || location.startsWith('/login/');
      final isConfirmingEmail = location == '/login/confirmar-email';
      final isOnboarding = location == '/onboarding/house';
      final isAccountPending = location == '/conta/em-analise';
      final isAdmin = location == '/admin';
      final isLegalPage = location == '/termos' || location == '/privacidade';
      final isTermsGate = location == '/termos/aceite';

      // Termos e Política: páginas públicas, abertas com ou sem login
      if (isLegalPage) return null;

      // 0. Enquanto estiver na rota de Splash, deixa a SplashPage coordenar o warm-up suave
      if (isSplash) {
        return null;
      }

      // 1. Enquanto o AuthCubit estiver em inicialização (fora do Splash)
      if (authState.status == AuthStatus.initial) {
        if (kIsWeb) {
          // Recarregou a página com sessão salva: aguarda no Splash e volta para onde estava
          if (sl<AuthRepository>().isRestoringSession) {
            return isLanding
                ? '/splash'
                : Uri(path: '/splash', queryParameters: {'from': state.uri.toString()}).toString();
          }
          return isLanding ? null : '/landing';
        }
        return '/splash';
      }

      // 2. Não autenticado -> na Web vai para a Landing Page (vitrine com Demo), no mobile vai para /login
      if (authState.status == AuthStatus.unauthenticated || !authState.isAuthenticated) {
        // 2.0. Cadastro esperando o código do e-mail
        if (authState.isAwaitingEmailConfirmation) {
          return isConfirmingEmail ? null : '/login/confirmar-email';
        }
        if (isConfirmingEmail) return '/login';
        if (kIsWeb) {
          if (isLanding || isLoggingIn) return null;
          return '/landing';
        }
        if (isLanding) return '/landing';
        return isLoggingIn ? null : '/login';
      }

      // 2.1. Conta em análise, recusada ou suspensa -> tela de espera (migration 0068)
      final access = sl<AccountAccessCubit>().state;
      if (access.isBlocked) {
        return isAccountPending ? null : '/conta/em-analise';
      }
      if (isAccountPending) {
        return authState.hasHouse ? '/casa' : '/onboarding/house';
      }

      // 2.15. Falta aceitar a versão atual dos Termos e da Política (migration 0085)
      final needsTerms = authState.user?.needsTermsAcceptance(kLegalVersion) ?? false;
      if (needsTerms && !sl<AuthRepository>().isDemoMode) {
        return isTermsGate ? null : '/termos/aceite';
      }
      if (isTermsGate) {
        return authState.hasHouse ? '/casa' : '/onboarding/house';
      }

      // 2.2. Painel administrativo só para quem administra o app
      if (isAdmin) {
        return access.isAdmin ? null : '/casa';
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
        builder: (context, state) => SplashPage(returnTo: state.uri.queryParameters['from']),
      ),
      GoRoute(
        path: '/apk',
        name: 'apk-download',
        parentNavigatorKey: _rootNavigatorKey,
        redirect: (context, state) {
          AppDownloadConfig.downloadApk();
          return '/login';
        },
      ),
      GoRoute(
        path: '/download',
        name: 'app-download',
        parentNavigatorKey: _rootNavigatorKey,
        redirect: (context, state) {
          AppDownloadConfig.downloadApk();
          return '/login';
        },
      ),
      GoRoute(
        path: '/login',
        name: 'login',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const LoginPage(),
      ),
      GoRoute(
        path: '/login/confirmar-email',
        name: 'login-confirmar-email',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const ConfirmEmailPage(),
      ),
      GoRoute(
        path: '/login/recuperar-senha',
        name: 'login-recuperar-senha',
        parentNavigatorKey: _rootNavigatorKey,
        // O e-mail vai por `extra`, não pela URL
        builder: (context, state) =>
            ResetPasswordPage(initialEmail: state.extra as String?),
      ),
      GoRoute(
        path: '/termos',
        name: 'termos',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const LegalPage(document: termsOfUse),
      ),
      GoRoute(
        path: '/privacidade',
        name: 'privacidade',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const LegalPage(document: privacyPolicy),
      ),
      GoRoute(
        path: '/termos/aceite',
        name: 'termos-aceite',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const TermsAcceptancePage(),
      ),
      GoRoute(
        path: '/conta/em-analise',
        name: 'account_pending',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const AccountPendingPage(),
      ),
      GoRoute(
        path: '/admin',
        name: 'admin',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => AdminPage(initialTab: state.uri.queryParameters['aba']),
      ),
      GoRoute(
        path: '/onboarding/house',
        name: 'house_onboarding',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const HouseOnboardingPage(),
      ),
      GoRoute(
        path: '/notificacoes',
        name: 'notifications',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const NotificationsPage(),
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
                    // ?ciclo=AAAA-MM-DD abre o fechamento daquele ciclo (notificações)
                    builder: (context, state) => SettlementHubPage(
                      initialCycleDate: DateTime.tryParse(state.uri.queryParameters['ciclo'] ?? ''),
                    ),
                  ),
                  GoRoute(
                    path: 'compras',
                    redirect: (context, state) => '/tarefas-compras?tab=compras',
                  ),
                  GoRoute(
                    path: 'caixinhas',
                    name: 'savings_vaults',
                    builder: (context, state) => SavingsVaultsPage(
                      openVaultId: state.uri.queryParameters['caixinha'],
                    ),
                  ),
                  GoRoute(
                    path: 'importar',
                    name: 'import',
                    builder: (context, state) => ImportPage(
                      initialSourceId: state.uri.queryParameters['origem'],
                    ),
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
                redirect: (context, state) => state.uri.replace(path: '/casa/fechamento').toString(),
              ),
              GoRoute(
                path: '/caixinhas',
                redirect: (context, state) => '/casa/caixinhas',
              ),
              // Deeplink das notificações: abre o histórico da caixinha
              GoRoute(
                path: '/caixinhas/:id',
                redirect: (context, state) =>
                    Uri(path: '/casa/caixinhas', queryParameters: {'caixinha': state.pathParameters['id']}).toString(),
              ),
              GoRoute(
                path: '/importar',
                redirect: (context, state) => state.uri.replace(path: '/casa/importar').toString(),
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
              // Deeplink das notificações: abre a aba de tarefas
              GoRoute(
                path: '/tarefas/:id',
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
                pageBuilder: (context, state) => NoTransitionPage(
                  child: CalendarPage(openEventId: state.uri.queryParameters['evento']),
                ),
              ),
              // Deeplink das notificações: abre o evento
              GoRoute(
                path: '/agenda/evento/:id',
                redirect: (context, state) =>
                    Uri(path: '/agenda', queryParameters: {'evento': state.pathParameters['id']}).toString(),
              ),
            ],
          ),
          // Aba 4: Pessoal (P2P)
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/pessoal',
                name: 'p2p',
                pageBuilder: (context, state) => NoTransitionPage(
                  child: P2PPage(openLoanId: state.uri.queryParameters['emprestimo']),
                ),
              ),
              // Deeplink das notificações: abre o empréstimo
              GoRoute(
                path: '/pessoal/emprestimo/:id',
                redirect: (context, state) =>
                    Uri(path: '/pessoal', queryParameters: {'emprestimo': state.pathParameters['id']}).toString(),
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
