import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:omni_lar/core/di/service_locator.dart';
import 'package:omni_lar/core/errors/failures.dart';
import 'package:omni_lar/features/admin/data/datasources/admin_datasource.dart';
import 'package:omni_lar/features/admin/data/datasources/mock_admin_datasource.dart';
import 'package:omni_lar/features/admin/domain/entities/account_access.dart';
import 'package:omni_lar/features/admin/domain/entities/admin_models.dart';
import 'package:omni_lar/features/admin/presentation/cubit/account_access_cubit.dart';
import 'package:omni_lar/features/admin/presentation/pages/account_pending_page.dart';
import 'package:omni_lar/features/admin/presentation/pages/admin_page.dart';
import 'package:omni_lar/features/auth/domain/entities/user_profile.dart';
import 'package:omni_lar/features/auth/domain/repositories/auth_repository.dart';

class _MockAuthRepository extends Mock implements AuthRepository {}

class _MockAdminDataSource extends Mock implements AdminDataSource {}

void main() {
  group('Leitura do que o banco devolve', () {
    test('Status da conta e acesso de administrador', () {
      final access = AccountAccess.fromJson({'status': 'suspended', 'reason': 'Teste', 'is_admin': false});
      expect(access.status, AccountStatus.suspended);
      expect(access.reason, 'Teste');
      expect(access.isActive, isFalse);
      // Status desconhecido conta como em análise, nunca como liberado
      expect(AccountAccess.fromJson({'status': 'x'}).status, AccountStatus.pending);
    });

    test('Visão geral conta por status', () {
      final o = AdminOverview.fromJson({
        'accounts_total': 5,
        'accounts_by_status': {'active': 3, 'pending': 2},
        'accounts_new_7d': 2,
        'houses_total': 1,
        'houses_active_30d': 1,
        'ai_reads_today': 4,
        'ai_reads_month': 40,
        'admins': 1,
      });
      expect(o.count(AccountStatus.active), 3);
      expect(o.count(AccountStatus.pending), 2);
      expect(o.count(AccountStatus.suspended), 0);
    });

    test('Detalhe da conta traz casas e histórico', () {
      final d = AdminAccountDetail.fromJson({
        'user_id': 'u1',
        'full_name': 'Ana',
        'email': 'ana@x.com',
        'status': 'active',
        'houses': [
          {'name': 'Casa', 'role': 'owner', 'joined_at': '2026-10-01T10:00:00Z'},
        ],
        'ai_reads_today': 1,
        'ai_reads_month': 9,
        'history': [
          {
            'action': 'set_status',
            'details': {'from': 'pending', 'to': 'active'},
            'created_at': '2026-10-02T10:00:00Z',
          },
        ],
      });
      expect(d.account.houses, 1);
      expect(d.houses.single.roleLabel, 'Dono');
      expect(d.history.single.description, 'Status: em análise → liberada');
    });
  });

  group('Regras do painel no modo demo (iguais às do banco)', () {
    test('Aprovar em lote muda só as que estavam esperando', () async {
      final ds = MockAdminDataSource();
      final pending = await ds.listAccounts(status: AccountStatus.pending);
      expect(pending, isNotEmpty);

      final changed = await ds.setAccountStatus([for (final a in pending) a.userId], AccountStatus.active);
      expect(changed, pending.length);
      expect(await ds.listAccounts(status: AccountStatus.pending), isEmpty);
      // Repetir não muda nada
      expect(await ds.setAccountStatus([pending.first.userId], AccountStatus.active), 0);

      final audit = await ds.listAudit();
      expect(audit.where((e) => e.action == 'set_status').length, pending.length);
    });

    test('Recusar e suspender exigem motivo', () async {
      final ds = MockAdminDataSource();
      await expectLater(
        ds.setAccountStatus(['demo_pending_1'], AccountStatus.rejected),
        throwsA(isA<ServerFailure>()),
      );
      await expectLater(
        ds.setAccountStatus(['member_marina'], AccountStatus.suspended, reason: '  '),
        throwsA(isA<ServerFailure>()),
      );
      expect(await ds.setAccountStatus(['demo_pending_1'], AccountStatus.rejected, reason: 'Não conheço'), 1);
      final detail = await ds.getAccountDetail('demo_pending_1');
      expect(detail.account.status, AccountStatus.rejected);
      expect(detail.account.statusReason, 'Não conheço');
      expect(detail.history.single.description, contains('Não conheço'));
    });

    test('Ninguém muda o próprio status nem o próprio acesso de administrador', () async {
      final ds = MockAdminDataSource();
      await expectLater(
        ds.setAccountStatus(['member_carlos'], AccountStatus.suspended, reason: 'x'),
        throwsA(isA<ServerFailure>()),
      );
      await expectLater(ds.setPlatformAdmin('member_carlos', false), throwsA(isA<ServerFailure>()));
    });

    test('Só conta liberada vira administradora', () async {
      final ds = MockAdminDataSource();
      await expectLater(ds.setPlatformAdmin('demo_pending_2', true), throwsA(isA<ServerFailure>()));
      await ds.setPlatformAdmin('member_marina', true);
      final marina = (await ds.listAccounts(search: 'marina')).single;
      expect(marina.isAdmin, isTrue);
    });

    test('Configurações limpam domínios e e-mails e recusam e-mail inválido', () async {
      final ds = MockAdminDataSource();
      await ds.updateSettings(const AdminSettings(
        requireApproval: false,
        autoApproveInvited: true,
        autoApproveDomains: ['@Familia.com', 'familia.com', ' '],
        autoApproveEmails: ['Mae@Gmail.com', ''],
      ));
      final s = await ds.getSettings();
      expect(s.requireApproval, isFalse);
      expect(s.autoApproveDomains, ['familia.com']);
      expect(s.autoApproveEmails, ['mae@gmail.com']);

      await expectLater(
        ds.updateSettings(const AdminSettings(autoApproveEmails: ['sem-arroba'])),
        throwsA(isA<ServerFailure>()),
      );
    });

    test('Busca por nome ou e-mail', () async {
      final ds = MockAdminDataSource();
      expect((await ds.listAccounts(search: 'PAULA')).single.userId, 'demo_pending_1');
      expect((await ds.listAccounts(search: 'exemplo.com')).length, 3);
    });
  });

  group('Planos Free e Premium', () {
    test('Leitura do plano e do limite', () {
      final access = AccountAccess.fromJson({
        'status': 'active',
        'plan': 'premium',
        'plan_expires_at': '2026-12-31T23:59:59Z',
      });
      expect(access.plan, AccountPlan.premium);
      expect(access.planExpiresAt, isNotNull);
      expect(AccountAccess.fromJson({'status': 'active'}).plan, AccountPlan.free);

      final limit = PlanLimit.fromJson({'plan': 'free', 'resource': 'members_per_house', 'max_value': 4})!;
      expect(limit.resource, PlanResource.membersPerHouse);
      expect(limit.maxValue, 4);
      expect(PlanLimit.fromJson({'plan': 'free', 'resource': 'desconhecido'}), isNull);
      expect(PlanLimit.fromJson({'plan': 'premium', 'resource': 'active_projects'})!.maxValue, isNull);
    });

    test('Trocar plano registra no histórico e recusa validade passada', () async {
      final ds = MockAdminDataSource();
      final until = DateTime.now().add(const Duration(days: 60));
      expect(await ds.setPlan(['demo_pending_1'], AccountPlan.premium, expiresAt: until, note: 'testador'), 1);

      final detail = await ds.getAccountDetail('demo_pending_1');
      expect(detail.account.plan, AccountPlan.premium);
      expect(detail.account.planNote, 'testador');
      expect(detail.history.single.description, startsWith('Plano: Free → Premium até '));
      // Repetir não muda nada
      expect(await ds.setPlan(['demo_pending_1'], AccountPlan.premium, expiresAt: until, note: 'testador'), 0);

      await expectLater(
        ds.setPlan(['demo_pending_2'], AccountPlan.premium, expiresAt: DateTime.now().subtract(const Duration(days: 1))),
        throwsA(isA<ServerFailure>()),
      );

      // Voltar para Free tira a validade
      await ds.setPlan(['demo_pending_1'], AccountPlan.free);
      final back = await ds.getAccountDetail('demo_pending_1');
      expect(back.account.plan, AccountPlan.free);
      expect(back.account.planExpiresAt, isNull);

      final overview = await ds.getOverview();
      expect(overview.countPlan(AccountPlan.premium), 2);
    });

    test('Limites editáveis, sem limite quando vazio', () async {
      final ds = MockAdminDataSource();
      await ds.setPlanLimit(AccountPlan.free, PlanResource.aiReadsPerDay, 20);
      await ds.setPlanLimit(AccountPlan.premium, PlanResource.housesOwned, null);
      final limits = await ds.getPlanLimits();
      int? value(AccountPlan p, PlanResource r) =>
          limits.firstWhere((l) => l.plan == p && l.resource == r).maxValue;
      expect(value(AccountPlan.free, PlanResource.aiReadsPerDay), 20);
      expect(value(AccountPlan.premium, PlanResource.housesOwned), isNull);
      await expectLater(
        ds.setPlanLimit(AccountPlan.free, PlanResource.housesOwned, -1),
        throwsA(isA<ServerFailure>()),
      );
      final audit = await ds.listAudit();
      expect(audit.first.description, 'Limite do Premium: Casas como dono 3 → sem limite');
    });
  });

  group('Status da própria conta', () {
    late _MockAuthRepository auth;
    late _MockAdminDataSource ds;
    late StreamController<UserProfile?> authChanges;

    setUp(() {
      auth = _MockAuthRepository();
      ds = _MockAdminDataSource();
      authChanges = StreamController<UserProfile?>.broadcast();
      when(() => auth.authStateChanges).thenAnswer((_) => authChanges.stream);
      when(() => auth.isDemoMode).thenReturn(false);
      when(() => auth.currentUser).thenReturn(null);
      when(() => ds.watchMyAccess()).thenAnswer((_) => const Stream.empty());
    });

    tearDown(() => authChanges.close());

    test('Conta em análise fica bloqueada; aprovada libera', () async {
      when(() => ds.getMyAccess()).thenAnswer((_) async => const AccountAccess(status: AccountStatus.pending));
      final cubit = AccountAccessCubit(ds, auth);
      expect(cubit.state.isBlocked, isFalse); // sem login ainda

      authChanges.add(const UserProfile(id: 'u1', fullName: 'Ana', email: 'ana@x.com'));
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.isBlocked, isTrue);

      when(() => ds.getMyAccess())
          .thenAnswer((_) async => const AccountAccess(status: AccountStatus.active, isAdmin: true));
      await cubit.refresh();
      expect(cubit.state.isBlocked, isFalse);
      expect(cubit.state.isAdmin, isTrue);

      authChanges.add(null);
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.access, isNull);
      await cubit.close();
    });

    test('Sem resposta do servidor ninguém fica preso na tela de espera', () async {
      when(() => ds.getMyAccess()).thenThrow(const ServerFailure('offline'));
      final cubit = AccountAccessCubit(ds, auth);
      authChanges.add(const UserProfile(id: 'u1', fullName: 'Ana', email: 'ana@x.com'));
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.isBlocked, isFalse);
      await cubit.close();
    });
  });

  group('Tela de espera', () {
    setUpAll(() async {
      if (!sl.isRegistered<AccountAccessCubit>()) await initServiceLocator();
    });

    testWidgets('Pergunta o status ao voltar ao app, de tempos em tempos e no botão', (tester) async {
      final auth = _MockAuthRepository();
      final ds = _MockAdminDataSource();
      when(() => auth.authStateChanges).thenAnswer((_) => const Stream.empty());
      when(() => auth.isDemoMode).thenReturn(false);
      when(() => auth.currentUser).thenReturn(const UserProfile(id: 'u1', fullName: 'Ana', email: 'ana@x.com'));
      // Sem aviso em tempo real, como com o app em segundo plano
      when(() => ds.watchMyAccess()).thenAnswer((_) => const Stream.empty());
      var status = AccountStatus.pending;
      var calls = 0;
      when(() => ds.getMyAccess()).thenAnswer((_) async {
        calls++;
        return AccountAccess(status: status);
      });

      final cubit = AccountAccessCubit(ds, auth);
      final previous = sl<AccountAccessCubit>();
      sl.unregister<AccountAccessCubit>();
      sl.registerSingleton<AccountAccessCubit>(cubit);
      addTearDown(() async {
        sl.unregister<AccountAccessCubit>();
        sl.registerSingleton<AccountAccessCubit>(previous);
        await cubit.close();
      });

      await tester.pumpWidget(const MaterialApp(home: AccountPendingPage(pollInterval: Duration(seconds: 1))));
      await tester.pump();
      expect(cubit.state.isBlocked, isTrue);
      var before = calls;

      await tester.pump(const Duration(seconds: 1));
      expect(calls, before + 1, reason: 'consulta periódica');

      before = calls;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(calls, before + 1, reason: 'consulta ao voltar ao app');

      status = AccountStatus.active;
      await tester.tap(find.text('Verificar agora'));
      await tester.pump();
      expect(cubit.state.isBlocked, isFalse);

      // Fora da tela, para de consultar
      await tester.pumpWidget(const SizedBox());
      before = calls;
      await tester.pump(const Duration(seconds: 3));
      expect(calls, before);
    });
  });

  group('Tela do painel (modo demo)', () {
    setUpAll(() async {
      await initServiceLocator();
    });

    testWidgets('Mostra a visão geral e aprova todas as contas pendentes', (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(const MaterialApp(home: AdminPage()));
      await tester.pumpAndSettle();

      expect(find.text('Administração do Omni Lar'), findsOneWidget);
      expect(find.text('Aprovações (2)'), findsOneWidget);
      expect(find.textContaining('esperando aprovação'), findsOneWidget);

      await tester.tap(find.text('Aprovações (2)'));
      await tester.pumpAndSettle();
      expect(find.text('Paula Souza'), findsOneWidget);

      await tester.tap(find.text('Aprovar todas'));
      await tester.pumpAndSettle();
      expect(find.text('Nenhuma conta esperando aprovação.'), findsOneWidget);
      expect(find.text('2 conta(s) aprovada(s).'), findsOneWidget);
    });

    testWidgets('Configurações mostram os limites dos planos e o detalhe troca o plano', (tester) async {
      tester.view.physicalSize = const Size(1400, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(const MaterialApp(home: AdminPage(initialTab: 'configuracoes')));
      await tester.pumpAndSettle();
      expect(find.text('Limites dos planos'), findsOneWidget);
      expect(find.text('Moradores por casa'), findsOneWidget);
      expect(find.text('sem limite'), findsOneWidget);

      await tester.tap(find.text('Contas'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Marina Demo'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Plano: Premium'), findsOneWidget);
      await tester.tap(find.text('Mudar plano'));
      await tester.pumpAndSettle();
      expect(find.text('Plano de Marina Demo'), findsOneWidget);
      await tester.tap(find.text('Free').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();
      expect(find.text('Marina Demo agora é Free.'), findsOneWidget);
    });

    testWidgets('Recusar pede o motivo antes', (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(const MaterialApp(home: AdminPage(initialTab: 'contas')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Teste Antigo'));
      await tester.pumpAndSettle();
      expect(find.text('Reativar'), findsOneWidget);
      await tester.tap(find.text('Fechar'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Marina Demo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Suspender'));
      await tester.pumpAndSettle();
      expect(find.text('Suspender Marina Demo'), findsOneWidget);
      await tester.tap(find.text('Confirmar'));
      await tester.pumpAndSettle();
      expect(find.text('Informe o motivo'), findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
    });
  });
}
