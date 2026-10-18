import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mocktail/mocktail.dart';
import 'package:omni_lar/features/auth/domain/entities/house.dart';
import 'package:omni_lar/features/auth/domain/entities/user_profile.dart';
import 'package:omni_lar/features/auth/domain/repositories/auth_repository.dart';
import 'package:omni_lar/features/auth/presentation/cubit/auth_cubit.dart';
import 'package:omni_lar/features/auth/presentation/pages/house_onboarding_page.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

void main() {
  MockAuthRepository buildRepo() {
    final mockAuthRepo = MockAuthRepository();
    when(() => mockAuthRepo.currentUser).thenReturn(
      const UserProfile(id: 'user_1', fullName: 'Kelvynn Silva', email: 'kelvynn@teste.com'),
    );
    when(() => mockAuthRepo.currentHouse).thenReturn(null);
    when(() => mockAuthRepo.isRestoringSession).thenReturn(false);
    when(() => mockAuthRepo.authStateChanges).thenAnswer((_) => const Stream.empty());
    when(() => mockAuthRepo.houseChanges).thenAnswer((_) => const Stream.empty());
    when(() => mockAuthRepo.getUserHouses()).thenAnswer((_) async => []);
    return mockAuthRepo;
  }

  testWidgets('Passo opcional do saldo inicial: fechado por padrão; preenchido, leva os valores à criação da casa', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final mockAuthRepo = buildRepo();
    when(
      () => mockAuthRepo.createHouse(
        name: any(named: 'name'),
        cycleStartDay: any(named: 'cycleStartDay'),
        initialReserveCents: any(named: 'initialReserveCents'),
        initialCashCents: any(named: 'initialCashCents'),
      ),
    ).thenAnswer((_) async => const House(id: 'h1', name: 'Nossa Casa', cycleStartDay: 5, createdBy: 'user_1'));
    final authCubit = AuthCubit(mockAuthRepo);

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<AuthCubit>.value(value: authCubit, child: const HouseOnboardingPage()),
      ),
    );
    await tester.pumpAndSettle();

    // Fechado por padrão: os campos só aparecem quando pedem
    expect(find.text('A casa já tem dinheiro? (opcional)'), findsOneWidget);
    expect(find.byKey(const ValueKey('onboarding_initial_reserve')), findsNothing);
    await tester.tap(find.text('A casa já tem dinheiro? (opcional)'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const ValueKey('onboarding_initial_reserve')), '300000');
    await tester.enterText(find.byKey(const ValueKey('onboarding_initial_cash')), '45050');
    await tester.ensureVisible(find.text('Criar Casa e Entrar'));
    await tester.tap(find.text('Criar Casa e Entrar'));
    await tester.pumpAndSettle();

    verify(
      () => mockAuthRepo.createHouse(
        name: 'Nossa Casa',
        cycleStartDay: 5,
        initialReserveCents: 300000,
        initialCashCents: 45050,
      ),
    ).called(1);
  });

  testWidgets(
    'HouseOnboardingPage exibe orientações e informativo sobre kit padrão (Caixa, Pix, Dinheiro)',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockAuthRepo = MockAuthRepository();
      when(() => mockAuthRepo.currentUser).thenReturn(
        const UserProfile(
          id: 'user_1',
          fullName: 'Kelvynn Silva',
          email: 'kelvynn@teste.com',
        ),
      );
      when(() => mockAuthRepo.currentHouse).thenReturn(null);
      when(() => mockAuthRepo.isRestoringSession).thenReturn(false);
      when(
        () => mockAuthRepo.authStateChanges,
      ).thenAnswer((_) => const Stream.empty());
      when(
        () => mockAuthRepo.houseChanges,
      ).thenAnswer((_) => const Stream.empty());
      when(() => mockAuthRepo.getUserHouses()).thenAnswer((_) async => []);

      final authCubit = AuthCubit(mockAuthRepo);

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<AuthCubit>.value(
            value: authCubit,
            child: const HouseOnboardingPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Validações visuais da tela
      expect(find.text('Configuração da Casa'), findsOneWidget);
      expect(find.text('Criar Nova Casa'), findsOneWidget);
      expect(find.text('Tenho um Convite'), findsOneWidget);
      expect(
        find.textContaining(
          'Caixa da Casa, Pix, Dinheiro e categorias essenciais',
        ),
        findsOneWidget,
      );
      expect(find.text('Criar Casa e Entrar'), findsOneWidget);
    },
  );
}
