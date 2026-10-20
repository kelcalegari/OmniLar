import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mocktail/mocktail.dart';
import 'package:omni_lar/core/di/service_locator.dart';
import 'package:omni_lar/core/widgets/house_switcher_sheet.dart';
import 'package:omni_lar/features/admin/data/datasources/admin_datasource.dart';
import 'package:omni_lar/features/admin/domain/entities/account_access.dart';
import 'package:omni_lar/features/admin/presentation/cubit/account_access_cubit.dart';
import 'package:omni_lar/features/auth/domain/entities/house.dart';
import 'package:omni_lar/features/auth/domain/entities/user_profile.dart';
import 'package:omni_lar/features/auth/domain/repositories/auth_repository.dart';
import 'package:omni_lar/features/auth/presentation/cubit/auth_cubit.dart';

class MockAuthRepository extends Mock implements AuthRepository {}
class MockAdminDataSource extends Mock implements AdminDataSource {}

void main() {
  setUp(() {
    if (sl.isRegistered<AccountAccessCubit>()) {
      sl.unregister<AccountAccessCubit>();
    }
  });

  tearDown(() {
    if (sl.isRegistered<AccountAccessCubit>()) {
      sl.unregister<AccountAccessCubit>();
    }
  });

  testWidgets('HouseSwitcherSheet exibe casas do usuário e destaca casa ativa', (tester) async {
    final mockAuthRepo = MockAuthRepository();
    final mockAdmin = MockAdminDataSource();
    const user = UserProfile(id: 'u1', fullName: 'Carlos', email: 'carlos@teste.com');
    const h1 = House(id: 'h1', name: 'Casa Principal', createdBy: 'u1');
    const h2 = House(id: 'h2', name: 'Casa de Praia', createdBy: 'u2');

    when(() => mockAuthRepo.currentUser).thenReturn(user);
    when(() => mockAuthRepo.currentHouse).thenReturn(h1);
    when(() => mockAuthRepo.isRestoringSession).thenReturn(false);
    when(() => mockAuthRepo.isDemoMode).thenReturn(false);
    when(() => mockAuthRepo.authStateChanges).thenAnswer((_) => Stream.value(user));
    when(() => mockAuthRepo.houseChanges).thenAnswer((_) => Stream.value(h1));
    when(() => mockAuthRepo.getUserHouses()).thenAnswer((_) async => [h1, h2]);
    when(() => mockAuthRepo.selectHouse('h2')).thenAnswer((_) async {});

    when(() => mockAdmin.getMyAccess()).thenAnswer(
      (_) async => const AccountAccess(status: AccountStatus.active, plan: AccountPlan.free),
    );
    when(() => mockAdmin.watchMyAccess()).thenAnswer((_) => const Stream.empty());

    sl.registerLazySingleton<AccountAccessCubit>(() => AccountAccessCubit(mockAdmin, mockAuthRepo));

    final authCubit = AuthCubit(mockAuthRepo);
    await authCubit.loadUserHouses();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlocProvider<AuthCubit>.value(
            value: authCubit,
            child: const HouseSwitcherSheet(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Minhas Casas'), findsOneWidget);
    expect(find.text('Casa Principal'), findsOneWidget);
    expect(find.text('Casa de Praia'), findsOneWidget);
    expect(find.text('• Ativa agora'), findsOneWidget);
    expect(find.text('Dono'), findsOneWidget);
    expect(find.text('Morador'), findsOneWidget);

    // Toca na Casa de Praia para alternar
    await tester.tap(find.text('Casa de Praia'));
    await tester.pumpAndSettle();

    verify(() => mockAuthRepo.selectHouse('h2')).called(1);

    authCubit.close();
  });

  testWidgets('Usuário Free que já possui 1 casa como dono vê diálogo do Premium ao tocar em criar nova casa', (tester) async {
    final mockAuthRepo = MockAuthRepository();
    final mockAdmin = MockAdminDataSource();
    const user = UserProfile(id: 'u1', fullName: 'Carlos', email: 'carlos@teste.com');
    const h1 = House(id: 'h1', name: 'Casa Principal', createdBy: 'u1');

    when(() => mockAuthRepo.currentUser).thenReturn(user);
    when(() => mockAuthRepo.currentHouse).thenReturn(h1);
    when(() => mockAuthRepo.isRestoringSession).thenReturn(false);
    when(() => mockAuthRepo.isDemoMode).thenReturn(false);
    when(() => mockAuthRepo.authStateChanges).thenAnswer((_) => Stream.value(user));
    when(() => mockAuthRepo.houseChanges).thenAnswer((_) => Stream.value(h1));
    when(() => mockAuthRepo.getUserHouses()).thenAnswer((_) async => [h1]);

    when(() => mockAdmin.getMyAccess()).thenAnswer(
      (_) async => const AccountAccess(status: AccountStatus.active, plan: AccountPlan.free),
    );
    when(() => mockAdmin.watchMyAccess()).thenAnswer((_) => const Stream.empty());

    sl.registerLazySingleton<AccountAccessCubit>(() => AccountAccessCubit(mockAdmin, mockAuthRepo));

    final authCubit = AuthCubit(mockAuthRepo);
    await authCubit.loadUserHouses();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlocProvider<AuthCubit>.value(
            value: authCubit,
            child: const HouseSwitcherSheet(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Criar nova casa'), findsOneWidget);
    await tester.tap(find.text('Criar nova casa'));
    await tester.pumpAndSettle();

    // Diálogo informativo e amigável do Premium deve abrir
    expect(find.text('Múltiplas Casas no Omni Lar'), findsOneWidget);
    expect(find.text('Conhecer o Premium'), findsOneWidget);
    expect(find.text('Agora não'), findsOneWidget);

    authCubit.close();
  });
}
