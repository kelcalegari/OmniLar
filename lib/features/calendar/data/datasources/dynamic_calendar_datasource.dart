import '../../../../core/domain/enums/recurrence.dart';
import '../../domain/entities/calendar_event.dart';
import '../../domain/entities/event_participant.dart';
import '../../domain/entities/task_item.dart';
import 'calendar_datasource.dart';

class DynamicCalendarDataSource implements CalendarDataSource {
  final CalendarDataSource remote;
  final CalendarDataSource mock;
  final bool Function() isDemoMode;

  DynamicCalendarDataSource({
    required this.remote,
    required this.mock,
    required this.isDemoMode,
  });

  CalendarDataSource get _active => isDemoMode() ? mock : remote;

  @override
  Future<List<CalendarEvent>> getEvents() => _active.getEvents();

  @override
  Future<void> addEvent(CalendarEvent event) => _active.addEvent(event);

  @override
  Future<void> updateEvent(
    CalendarEvent event, {
    RecurrenceScope scope = RecurrenceScope.thisInstanceOnly,
  }) =>
      _active.updateEvent(event, scope: scope);

  @override
  Future<void> deleteEvent(
    String eventId, {
    RecurrenceScope scope = RecurrenceScope.thisInstanceOnly,
  }) =>
      _active.deleteEvent(eventId, scope: scope);

  @override
  Future<void> updateRsvp({
    required String eventId,
    required String memberId,
    required RsvpStatus status,
  }) =>
      _active.updateRsvp(
        eventId: eventId,
        memberId: memberId,
        status: status,
      );

  @override
  Future<void> cancelEvent(String eventId) => _active.cancelEvent(eventId);

  @override
  Future<List<TaskItem>> getTasks({bool includeArchived = false}) =>
      _active.getTasks(includeArchived: includeArchived);

  @override
  Stream<List<TaskItem>> watchTasks({bool includeArchived = false}) =>
      _active.watchTasks(includeArchived: includeArchived);

  @override
  Future<void> addTask(TaskItem task) => _active.addTask(task);

  @override
  Future<void> updateTask(TaskItem task) => _active.updateTask(task);

  @override
  Future<void> toggleTaskComplete({
    required String taskId,
    required String completedByMemberId,
  }) =>
      _active.toggleTaskComplete(
        taskId: taskId,
        completedByMemberId: completedByMemberId,
      );

  @override
  Future<void> setTaskCompleted({
    required String taskId,
    required bool completed,
    required String completedByMemberId,
    DateTime? at,
  }) =>
      _active.setTaskCompleted(
        taskId: taskId,
        completed: completed,
        completedByMemberId: completedByMemberId,
        at: at,
      );

  @override
  Future<void> deleteTask(String taskId) => _active.deleteTask(taskId);
}
