import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/di/service_locator.dart';
import 'package:omni_lar/features/auth/domain/repositories/auth_repository.dart';
import 'package:omni_lar/features/calendar/data/datasources/calendar_datasource.dart';
import 'package:omni_lar/features/calendar/data/datasources/mock_calendar_datasource.dart';
import 'package:omni_lar/features/calendar/domain/repositories/calendar_repository.dart';
import 'package:omni_lar/features/finance/data/datasources/finance_datasource.dart';
import 'package:omni_lar/features/finance/data/datasources/mock_finance_datasource.dart';
import 'package:omni_lar/features/finance/domain/repositories/finance_repository.dart';
import 'package:omni_lar/features/p2p/data/datasources/mock_p2p_datasource.dart';
import 'package:omni_lar/features/p2p/data/datasources/p2p_datasource.dart';
import 'package:omni_lar/features/p2p/domain/repositories/p2p_repository.dart';
import 'package:omni_lar/features/projects/data/repositories/mock_projects_repository.dart';
import 'package:omni_lar/features/projects/domain/repositories/projects_repository.dart';
import 'package:omni_lar/features/settlement/domain/repositories/settlement_repository.dart';
import 'package:omni_lar/features/shopping/data/datasources/mock_shopping_datasource.dart';
import 'package:omni_lar/features/shopping/data/datasources/shopping_datasource.dart';
import 'package:omni_lar/features/shopping/domain/repositories/shopping_repository.dart';

void main() {
  group('ServiceLocator DI Architecture & Fallback', () {
    setUpAll(() async {
      await initServiceLocator();
    });

    test('Auth, Finance, P2P, Shopping, Calendar e Projects estão devidamente registrados', () {
      expect(sl.isRegistered<AuthRepository>(), isTrue);
      expect(sl.isRegistered<FinanceRepository>(), isTrue);
      expect(sl.isRegistered<P2PRepository>(), isTrue);
      expect(sl.isRegistered<ShoppingRepository>(), isTrue);
      expect(sl.isRegistered<CalendarRepository>(), isTrue);
      expect(sl.isRegistered<SettlementRepository>(), isTrue);
      expect(sl.isRegistered<ProjectsRepository>(), isTrue);
    });

    test('DataSources resolvem para as instâncias de mock em ambiente offline/demo', () {
      expect(sl<FinanceDataSource>(), isA<MockFinanceDataSource>());
      expect(sl<P2PDataSource>(), isA<MockP2PDataSource>());
      expect(sl<ShoppingDataSource>(), isA<MockShoppingDataSource>());
      expect(sl<CalendarDataSource>(), isA<MockCalendarDataSource>());
      expect(sl<ProjectsRepository>(), isA<MockProjectsRepository>());
    });
  });
}
