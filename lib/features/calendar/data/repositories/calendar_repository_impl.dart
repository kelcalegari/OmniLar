import '../../../../core/network/offline_queue.dart';
import '../../../../core/network/offline_sync_service.dart';
import '../../../../core/utils/uuid.dart';
import '../offline/calendar_offline_codec.dart';
import '../../../../core/domain/enums/recurrence.dart';
import '../../domain/entities/calendar_event.dart';
import '../../domain/entities/event_participant.dart';
import '../../domain/entities/task_item.dart';
import '../../domain/repositories/calendar_repository.dart';
import '../datasources/calendar_datasource.dart';

class CalendarRepositoryImpl implements CalendarRepository {
  final CalendarDataSource _dataSource;
  final OfflineSyncService? _offlineSync;

  CalendarRepositoryImpl(this._dataSource, [this._offlineSync]);

  @override
  Future<List<CalendarEvent>> getEvents() => _dataSource.getEvents();

  @override
  Future<void> addEvent(CalendarEvent event) async {
    final sync = _offlineSync;
    if (sync == null || !sync.isActive) return _dataSource.addEvent(event);

    final withId = isUuid(event.id) ? event : event.copyWith(id: generateUuidV4());
    await sync.runOrQueue(
      OfflineActionType.addCalendarEvent,
      () => calendarEventToJson(withId),
      () => _dataSource.addEvent(withId),
    );
  }

  @override
  Future<void> updateEvent(
    CalendarEvent event, {
    RecurrenceScope scope = RecurrenceScope.thisInstanceOnly,
  }) =>
      _dataSource.updateEvent(event, scope: scope);

  @override
  Future<void> deleteEvent(
    String eventId, {
    RecurrenceScope scope = RecurrenceScope.thisInstanceOnly,
  }) =>
      _dataSource.deleteEvent(eventId, scope: scope);

  @override
  Future<void> updateRsvp({
    required String eventId,
    required String memberId,
    required RsvpStatus status,
  }) =>
      _dataSource.updateRsvp(
        eventId: eventId,
        memberId: memberId,
        status: status,
      );

  @override
  Future<void> cancelEvent(String eventId) => _dataSource.cancelEvent(eventId);

  @override
  Stream<void> watchEventChanges() => _dataSource.watchEventChanges();

  @override
  Future<List<TaskItem>> getTasks({bool includeArchived = false}) =>
      _dataSource.getTasks(includeArchived: includeArchived);

  @override
  Stream<List<TaskItem>> watchTasks({bool includeArchived = false}) =>
      _dataSource.watchTasks(includeArchived: includeArchived);

  @override
  Future<void> addTask(TaskItem task) async {
    final sync = _offlineSync;
    if (sync == null || !sync.isActive) return _dataSource.addTask(task);

    final withId = isUuid(task.id) ? task : task.copyWith(id: generateUuidV4());
    await sync.runOrQueue(
      OfflineActionType.addTask,
      () => taskItemToJson(withId),
      () => _dataSource.addTask(withId),
    );
  }

  @override
  Future<void> toggleTaskComplete({
    required String taskId,
    required String completedByMemberId,
  }) =>
      _dataSource.toggleTaskComplete(
        taskId: taskId,
        completedByMemberId: completedByMemberId,
      );

  @override
  Future<bool> setTaskCompleted({
    required String taskId,
    required bool completed,
    required String completedByMemberId,
  }) async {
    final sync = _offlineSync;
    final at = DateTime.now();
    Future<void> write() => _dataSource.setTaskCompleted(
          taskId: taskId,
          completed: completed,
          completedByMemberId: completedByMemberId,
          at: at,
        );
    // Só o que já tem id real pode ser reenviado depois
    if (sync == null || !sync.isActive || !isUuid(taskId)) {
      await write();
      return true;
    }
    return sync.runOrQueue(
      OfflineActionType.setTaskCompleted,
      () => {
        'id': taskId,
        'completed': completed,
        'completedBy': completedByMemberId,
        'at': at.toIso8601String(),
      },
      write,
    );
  }

  @override
  Future<bool> deleteTask(String taskId) async {
    final sync = _offlineSync;
    // Só o que já tem id real pode ser reenviado depois; excluir de novo não muda nada
    if (sync == null || !sync.isActive || !isUuid(taskId)) {
      await _dataSource.deleteTask(taskId);
      return true;
    }
    return sync.runOrQueue(
      OfflineActionType.deleteTask,
      () => {'id': taskId},
      () => _dataSource.deleteTask(taskId),
    );
  }

  @override
  Future<void> updateTask(TaskItem task) async {
    final sync = _offlineSync;
    // Só o que já tem id real pode ser reenviado depois
    if (sync == null || !sync.isActive || !isUuid(task.id)) {
      return _dataSource.updateTask(task);
    }
    await sync.runOrQueue(
      OfflineActionType.updateTask,
      () => taskItemToJson(task),
      () => _dataSource.updateTask(task),
    );
  }
}
