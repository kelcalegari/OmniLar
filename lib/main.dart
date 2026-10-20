import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'core/config/firebase_config.dart';
import 'core/di/service_locator.dart';
import 'core/logging/omni_bloc_observer.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_cubit.dart';
import 'features/auth/presentation/cubit/auth_cubit.dart';
import 'features/auth/presentation/cubit/auth_state.dart';
import 'features/finance/presentation/cubit/finance_cubit.dart';
import 'features/p2p/presentation/cubit/p2p_cubit.dart';
import 'features/shopping/presentation/cubit/shopping_cubit.dart';
import 'features/calendar/presentation/cubit/calendar_cubit.dart';
import 'features/auth/domain/repositories/auth_repository.dart';
import 'features/notifications/data/push/push_service.dart';
import 'features/notifications/presentation/cubit/notifications_cubit.dart';
import 'core/offline/offline_banner.dart';
import 'core/widgets/search_shortcut.dart';

Future<void> _bootstrapApp() async {
  // Configura URLs limpas (sem #) na Web
  usePathUrlStrategy();

  // Inicializa formatação de datas em Português (Brasil)
  await initializeDateFormatting('pt_BR', null);

  // Firebase, só para o push das notificações
  await FirebaseConfig.initialize();

  // Inicializa Injeção de Dependências
  await initServiceLocator();

  // Push: registra o aparelho de quem já permitiu; toque no aviso abre o item
  final push = sl<PushService>();
  push.onOpenDeeplink = AppRouter.router.go;
  final authRepo = sl<AuthRepository>();
  push.start(authRepo.authStateChanges);

  // Vincula o usuário e a casa ao escopo do Sentry (anonimizando por ID para LGPD)
  authRepo.authStateChanges.listen((user) {
    if (user != null) {
      Sentry.configureScope((scope) => scope.setUser(SentryUser(id: user.id)));
    } else {
      Sentry.configureScope((scope) {
        scope.setUser(null);
        scope.removeTag('house_id');
      });
    }
  });
  authRepo.houseChanges.listen((house) {
    Sentry.configureScope((scope) {
      if (house != null) {
        scope.setTag('house_id', house.id);
      } else {
        scope.removeTag('house_id');
      }
    });
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Observador de cubits/blocs para capturar exceções não tratadas
  Bloc.observer = OmniBlocObserver();

  const defaultSentryDsn = 'https://12b32d1db8bdf0ed9578cdd02e18d9e4@o4512285777657856.ingest.us.sentry.io/4512285825433600';
  const envSentryDsn = String.fromEnvironment('SENTRY_DSN');
  final sentryDsn = envSentryDsn.isNotEmpty ? envSentryDsn : defaultSentryDsn;

  if (sentryDsn.isEmpty) {
    // Ambiente local ou sem DSN: executa sem enviar telemetria para a nuvem
    await _bootstrapApp();
    runApp(const OmniLarApp());
  } else {
    // Produção: envelope seguro do Sentry com sanitização e LGPD
    await SentryFlutter.init(
      (options) {
        options.dsn = sentryDsn;
        options.tracesSampleRate = 0.2;
        options.attachScreenshot = false; // Não capturar tela para proteger dados financeiros
        options.sendDefaultPii = false;   // Não enviar IP ou dados pessoais brutos
        options.environment = kReleaseMode ? 'production' : 'development';
        options.beforeSend = (event, hint) {
          // Remove cabeçalhos de autorização que possam conter tokens JWT
          event.request?.headers.remove('Authorization');
          event.request?.headers.remove('apikey');
          return event;
        };
      },
      appRunner: () async {
        await _bootstrapApp();
        runApp(const OmniLarApp());
      },
    );
  }
}

class OmniLarApp extends StatelessWidget {
  const OmniLarApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<ThemeCubit>(
          create: (_) => sl<ThemeCubit>(),
        ),
        BlocProvider<AuthCubit>(
          create: (_) => sl<AuthCubit>(),
        ),
        BlocProvider<FinanceCubit>(
          create: (_) => sl<FinanceCubit>()..loadCycleData(),
        ),
        BlocProvider<P2PCubit>(
          create: (_) => sl<P2PCubit>()..loadLoans(),
        ),
        BlocProvider<ShoppingCubit>(
          create: (_) => sl<ShoppingCubit>()..loadShoppingData(),
        ),
        BlocProvider<CalendarCubit>(
          create: (_) => sl<CalendarCubit>()..loadCalendarData(),
        ),
        BlocProvider<NotificationsCubit>(
          create: (_) => sl<NotificationsCubit>()..load(),
        ),
      ],
      child: BlocListener<AuthCubit, AuthState>(
        listenWhen: (previous, current) =>
            previous.house?.id != current.house?.id && current.house != null,
        listener: (context, state) {
          context.read<FinanceCubit>().resetState();
          context.read<FinanceCubit>().loadCycleData();
          context.read<P2PCubit>().resetState();
          context.read<P2PCubit>().loadLoans();
          context.read<ShoppingCubit>().resetState();
          context.read<ShoppingCubit>().loadShoppingData();
          context.read<CalendarCubit>().resetState();
          context.read<CalendarCubit>().loadCalendarData();
          context.read<NotificationsCubit>().resetState();
          context.read<NotificationsCubit>().load();
        },
        child: BlocBuilder<ThemeCubit, ThemeMode>(
          builder: (context, themeMode) {
            return MaterialApp.router(
              title: 'Omni Lar',
              debugShowCheckedModeBanner: false,
              theme: AppTheme.lightTheme,
              darkTheme: AppTheme.darkTheme,
              themeMode: themeMode,
              localizationsDelegates: const [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: const [
                Locale('pt', 'BR'),
              ],
              locale: const Locale('pt', 'BR'),
              routerConfig: AppRouter.router,
              builder: (context, child) => SearchShortcut.listener(
                child: OfflineBanner(child: child ?? const SizedBox.shrink()),
              ),
            );
          },
        ),
      ),
    );
  }
}
