import '../../../../core/domain/enums/recurrence.dart';
import '../entities/calendar_event.dart';
import '../entities/event_participant.dart';
import '../entities/task_item.dart';

abstract class CalendarRepository {
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

  /// Altera título, descrição, prazo, responsável, prioridade e custo.
  Future<void> updateTask(TaskItem task);
  Future<void> toggleTaskComplete({
    required String taskId,
    required String completedByMemberId,
  });
  Future<void> deleteTask(String taskId);
}
