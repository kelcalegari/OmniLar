import 'package:get_it/get_it.dart';
import '../network/offline_queue.dart';
import '../network/supabase_config.dart';
import '../theme/theme_cubit.dart';
import '../../features/auth/data/datasources/auth_datasource.dart';
import '../../features/auth/data/datasources/mock_auth_datasource.dart';
import '../../features/auth/data/datasources/supabase_auth_datasource.dart';
import '../../features/auth/data/repositories/auth_repository_impl.dart';
import '../../features/auth/domain/repositories/auth_repository.dart';
import '../../features/auth/presentation/cubit/auth_cubit.dart';

import '../../features/finance/data/datasources/finance_datasource.dart';
import '../../features/finance/data/datasources/mock_finance_datasource.dart';
import '../../features/finance/data/datasources/supabase_finance_datasource.dart';
import '../../features/finance/data/repositories/finance_repository_impl.dart';
import '../../features/finance/domain/repositories/finance_repository.dart';
import '../../features/finance/presentation/cubit/finance_cubit.dart';

import '../../features/p2p/data/datasources/mock_p2p_datasource.dart';
import '../../features/p2p/data/repositories/p2p_repository_impl.dart';
import '../../features/p2p/domain/repositories/p2p_repository.dart';
import '../../features/p2p/presentation/cubit/p2p_cubit.dart';

import '../../features/settlement/data/datasources/mock_settlement_datasource.dart';
import '../../features/settlement/data/repositories/settlement_repository_impl.dart';
import '../../features/settlement/domain/repositories/settlement_repository.dart';
import '../../features/settlement/presentation/cubit/settlement_cubit.dart';

import '../../features/shopping/data/datasources/mock_shopping_datasource.dart';
import '../../features/shopping/data/repositories/shopping_repository_impl.dart';
import '../../features/shopping/domain/repositories/shopping_repository.dart';
import '../../features/shopping/presentation/cubit/shopping_cubit.dart';

import '../../features/calendar/data/datasources/mock_calendar_datasource.dart';
import '../../features/calendar/data/repositories/calendar_repository_impl.dart';
import '../../features/calendar/domain/repositories/calendar_repository.dart';
import '../../features/calendar/presentation/cubit/calendar_cubit.dart';

import '../../features/assistant/domain/services/assistant_interpreter_service.dart';

import '../../features/projects/data/repositories/mock_projects_repository.dart';
import '../../features/projects/domain/repositories/projects_repository.dart';
import '../../features/projects/presentation/cubit/projects_cubit.dart';

final sl = GetIt.instance;

Future<void> initServiceLocator() async {
  // Core Infrastructure & Theme
  sl.registerLazySingleton<OfflineQueueManager>(() => OfflineQueueManager());
  sl.registerLazySingleton<ThemeCubit>(() => ThemeCubit());

  // Auth & House Feature (Fase 0: Fundação)
  sl.registerLazySingleton<AuthDataSource>(() {
    final client = SupabaseConfig.client;
    if (client != null) {
      return SupabaseAuthDataSource(client);
    }
    return MockAuthDataSource();
  });
  sl.registerLazySingleton<AuthRepository>(() => AuthRepositoryImpl(sl()));
  sl.registerLazySingleton<AuthCubit>(() => AuthCubit(sl()));

  // Finance Feature
  sl.registerLazySingleton<FinanceDataSource>(() {
    final client = SupabaseConfig.client;
    if (client != null) {
      return SupabaseFinanceDataSource(
        client: client,
        getCurrentHouseId: () => sl<AuthRepository>().currentHouse?.id ?? 'house_nossa_casa',
      );
    }
    return MockFinanceDataSource();
  });
  sl.registerLazySingleton<FinanceRepository>(() => FinanceRepositoryImpl(sl()));
  sl.registerLazySingleton<FinanceCubit>(() => FinanceCubit(sl()));

  // P2P Feature
  sl.registerLazySingleton<MockP2PDataSource>(() => MockP2PDataSource());
  sl.registerLazySingleton<P2PRepository>(() => P2PRepositoryImpl(sl()));
  sl.registerLazySingleton<P2PCubit>(() => P2PCubit(sl()));

  // Settlement Feature (Motor de Compensação / Super Pix)
  sl.registerLazySingleton<MockSettlementDataSource>(() => MockSettlementDataSource(
        financeDataSource: sl(),
        p2pDataSource: sl(),
      ));
  sl.registerLazySingleton<SettlementRepository>(() => SettlementRepositoryImpl(sl()));
  sl.registerFactory<SettlementCubit>(() => SettlementCubit(sl()));

  // Shopping Feature (Fase 4: Organização do Lar)
  sl.registerLazySingleton<MockShoppingDataSource>(() => MockShoppingDataSource(
        financeRepository: sl(),
        p2pRepository: sl(),
      ));
  sl.registerLazySingleton<ShoppingRepository>(() => ShoppingRepositoryImpl(sl()));
  sl.registerLazySingleton<ShoppingCubit>(() => ShoppingCubit(sl()));

  // Calendar & Tasks Feature (Fase 4: Agenda do Lar e Tarefas)
  sl.registerLazySingleton<MockCalendarDataSource>(() => MockCalendarDataSource());
  sl.registerLazySingleton<CalendarRepository>(() => CalendarRepositoryImpl(sl()));
  sl.registerLazySingleton<CalendarCubit>(() => CalendarCubit(sl()));

  // Assistant Feature (Fase 7: Assistente de IA Determinístico)
  sl.registerLazySingleton<AssistantInterpreterService>(() => AssistantInterpreterService(
        financeRepository: sl(),
        p2pRepository: sl(),
        shoppingRepository: sl(),
        calendarRepository: sl(),
      ));
  // Projects & Events Feature (Viagens, Compra de Imóveis, Reformas e Investimentos)
  sl.registerLazySingleton<ProjectsRepository>(() => MockProjectsRepository());
  sl.registerFactory<ProjectsCubit>(() => ProjectsCubit(
        projectsRepository: sl(),
        financeRepository: sl(),
      ));
}
