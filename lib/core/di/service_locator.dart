import '../../features/reconciliation/data/csv_mapping_store.dart';
import '../../features/reconciliation/data/import_ai_service.dart';
import '../../features/reconciliation/data/import_draft_store.dart';
import '../../features/reconciliation/data/mock_import_repository.dart';
import '../../features/reconciliation/data/supabase_import_repository.dart';
import '../../features/reconciliation/domain/repositories/import_repository.dart';
import '../../features/p2p/data/offline/p2p_loan_offline_codec.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get_it/get_it.dart';
import '../network/offline_queue.dart';
import '../network/offline_sync_service.dart';
import '../utils/uuid.dart';
import '../network/supabase_config.dart';
import '../security/biometric_auth_service.dart';
import '../services/ai_config_service.dart';
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
import '../../features/finance/data/repositories/member_settings_repositories.dart';
import '../../features/finance/domain/repositories/member_settings_repository.dart';
import '../../features/finance/domain/repositories/finance_repository.dart';
import '../../features/finance/domain/services/cycle_funding_estimator.dart';
import '../../features/finance/domain/services/receipt_attachment_service.dart';
import '../../features/finance/presentation/cubit/finance_cubit.dart';
import '../../features/admin/data/datasources/admin_datasource.dart';
import '../../features/admin/data/datasources/dynamic_admin_datasource.dart';
import '../../features/admin/data/datasources/mock_admin_datasource.dart';
import '../../features/admin/data/datasources/supabase_admin_datasource.dart';
import '../../features/admin/presentation/cubit/account_access_cubit.dart';
import '../../features/admin/presentation/cubit/admin_cubit.dart';
import '../../features/notifications/data/datasources/dynamic_notifications_datasource.dart';
import '../../features/notifications/data/datasources/mock_notifications_datasource.dart';
import '../../features/notifications/data/datasources/notifications_datasource.dart';
import '../../features/notifications/data/datasources/supabase_notifications_datasource.dart';
import '../../features/notifications/data/push/push_service.dart';
import '../../features/notifications/presentation/cubit/notifications_cubit.dart';

import '../../features/p2p/data/datasources/p2p_datasource.dart';
import '../domain/value_objects/money.dart';
import '../../features/p2p/data/datasources/mock_p2p_datasource.dart';
import '../../features/p2p/data/datasources/supabase_p2p_datasource.dart';
import '../../features/p2p/data/repositories/p2p_repository_impl.dart';
import '../../features/p2p/domain/repositories/p2p_repository.dart';
import '../../features/p2p/presentation/cubit/p2p_cubit.dart';

import '../../features/settlement/data/datasources/settlement_datasource.dart';
import '../../features/settlement/data/datasources/mock_settlement_datasource.dart';
import '../../features/settlement/data/datasources/supabase_settlement_datasource.dart';
import '../../features/settlement/data/repositories/settlement_repository_impl.dart';
import '../../features/settlement/domain/repositories/settlement_repository.dart';
import '../../features/settlement/presentation/cubit/settlement_cubit.dart';
import '../../features/reports/presentation/cubit/reports_cubit.dart';

import '../../features/shopping/data/datasources/shopping_datasource.dart';
import '../../features/shopping/data/datasources/mock_shopping_datasource.dart';
import '../../features/shopping/data/datasources/supabase_shopping_datasource.dart';
import '../../features/shopping/data/repositories/shopping_repository_impl.dart';
import '../../features/shopping/domain/repositories/shopping_repository.dart';
import '../../features/shopping/presentation/cubit/shopping_cubit.dart';

import '../../features/calendar/data/datasources/calendar_datasource.dart';
import '../../features/calendar/data/datasources/mock_calendar_datasource.dart';
import '../../features/calendar/data/datasources/supabase_calendar_datasource.dart';
import '../../features/calendar/data/repositories/calendar_repository_impl.dart';
import '../../features/calendar/domain/repositories/calendar_repository.dart';
import '../../features/calendar/presentation/cubit/calendar_cubit.dart';

import '../../features/assistant/domain/services/assistant_interpreter_service.dart';
import '../../features/assistant/presentation/cubit/assistant_cubit.dart';

import '../../features/projects/data/repositories/mock_projects_repository.dart';
import '../../features/projects/data/repositories/supabase_projects_repository.dart';
import '../../features/finance/data/datasources/dynamic_finance_datasource.dart';
import '../../features/p2p/data/datasources/dynamic_p2p_datasource.dart';
import '../../features/shopping/data/datasources/dynamic_shopping_datasource.dart';
import '../../features/calendar/data/datasources/dynamic_calendar_datasource.dart';
import '../../features/projects/data/repositories/dynamic_projects_repository.dart';
import '../../features/settlement/data/datasources/dynamic_settlement_datasource.dart';
import '../../features/projects/domain/repositories/projects_repository.dart';
import '../../features/projects/presentation/cubit/projects_cubit.dart';
import '../../features/capture/domain/services/capture_service.dart';
import '../../features/finance/data/offline/house_expense_offline_codec.dart';
import '../../features/shopping/data/offline/shopping_item_offline_codec.dart';
import '../../features/calendar/data/offline/calendar_offline_codec.dart';
import '../offline/offline_snapshot.dart';
import '../ai/ai_consent.dart';
import '../router/app_router.dart';

final sl = GetIt.instance;

Future<void> initServiceLocator() async {
  // Inicializa o Supabase Flutter se as credenciais estiverem configuradas
  await SupabaseConfig.initialize();

  // Core Infrastructure, Security & Theme
  sl.registerLazySingleton<FlutterSecureStorage>(() => const FlutterSecureStorage());
  sl.registerLazySingleton<BiometricAuthService>(() => BiometricAuthService());
  sl.registerLazySingleton<OfflineQueueManager>(() => OfflineQueueManager(sl<FlutterSecureStorage>()));
  sl.registerLazySingleton<AiConfigService>(() => AiConfigService(sl<FlutterSecureStorage>()));
  sl.registerLazySingleton<ThemeCubit>(() => ThemeCubit());

  // Restaura dados da fila offline de forma não-bloqueante
  try {
    await sl<OfflineQueueManager>().init();
  } catch (_) {}

  // Auth & House Feature (Fase 0: Fundação)
  sl.registerLazySingleton<AuthDataSource>(() {
    final client = SupabaseConfig.client;
    if (client != null) {
      return SupabaseAuthDataSource(client);
    }
    return MockAuthDataSource();
  });
  sl.registerLazySingleton<AuthRepository>(() => AuthRepositoryImpl(sl()));
  sl.registerLazySingleton<AuthCubit>(() => AuthCubit(
        sl(),
        onSignOut: () {
          try {
            if (sl.isRegistered<FinanceCubit>()) sl<FinanceCubit>().resetState();
            if (sl.isRegistered<ShoppingCubit>()) sl<ShoppingCubit>().resetState();
            if (sl.isRegistered<CalendarCubit>()) sl<CalendarCubit>().resetState();
            if (sl.isRegistered<P2PCubit>()) sl<P2PCubit>().resetState();
            if (sl.isRegistered<NotificationsCubit>()) sl<NotificationsCubit>().resetState();
          } catch (_) {}
        },
      ));

  // Fila offline: só vale para sessão real em uma casa (o modo demo grava em memória)
  sl.registerLazySingleton<OfflineSyncService>(() => OfflineSyncService(
        queue: sl<OfflineQueueManager>(),
        currentScope: () {
          final authRepo = sl<AuthRepository>();
          final userId = authRepo.currentUser?.id;
          final houseId = authRepo.currentHouse?.id;
          if (authRepo.isDemoMode || !isUuid(userId) || !isUuid(houseId)) return null;
          return '$userId|$houseId';
        },
      ));

  bool isDemoModeActive() {
    final authRepo = sl<AuthRepository>();
    if (authRepo.isDemoMode) return true;
    // Se o cliente Supabase não estiver autenticado com um usuário real, é modo local/demo
    if (SupabaseConfig.client?.auth.currentUser == null) return true;
    // Se o usuário está logado no Supabase, ele NÃO está no modo demo.
    return false;
  }

  // Finance Feature
  sl.registerLazySingleton<FinanceDataSource>(() {
    final client = SupabaseConfig.client;
    final mock = MockFinanceDataSource()
      ..houseLoansFundedIn = (cycle) async {
        // Só roda no modo demonstração, em que o P2P também é o de demonstração
        final loans = await sl<P2PDataSource>().getLoans();
        return Money(loans
            .where((loan) => loan.fundedFromCycle(cycle))
            .fold<int>(0, (acc, loan) => acc + loan.totalAmount.cents));
      };
    if (client != null) {
      final remote = SupabaseFinanceDataSource(
        client: client,
        getCurrentHouseId: () => sl<AuthRepository>().currentHouse?.id ?? '',
      );
      return DynamicFinanceDataSource(
        remote: remote,
        mock: mock,
        isDemoMode: isDemoModeActive,
      );
    }
    return mock;
  });
  sl.registerLazySingleton<FinanceRepository>(() => FinanceRepositoryImpl(sl(), sl<OfflineSyncService>()));
  // Ajustes de cada morador na casa (0095)
  sl.registerLazySingleton<MemberSettingsRepository>(() {
    final client = SupabaseConfig.client;
    final mock = InMemoryMemberSettingsRepository();
    if (client != null) {
      return DynamicMemberSettingsRepository(
        remote: SupabaseMemberSettingsRepository(
          client: client,
          getCurrentHouseId: () => sl<AuthRepository>().currentHouse?.id ?? '',
        ),
        mock: mock,
        isDemoMode: isDemoModeActive,
      );
    }
    return mock;
  });
  sl.registerLazySingleton<ReceiptAttachmentService>(
      () => ReceiptAttachmentService(client: SupabaseConfig.client));
  sl.registerLazySingleton<FinanceCubit>(() => FinanceCubit(
        sl(),
        const CycleFundingEstimator(),
        () => sl<AuthRepository>().currentHouse?.cycleStartDay,
        () => sl<AuthRepository>().currentHouse?.cycleSchedule,
        sl<MemberSettingsRepository>(),
      ));

  // P2P Feature
  sl.registerLazySingleton<P2PDataSource>(() {
    final client = SupabaseConfig.client;
    final mock = MockP2PDataSource()
      ..depositToVault = ((vaultId, memberId, amount, description) =>
          sl<FinanceDataSource>().depositToVault(
            vaultId: vaultId,
            memberId: memberId,
            amount: amount,
            description: description,
          ))
      ..withdrawFromVault = (vaultId, memberId, amount, description) =>
          sl<FinanceDataSource>().withdrawFromVault(
            vaultId: vaultId,
            memberId: memberId,
            amount: amount,
            description: description,
          );
    if (client != null) {
      final remote = SupabaseP2PDataSource(
        client: client,
        getCurrentHouseId: () => sl<AuthRepository>().currentHouse?.id ?? '',
      );
      return DynamicP2PDataSource(
        remote: remote,
        mock: mock,
        isDemoMode: isDemoModeActive,
      );
    }
    return mock;
  });
  sl.registerLazySingleton<P2PRepository>(() => P2PRepositoryImpl(sl(), sl<OfflineSyncService>()));
  sl.registerLazySingleton<P2PCubit>(() => P2PCubit(
        sl(),
        sl<AuthRepository>(),
        // Empréstimos e parcelas pagos em outro aparelho (migration 0061)
        () => sl<FinanceRepository>().watchHouseChanges(),
      ));

  // Settlement Feature (Motor de Compensação / Super Pix)
  sl.registerLazySingleton<SettlementDataSource>(() {
    final client = SupabaseConfig.client;
    final mock = MockSettlementDataSource(
      financeDataSource: sl(),
      p2pDataSource: sl(),
      getCurrentHouse: () => sl<AuthRepository>().currentHouse,
    );
    if (client != null) {
      final remote = SupabaseSettlementDataSource(
        client: client,
        financeDataSource: sl(),
        p2pDataSource: sl(),
        getCurrentHouseId: () => sl<AuthRepository>().currentHouse?.id ?? '',
        getCurrentHouse: () => sl<AuthRepository>().currentHouse,
      );
      return DynamicSettlementDataSource(
        remote: remote,
        mock: mock,
        isDemoMode: isDemoModeActive,
      );
    }
    return mock;
  });
  sl.registerLazySingleton<SettlementRepository>(() => SettlementRepositoryImpl(sl()));
  sl.registerFactory<SettlementCubit>(() => SettlementCubit(sl(), sl()));
  sl.registerFactory<ReportsCubit>(
    () => ReportsCubit(sl(), p2pRepository: sl(), financeRepository: sl()),
  );

  // Shopping Feature (Fase 4: Organização do Lar)
  sl.registerLazySingleton<ShoppingDataSource>(() {
    final client = SupabaseConfig.client;
    final mock = MockShoppingDataSource(
      financeRepository: sl(),
      p2pRepository: sl(),
    );
    if (client != null) {
      final remote = SupabaseShoppingDataSource(
        client: client,
        getCurrentHouseId: () => sl<AuthRepository>().currentHouse?.id ?? '',
        financeRepository: sl(),
        p2pRepository: sl(),
      );
      return DynamicShoppingDataSource(
        remote: remote,
        mock: mock,
        isDemoMode: isDemoModeActive,
      );
    }
    return mock;
  });
  sl.registerLazySingleton<ShoppingRepository>(() => ShoppingRepositoryImpl(sl(), sl<OfflineSyncService>()));
  sl.registerLazySingleton<ShoppingCubit>(() => ShoppingCubit(sl()));

  // Calendar & Tasks Feature (Fase 4: Agenda do Lar e Tarefas)
  sl.registerLazySingleton<CalendarDataSource>(() {
    final client = SupabaseConfig.client;
    final mock = MockCalendarDataSource();
    if (client != null) {
      final remote = SupabaseCalendarDataSource(
        client: client,
        getCurrentHouseId: () => sl<AuthRepository>().currentHouse?.id ?? '',
      );
      return DynamicCalendarDataSource(
        remote: remote,
        mock: mock,
        isDemoMode: isDemoModeActive,
      );
    }
    return mock;
  });
  sl.registerLazySingleton<CalendarRepository>(() => CalendarRepositoryImpl(sl(), sl<OfflineSyncService>()));
  sl.registerLazySingleton<CalendarCubit>(() => CalendarCubit(sl(), sl<AuthRepository>()));

  // Consentimento da IA: guardado no perfil; perguntado sobre a tela em uso
  AiConsent.isGiven = () {
    final auth = sl<AuthRepository>();
    final user = auth.currentUser;
    return auth.isDemoMode || user == null || !user.legalStatusKnown || user.hasAiConsent;
  };
  AiConsent.ask = () async {
    final context = AppRouter.rootNavigatorKey.currentContext;
    return context != null && context.mounted && await AiConsent.showDialogIn(context);
  };
  AiConsent.record = () => sl<AuthRepository>().setAiConsent(true);

  // Cópia local para abrir sem internet: por conta logada no Supabase
  OfflineSnapshot.instance = OfflineSnapshot(
    currentUserId: () => SupabaseConfig.client?.auth.currentUser?.id,
  );

  // Notificações (sino): quem grava é o banco; o app lê e marca como lida
  sl.registerLazySingleton<NotificationsDataSource>(() {
    final client = SupabaseConfig.client;
    final mock = MockNotificationsDataSource();
    if (client != null) {
      return DynamicNotificationsDataSource(
        remote: SupabaseNotificationsDataSource(
          client: client,
          getCurrentHouseId: () => sl<AuthRepository>().currentHouse?.id ?? '',
        ),
        mock: mock,
        isDemoMode: isDemoModeActive,
      );
    }
    return mock;
  });
  sl.registerLazySingleton<NotificationsCubit>(() => NotificationsCubit(sl(), sl<AuthRepository>()));

  // Status da conta e painel administrativo (migration 0068)
  sl.registerLazySingleton<AdminDataSource>(() {
    final client = SupabaseConfig.client;
    final mock = MockAdminDataSource(
      currentUserId: () => sl<AuthRepository>().currentUser?.id ?? 'member_carlos',
    );
    if (client != null) {
      return DynamicAdminDataSource(
        remote: SupabaseAdminDataSource(client: client),
        mock: mock,
        isDemoMode: isDemoModeActive,
      );
    }
    return mock;
  });
  sl.registerLazySingleton<AccountAccessCubit>(() => AccountAccessCubit(sl(), sl<AuthRepository>()));
  sl.registerFactory<AdminCubit>(() => AdminCubit(sl()));
  sl.registerLazySingleton<PushService>(() => PushService(
        client: SupabaseConfig.client,
        isDemoMode: isDemoModeActive,
      ));

  // Assistant Feature (Fase 7: Assistente de IA Determinístico)
  sl.registerLazySingleton<AssistantInterpreterService>(() => AssistantInterpreterService(
        financeRepository: sl(),
        p2pRepository: sl(),
        shoppingRepository: sl(),
        calendarRepository: sl(),
        aiConfigService: sl<AiConfigService>(),
        authRepository: sl<AuthRepository>(),
        supabaseClient: SupabaseConfig.client,
      ));
  sl.registerFactory<AssistantCubit>(() => AssistantCubit(interpreterService: sl()));
  // Projects & Events Feature (Viagens, Compra de Imóveis, Reformas e Investimentos)
  sl.registerLazySingleton<ProjectsRepository>(() {
    final client = SupabaseConfig.client;
    final mock = MockProjectsRepository();
    if (client != null) {
      final remote = SupabaseProjectsRepository(client);
      return DynamicProjectsRepository(
        remote: remote,
        mock: mock,
        isDemoMode: isDemoModeActive,
      );
    }
    return mock;
  });
  sl.registerFactory<ProjectsCubit>(() => ProjectsCubit(
        projectsRepository: sl(),
        financeRepository: sl(),
        currentHouseId: () {
          final auth = sl<AuthRepository>();
          return auth.isDemoMode ? null : auth.currentHouse?.id;
        },
        currentUserId: () {
          final auth = sl<AuthRepository>();
          return auth.isDemoMode ? null : auth.currentUser?.id;
        },
      ));

  // Reenvio da fila offline: cada ação volta pela mesma gravação que faria online
  sl<OfflineSyncService>()
    ..registerHandler(
      OfflineActionType.addExpense,
      (payload) => sl<FinanceDataSource>().addExpense(houseExpenseFromJson(payload)),
    )
    ..registerHandler(
      OfflineActionType.addShoppingItem,
      (payload) => sl<ShoppingDataSource>().addItem(shoppingItemFromJson(payload)),
    )
    ..registerHandler(
      OfflineActionType.addCalendarEvent,
      (payload) => sl<CalendarDataSource>().addEvent(calendarEventFromJson(payload)),
    )
    ..registerHandler(
      OfflineActionType.addTask,
      (payload) => sl<CalendarDataSource>().addTask(taskItemFromJson(payload)),
    )
    ..registerHandler(
      OfflineActionType.updateTask,
      (payload) => sl<CalendarDataSource>().updateTask(taskItemFromJson(payload)),
    )
    ..registerHandler(
      OfflineActionType.updateShoppingItem,
      (payload) => sl<ShoppingDataSource>().updateItem(shoppingItemFromJson(payload)),
    )
    ..registerHandler(
      OfflineActionType.setShoppingItemBought,
      (payload) => sl<ShoppingDataSource>().setItemBought(
        payload['id'] as String,
        bought: payload['bought'] as bool,
        at: DateTime.parse(payload['at'] as String),
      ),
    )
    ..registerHandler(
      OfflineActionType.setTaskCompleted,
      (payload) => sl<CalendarDataSource>().setTaskCompleted(
        taskId: payload['id'] as String,
        completed: payload['completed'] as bool,
        completedByMemberId: payload['completedBy'] as String,
        at: DateTime.parse(payload['at'] as String),
      ),
    )
    ..registerHandler(
      OfflineActionType.deleteShoppingItem,
      (payload) => sl<ShoppingDataSource>().deleteItem(payload['id'] as String),
    )
    ..registerHandler(
      OfflineActionType.deleteTask,
      (payload) => sl<CalendarDataSource>().deleteTask(payload['id'] as String),
    )
    ..registerHandler(
      OfflineActionType.createLoan,
      (payload) => sl<P2PDataSource>().createLoan(p2pLoanFromJson(payload)),
    );

  // Importação de fatura e extrato
  sl.registerLazySingleton<ImportRepository>(() {
    final client = SupabaseConfig.client;
    final mock = MockImportRepository(finance: sl(), p2p: sl());
    if (client != null) {
      return DynamicImportRepository(
        remote: SupabaseImportRepository(
          client: client,
          getCurrentHouseId: () => sl<AuthRepository>().currentHouse?.id ?? '',
        ),
        mock: mock,
        isDemoMode: isDemoModeActive,
      );
    }
    return mock;
  });

  sl.registerLazySingleton<CsvMappingStore>(() {
    final client = SupabaseConfig.client;
    return CsvMappingStore(
      sl<FlutterSecureStorage>(),
      client == null
          ? null
          : SupabaseCsvMappingRemote(
              client: client,
              getCurrentHouseId: () => sl<AuthRepository>().currentHouse?.id,
              isDemoMode: isDemoModeActive,
            ),
    );
  });
  sl.registerLazySingleton<ImportDraftStore>(() => ImportDraftStore(sl<FlutterSecureStorage>()));
  sl.registerLazySingleton<ImportAiService>(() => ImportAiService(
        getClient: () => SupabaseConfig.client,
        aiConfigService: sl(),
        getCurrentHouseId: () => sl<AuthRepository>().currentHouse?.id,
        isDemoMode: isDemoModeActive,
      ));

  // Capture Feature
  sl.registerLazySingleton<CaptureService>(() => CaptureService(
        aiConfigService: sl(),
        getCurrentHouseId: () => sl<AuthRepository>().currentHouse?.id,
      ));
}
