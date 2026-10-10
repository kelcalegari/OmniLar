import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'core/di/service_locator.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_cubit.dart';
import 'features/auth/presentation/cubit/auth_cubit.dart';
import 'features/finance/presentation/cubit/finance_cubit.dart';
import 'features/p2p/presentation/cubit/p2p_cubit.dart';
import 'features/shopping/presentation/cubit/shopping_cubit.dart';
import 'features/calendar/presentation/cubit/calendar_cubit.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Inicializa formatação de datas em Português (Brasil)
  await initializeDateFormatting('pt_BR', null);

  // Inicializa Injeção de Dependências
  await initServiceLocator();

  runApp(const OmniLarApp());
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
      ],
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
          );
        },
      ),
    );
  }
}
