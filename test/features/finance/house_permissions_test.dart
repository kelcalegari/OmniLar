import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/domain/value_objects/financial_cycle.dart';
import 'package:omni_lar/features/finance/data/datasources/mock_finance_datasource.dart';
import 'package:omni_lar/features/finance/data/repositories/finance_repository_impl.dart';
import 'package:omni_lar/features/finance/domain/entities/house_member.dart';
import 'package:omni_lar/features/finance/domain/entities/house_permissions.dart';
import 'package:omni_lar/features/finance/domain/entities/house_settings.dart';
import 'package:omni_lar/features/finance/presentation/cubit/finance_cubit.dart';
import 'package:omni_lar/features/finance/presentation/cubit/finance_state.dart';

void main() {
  group('HousePermissions', () {
    test('sem configuração tudo segue exigindo administrador', () {
      const p = HousePermissions();
      expect(p.isEmpty, isTrue);
      for (final action in HousePermissionAction.values) {
        expect(p.allows(action, isAdmin: false, memberId: 'u1'), isFalse);
        expect(p.allows(action, isAdmin: true), isTrue);
      }
      expect(HouseSettings.fromJson({}).permissions.isEmpty, isTrue);
      // Banco sem a coluna ou com lixo
      expect(HousePermissions.fromJson(null).isEmpty, isTrue);
      expect(HousePermissions.fromJson({'acao_x': {'level': 'all'}, 'fechar_ciclo': 'x'}).isEmpty, isTrue);
    });

    test('todos, escolhidos e administrador que sempre passa', () {
      final p = HousePermissions.fromJson({
        'fechar_ciclo': {'level': 'all'},
        'saldo_inicial': {'level': 'chosen', 'members': ['u1']},
        'reabrir_ciclo': {'level': 'admins'},
      });
      expect(p.allows(HousePermissionAction.closeCycle, isAdmin: false, memberId: 'u2'), isTrue);
      expect(p.allows(HousePermissionAction.initialBalance, isAdmin: false, memberId: 'u1'), isTrue);
      expect(p.allows(HousePermissionAction.initialBalance, isAdmin: false, memberId: 'u2'), isFalse);
      expect(p.allows(HousePermissionAction.initialBalance, isAdmin: true), isTrue);
      expect(p.allows(HousePermissionAction.reopenCycle, isAdmin: false, memberId: 'u1'), isFalse);
      expect(p.allows(HousePermissionAction.reopenCycle, isAdmin: true), isTrue);
    });

    test('toJson só leva o que foge do padrão e volta igual', () {
      final p = const HousePermissions()
          .withAction(HousePermissionAction.closeCycle, const ActionPermission(PermissionLevel.all))
          .withAction(HousePermissionAction.houseLoans,
              const ActionPermission(PermissionLevel.chosen, members: ['u1', 'u2']))
          .withAction(HousePermissionAction.reopenCycle, ActionPermission.admins);
      expect(p.toJson(), {
        'fechar_ciclo': {'level': 'all'},
        'emprestimos_da_casa': {'level': 'chosen', 'members': ['u1', 'u2']},
      });
      expect(HousePermissions.fromJson(p.toJson()), p);
    });
  });

  group('FinanceState.canDo', () {
    FinanceState state(Map<String, dynamic> json) => FinanceState(
          currentCycle: FinancialCycle.fromDate(date: DateTime(2026, 10, 10), cycleStartDay: 5),
          members: const [
            HouseMember(id: 'adm', name: 'Ana', role: 'admin'),
            HouseMember(id: 'm1', name: 'Bia'),
            HouseMember(id: 'm2', name: 'Caio'),
          ],
          houseSettings: HouseSettings.fromJson({'permissions': json}),
        );

    test('administrador sempre; demais seguem o nível', () {
      final s = state({
        'fechar_ciclo': {'level': 'chosen', 'members': ['m1']},
      });
      expect(s.canDo(HousePermissionAction.closeCycle, 'adm'), isTrue);
      expect(s.canDo(HousePermissionAction.closeCycle, 'm1'), isTrue);
      expect(s.canDo(HousePermissionAction.closeCycle, 'm2'), isFalse);
      expect(s.canDo(HousePermissionAction.reopenCycle, 'm1'), isFalse);
      expect(s.canDo(HousePermissionAction.closeCycle, 'desconhecido'), isFalse);
      expect(state({}).canDo(HousePermissionAction.editConfigurations, 'm1'), isFalse);
    });
  });

  group('FinanceCubit: permissões', () {
    test('administrador grava e a casa passa a ler as permissões', () async {
      final cubit = FinanceCubit(FinanceRepositoryImpl(MockFinanceDataSource()));
      await cubit.loadCycleData();
      const permissions = HousePermissions({
        HousePermissionAction.closeCycle: ActionPermission(PermissionLevel.all),
      });
      expect(await cubit.updateHouseSettings(permissions: permissions), isTrue);
      expect(cubit.state.houseSettings.permissions, permissions);
      await cubit.close();
    });

    test('morador comum não muda as permissões', () async {
      final dataSource = MockFinanceDataSource();
      final cubit = FinanceCubit(FinanceRepositoryImpl(dataSource));
      await cubit.loadCycleData();
      dataSource.viewerId = 'morador_comum';
      const permissions = HousePermissions({
        HousePermissionAction.closeCycle: ActionPermission(PermissionLevel.all),
      });
      expect(await cubit.updateHouseSettings(permissions: permissions), isFalse);
      await cubit.close();
    });
  });

  group('Migration 0103', () {
    final sql = File('supabase/migrations/20261018230000_0103_house_permissions.sql').readAsStringSync();

    test('cria a coluna, a validação e has_house_permission com admin sempre passando', () {
      expect(sql, contains('add column if not exists permissions jsonb'));
      expect(sql, contains('function public.house_permissions_valid'));
      expect(sql, contains('function public.has_house_permission(p_house_id uuid, p_action text)'));
      expect(sql, contains('if public.is_house_admin(p_house_id) then'));
      expect(sql, isNot(contains('drop trigger')));
    });

    test('cada ação do app existe na lista do banco e é usada numa função', () {
      for (final action in HousePermissionAction.values) {
        expect(sql, contains("'${action.dbValue}'"), reason: action.dbValue);
        expect(sql, contains("has_house_permission("), reason: action.dbValue);
      }
      for (final action in HousePermissionAction.values) {
        expect(RegExp("has_house_permission\\([a-z_.]+, '${action.dbValue}'\\)").hasMatch(sql), isTrue,
            reason: action.dbValue);
      }
    });

    test('update_house_settings mantém os campos anteriores e só administradores mudam permissions', () {
      for (final field in [
        'opening_inflow_rules', 'closing_defaults', 'new_member_split_policy', 'folego_params',
        'budget_alert_stages', 'import_matching', 'import_defaults', 'cash_label', 'shopping_units',
        'income_visibility', 'split_basis', 'planner_category_overrides',
      ]) {
        expect(sql, contains(field), reason: field);
      }
      expect(sql, contains("p_settings ? 'permissions' and not public.is_house_admin(p_house_id)"));
    });
  });
}
