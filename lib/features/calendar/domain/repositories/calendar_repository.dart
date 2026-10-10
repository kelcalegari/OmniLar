import '../entities/calendar_event.dart';
import '../entities/event_participant.dart';
import '../entities/task_item.dart';

abstract class CalendarRepository {
  Future<List<CalendarEvent>> getEvents();
  Future<void> addEvent(CalendarEvent event);
  Future<void> updateRsvp({
    required String eventId,
    required String memberId,
    required RsvpStatus status,
  });
  Future<void> cancelEvent(String eventId);

  Future<List<TaskItem>> getTasks();
  Future<void> addTask(TaskItem task);
  Future<void> toggleTaskComplete({
    required String taskId,
    required String completedByMemberId,
  });
  Future<void> deleteTask(String taskId);
}
