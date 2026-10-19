import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/features/calendar/data/datasources/mock_calendar_datasource.dart';
import 'package:omni_lar/features/calendar/data/offline/calendar_offline_codec.dart';
import 'package:omni_lar/features/calendar/domain/entities/task_item.dart';

void main() {
  TaskItem task({
    TaskRecurrence recurrence = TaskRecurrence.weekly,
    List<String> rotation = const ['ana', 'bia', 'caio'],
    String? assigned = 'ana',
    String? next = 'bia',
    DateTime? due,
  }) =>
      TaskItem(
        id: 't1',
        title: 'Lixo',
        dueDate: due ?? DateTime(2026, 10, 20),
        assignedToMemberId: assigned,
        createdByMemberId: 'ana',
        createdAt: DateTime(2026, 10, 1),
        recurrence: recurrence,
        rotationMemberIds: rotation,
        nextAssigneeMemberId: next,
      );

  group('Rodízio', () {
    test('tarefa atual (sem repetição) não gera nada', () {
      final t = TaskItem(id: 'x', title: 'Única', createdByMemberId: 'a', createdAt: DateTime(2026, 10, 1));
      expect(t.isRecurring, isFalse);
      expect(t.nextOccurrence(id: 'n', now: DateTime(2026, 10, 2)), isNull);
    });

    test('rotationAfter dá a volta e volta ao primeiro se o atual saiu', () {
      const m = ['ana', 'bia', 'caio'];
      expect(TaskItem.rotationAfter(m, 'ana'), 'bia');
      expect(TaskItem.rotationAfter(m, 'caio'), 'ana');
      expect(TaskItem.rotationAfter(m, 'zed'), 'ana');
      expect(TaskItem.rotationAfter(m, null), 'ana');
      expect(TaskItem.rotationAfter(const [], 'ana'), isNull);
    });

    test('a próxima ocorrência vai para o próximo do rodízio, uma semana depois', () {
      final next = task().nextOccurrence(id: 'n', now: DateTime(2026, 10, 19))!;
      expect(next.assignedToMemberId, 'bia');
      expect(next.nextAssigneeMemberId, 'caio');
      expect(next.dueDate, DateTime(2026, 10, 27));
      expect(next.isCompleted, isFalse);
      expect(next.recurrence, TaskRecurrence.weekly);
      expect(next.rotationMemberIds, ['ana', 'bia', 'caio']);
    });

    test('sem next_assignee usa o seguinte de quem tem a tarefa', () {
      final next = task(next: null, assigned: 'caio').nextOccurrence(id: 'n', now: DateTime(2026, 10, 19))!;
      expect(next.assignedToMemberId, 'ana');
    });

    test('vencimento atrasado continua andando até hoje; mensal respeita o fim do mês', () {
      final daily = task(recurrence: TaskRecurrence.daily, due: DateTime(2026, 10, 1))
          .nextOccurrence(id: 'n', now: DateTime(2026, 10, 19))!;
      expect(daily.dueDate, DateTime(2026, 10, 19));
      final monthly = task(recurrence: TaskRecurrence.monthly, due: DateTime(2026, 1, 31))
          .nextOccurrence(id: 'n', now: DateTime(2026, 1, 31))!;
      expect(monthly.dueDate, DateTime(2026, 2, 28));
    });

    test('mock: concluir cria a próxima e não duplica ao reabrir e concluir de novo', () async {
      final ds = MockCalendarDataSource();
      await ds.addTask(task(due: DateTime.now()));
      await ds.setTaskCompleted(taskId: 't1', completed: true, completedByMemberId: 'ana');
      var all = (await ds.getTasks(includeArchived: true)).where((t) => t.title == 'Lixo').toList();
      expect(all, hasLength(2));
      final spawned = all.firstWhere((t) => t.id != 't1');
      expect(spawned.assignedToMemberId, 'bia');
      expect(spawned.isCompleted, isFalse);
      expect(all.firstWhere((t) => t.id == 't1').isRecurring, isFalse);

      await ds.setTaskCompleted(taskId: 't1', completed: false, completedByMemberId: 'ana');
      await ds.setTaskCompleted(taskId: 't1', completed: true, completedByMemberId: 'ana');
      all = (await ds.getTasks(includeArchived: true)).where((t) => t.title == 'Lixo').toList();
      expect(all, hasLength(2));
    });

    test('codec offline guarda a repetição e lê tarefa antiga como única', () {
      final back = taskItemFromJson(taskItemToJson(task()));
      expect(back, task());
      final legacy = taskItemToJson(TaskItem(id: 'x', title: 'a', createdByMemberId: 'a', createdAt: DateTime(2026, 10, 1)));
      expect(legacy.containsKey('recurrence'), isFalse);
      expect(taskItemFromJson(legacy).recurrence, TaskRecurrence.none);
    });
  });

  group('Migration 0104 (tarefas)', () {
    final sql = File('supabase/migrations/20261018240000_0104_card_cycle_approval_tasks.sql').readAsStringSync();

    test('colunas, gatilho ao concluir e sem drop trigger', () {
      expect(sql, contains("recurrence text check (recurrence in ('daily', 'weekly', 'monthly'))"));
      expect(sql, contains('rotation_members uuid[] not null default'));
      expect(sql, contains('next_assignee uuid'));
      expect(sql, contains('create or replace trigger trg_tasks_spawn_next_recurring'));
      expect(sql, contains('new.is_completed and not old.is_completed and new.recurrence is not null'));
      expect(sql, isNot(contains('drop trigger')));
    });
  });
}
