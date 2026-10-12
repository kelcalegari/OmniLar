import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/features/calendar/data/datasources/mock_calendar_datasource.dart';
import 'package:omni_lar/features/calendar/data/repositories/calendar_repository_impl.dart';
import 'package:omni_lar/features/calendar/domain/entities/task_item.dart';
import 'package:omni_lar/features/calendar/presentation/cubit/calendar_cubit.dart';

void main() {
  group('Calendar / Tasks Realtime Sync', () {
    late MockCalendarDataSource dataSource;
    late CalendarRepositoryImpl repository;
    late CalendarCubit cubit;

    setUp(() async {
      dataSource = MockCalendarDataSource();
      repository = CalendarRepositoryImpl(dataSource);
      cubit = CalendarCubit(repository);
      await cubit.loadCalendarData();
    });

    tearDown(() {
      cubit.close();
    });

    test('reflete adição externa de tarefa na stream em tempo real', () async {
      final initialCount = cubit.state.tasks.length;

      // Parceiro de república adiciona tarefa
      await dataSource.addTask(
        TaskItem(
          id: 'task_realtime_1',
          title: 'Trocar filtro de água da cozinha',
          priority: TaskPriority.high,
          cost: const Money(3500),
          createdByMemberId: 'member_marina',
          createdAt: DateTime.now(),
        ),
      );

      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(cubit.state.tasks.length, equals(initialCount + 1));
      expect(
        cubit.state.tasks.any((t) => t.title == 'Trocar filtro de água da cozinha'),
        isTrue,
      );
    });

    test('reflete conclusão de tarefa em tempo real', () async {
      final targetTask = cubit.state.tasks.firstWhere((t) => !t.isCompleted);

      // Parceiro conclui a tarefa
      await dataSource.toggleTaskComplete(
        taskId: targetTask.id,
        completedByMemberId: 'member_marina',
      );

      await Future<void>.delayed(const Duration(milliseconds: 50));

      final updatedTask =
          cubit.state.tasks.firstWhere((t) => t.id == targetTask.id);
      expect(updatedTask.isCompleted, isTrue);
    });
  });
}
