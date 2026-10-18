import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/features/finance/data/datasources/mock_finance_datasource.dart';
import 'package:omni_lar/features/finance/data/repositories/finance_repository_impl.dart';
import 'package:omni_lar/features/finance/domain/entities/budget_alert_stages.dart';
import 'package:omni_lar/features/finance/domain/entities/category.dart';
import 'package:omni_lar/features/finance/domain/entities/house_settings.dart';
import 'package:omni_lar/features/finance/domain/entities/member_settings.dart';
import 'package:omni_lar/features/finance/presentation/cubit/finance_cubit.dart';

void main() {
  group('BudgetAlertStages', () {
    test('sem nada gravado vale o de sempre: 90 e 100', () {
      for (final json in <Object?>[null, 'x', <int>[], <int>[100, 90], <int>[0], <int>[1, 2, 3, 4, 5]]) {
        expect(BudgetAlertStages.fromJson(json), BudgetAlertStages.defaults);
      }
      expect(HouseSettings.fromJson({}).budgetAlertStages.stages, [90, 100]);
    });

    test('lê, escreve e interpreta o texto digitado', () {
      final stages = BudgetAlertStages.fromJson([80, 100, 120]);
      expect(stages.stages, [80, 100, 120]);
      expect(BudgetAlertStages.fromJson(stages.toJson()), stages);
      expect(HouseSettings.fromJson({'budget_alert_stages': [80, 100]}).budgetAlertStages.label, '80% e 100%');
      expect(BudgetAlertStages.parse('80, 100%')!.stages, [80, 100]);
      expect(BudgetAlertStages.parse('80 100')!.stages, [80, 100]);
      expect(BudgetAlertStages.parse('100, 80'), isNull);
      expect(BudgetAlertStages.parse('80, abc'), isNull);
      expect(BudgetAlertStages.parse('301'), isNull);
      expect(BudgetAlertStages.parse(''), isNull);
    });

    test('estágio atingido segue o agendador: abaixo de 100 ao chegar, de 100 em diante ao passar', () {
      const defaults = BudgetAlertStages.defaults;
      expect(defaults.stageFor(89), 0);
      expect(defaults.stageFor(90), 90);
      expect(defaults.stageFor(100), 90);
      expect(defaults.stageFor(101), 100);
      expect(const BudgetAlertStages([80, 100]).stageFor(80), 80);
    });
  });

  group('Categoria e casa', () {
    test('a categoria pode ter estágios próprios e a casa grava os dela', () async {
      const category = ExpenseCategory(
        id: 'c',
        name: 'Mercado',
        icon: 'i',
        colorHex: '#000000',
        budgetAlertStages: BudgetAlertStages([70, 100]),
      );
      expect(category.budgetAlertStages!.stages, [70, 100]);
      expect(category == const ExpenseCategory(id: 'c', name: 'Mercado', icon: 'i', colorHex: '#000000'), isFalse);

      final cubit = FinanceCubit(FinanceRepositoryImpl(MockFinanceDataSource()));
      await cubit.loadCycleData();
      final ok = await cubit.updateHouseSettings(budgetAlertStages: const BudgetAlertStages([80, 100]));
      expect(ok, isTrue);
      expect(cubit.state.houseSettings.budgetAlertStages.stages, [80, 100]);
      await cubit.close();
    });
  });

  group('MemberSettings: lembretes e resumo semanal', () {
    test('sem escolha valem os padrões e o padrão não fica gravado', () {
      const empty = MemberSettings();
      expect(empty.alertHour, 9);
      expect(empty.weeklyDay, 0);
      expect(empty.weeklyHour, 18);
      expect(empty.mutedReminders, isEmpty);
      final same = empty.withAlertPrefs(alertHour: 9, muted: {}, weeklyDay: 0, weeklyHour: 18);
      expect(same, empty);
    });

    test('guarda horário, grupos silenciados e dia do resumo, ignorando o inválido', () {
      final settings = const MemberSettings().withAlertPrefs(
        alertHour: 7,
        muted: {'tasks', 'bills'},
        weeklyDay: 1,
        weeklyHour: 8,
      );
      expect(settings.toJson(), {
        'alert_hour': 7,
        'muted_reminders': ['bills', 'tasks'],
        'weekly_day': 1,
        'weekly_hour': 8,
      });
      expect(MemberSettings.fromJson(settings.toJson()), settings);
      expect(settings.mutedReminders, {'bills', 'tasks'});

      final bad = MemberSettings.fromJson({
        'alert_hour': 30,
        'weekly_day': 9,
        'weekly_hour': 'x',
        'muted_reminders': ['nada', 3, 'cycle'],
      });
      expect(bad.alertHour, 9);
      expect(bad.weeklyDay, 0);
      expect(bad.weeklyHour, 18);
      expect(bad.mutedReminders, {'cycle'});
    });

    test('preserva os padrões de lançamento ao mexer nos lembretes', () {
      final base = const MemberSettings().withLaunchDefaults(
        payer: LaunchPayer.house,
        paymentMethodId: null,
        categoryId: null,
      );
      final next = base.withAlertPrefs(alertHour: 6, muted: {}, weeklyDay: 0, weeklyHour: 18);
      expect(next.launchPayer, LaunchPayer.house);
      expect(next.alertHour, 6);
    });
  });

  group('Migration 0099', () {
    final sql = File('supabase/migrations/20261018190000_0099_alert_params.sql').readAsStringSync();

    test('segue o estilo: create or replace trigger, sem drop trigger', () {
      expect(sql, contains('create or replace trigger trg_notifications_member_alert_gate'));
      expect(sql.toLowerCase(), isNot(contains('drop trigger')));
    });

    test('padrão da casa é 90 e 100 e os estágios são validados', () {
      expect(sql, contains("default '[90, 100]'::jsonb"));
      expect(sql, contains('budget_alert_stages_valid'));
      expect(sql, contains('member_settings_valid'));
      expect(sql, contains("'alert_hour', 'weekly_hour'"));
      expect(sql, contains("'muted_reminders'"));
    });

    test('só administradores mudam os estágios da casa', () {
      expect(sql, contains("p_settings ? 'budget_alert_stages' and not public.is_house_admin(p_house_id)"));
    });

    test('o agendador respeita os estágios, o horário e o resumo de cada morador', () {
      expect(sql, contains('notification_budget_stage(v_pct, coalesce(c.budget_alert_stages, v_house_stages))'));
      expect(sql, contains("omnilar.sched_local"));
      expect(sql, contains("ms.settings->>'weekly_day'"));
    });
  });
}
