import '../../../../core/domain/enums/recurrence.dart';
import '../../domain/entities/calendar_event.dart';
import '../../domain/entities/event_participant.dart';
import '../../domain/entities/task_item.dart';
import '../../domain/repositories/calendar_repository.dart';
import '../datasources/calendar_datasource.dart';

class CalendarRepositoryImpl implements CalendarRepository {
  final CalendarDataSource _dataSource;

  CalendarRepositoryImpl(this._dataSource);

  @override
  Future<List<CalendarEvent>> getEvents() => _dataSource.getEvents();

  @override
  Future<void> addEvent(CalendarEvent event) => _dataSource.addEvent(event);

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
  Future<List<TaskItem>> getTasks() => _dataSource.getTasks();

  @override
  Future<void> addTask(TaskItem task) => _dataSource.addTask(task);

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
  Future<void> deleteTask(String taskId) => _dataSource.deleteTask(taskId);
}
