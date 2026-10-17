import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/ai/ai_consent.dart';
import 'package:omni_lar/features/auth/data/datasources/mock_auth_datasource.dart';
import 'package:omni_lar/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:omni_lar/features/auth/domain/entities/user_profile.dart';
import 'package:omni_lar/features/auth/presentation/cubit/auth_cubit.dart';
import 'package:omni_lar/features/legal/legal_page.dart';
import 'package:omni_lar/features/legal/legal_texts.dart';
import 'package:omni_lar/features/legal/terms_acceptance_page.dart';

void main() {
  group('Aceite dos termos', () {
    const base = UserProfile(id: 'u', email: 'a@b.c', fullName: 'Ana');

    test('Só pede o aceite quando o perfil veio do banco e a versão é outra', () {
      expect(base.needsTermsAcceptance(kLegalVersion), isFalse);
      expect(base.copyWith(legalStatusKnown: true).needsTermsAcceptance(kLegalVersion), isTrue);
      expect(
        base.copyWith(legalStatusKnown: true, termsVersion: kLegalVersion).needsTermsAcceptance(kLegalVersion),
        isFalse,
      );
    });

    testWidgets('O botão só libera com a caixa marcada e grava o aceite', (tester) async {
      final dataSource = MockAuthDataSource(startAuthenticated: false);
      final cubit = AuthCubit(AuthRepositoryImpl(dataSource));
      await tester.runAsync(() => cubit.signInWithEmailPassword('carlos@omnilar.com', '123456'));
      addTearDown(() {
        cubit.close();
        dataSource.dispose();
      });

      await tester.pumpWidget(BlocProvider.value(
        value: cubit,
        child: const MaterialApp(home: TermsAcceptancePage()),
      ));

      final button = find.byKey(const Key('terms_accept_button'));
      expect(tester.widget<FilledButton>(button).onPressed, isNull);

      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await tester.tap(button);
      // A página fica girando até o app sair dela (o roteador não existe aqui)
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(cubit.state.user?.termsVersion, kLegalVersion);
    });
  });

  group('Consentimento da IA', () {
    tearDown(() {
      AiConsent.isGiven = () => true;
      AiConsent.ask = () async => true;
      AiConsent.record = () async {};
    });

    test('Já dado: não pergunta', () async {
      var asked = false;
      AiConsent.isGiven = () => true;
      AiConsent.ask = () async => asked = true;
      expect(await AiConsent.request(), isTrue);
      expect(asked, isFalse);
    });

    test('Recusado: não envia e não grava', () async {
      var recorded = false;
      AiConsent.isGiven = () => false;
      AiConsent.ask = () async => false;
      AiConsent.record = () async => recorded = true;
      expect(await AiConsent.request(), isFalse);
      expect(recorded, isFalse);
    });

    test('Permitido: grava no perfil', () async {
      var recorded = false;
      AiConsent.isGiven = () => false;
      AiConsent.ask = () async => true;
      AiConsent.record = () async => recorded = true;
      expect(await AiConsent.request(), isTrue);
      expect(recorded, isTrue);
    });
  });

  testWidgets('A página mostra o responsável, o contato e a versão', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LegalPage(document: privacyPolicy)));
    expect(find.text('Política de privacidade'), findsOneWidget);
    expect(find.text('Versão de $kLegalVersionLabel'), findsOneWidget);
    expect(find.textContaining(kLegalControllerName), findsWidgets);
    expect(find.textContaining(kLegalContactEmail), findsWidgets);
  });
}
