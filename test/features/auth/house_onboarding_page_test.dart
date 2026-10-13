import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mocktail/mocktail.dart';
import 'package:omni_lar/features/auth/domain/entities/user_profile.dart';
import 'package:omni_lar/features/auth/domain/repositories/auth_repository.dart';
import 'package:omni_lar/features/auth/presentation/cubit/auth_cubit.dart';
import 'package:omni_lar/features/auth/presentation/pages/house_onboarding_page.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

void main() {
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
