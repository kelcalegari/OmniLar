import '../../../../core/domain/enums/recurrence.dart';
import '../../domain/entities/calendar_event.dart';
import '../../domain/entities/event_participant.dart';
import '../../domain/entities/task_item.dart';

abstract class CalendarDataSource {
  Future<List<CalendarEvent>> getEvents();
  Future<void> addEvent(CalendarEvent event);
  Future<void> updateEvent(
    CalendarEvent event, {
    RecurrenceScope scope = RecurrenceScope.thisInstanceOnly,
  });
  Future<void> deleteEvent(
    String eventId, {
    RecurrenceScope scope = RecurrenceScope.thisInstanceOnly,
  });
  Future<void> updateRsvp({
    required String eventId,
    required String memberId,
    required RsvpStatus status,
  });
  Future<void> cancelEvent(String eventId);
  Future<List<TaskItem>> getTasks({bool includeArchived = false});
  Stream<List<TaskItem>> watchTasks({bool includeArchived = false});
  Future<void> addTask(TaskItem task);
  Future<void> toggleTaskComplete({
    required String taskId,
    required String completedByMemberId,
  });
  Future<void> deleteTask(String taskId);
}
