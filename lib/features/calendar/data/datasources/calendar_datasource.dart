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

  /// Altera título, descrição, prazo, responsável, prioridade e custo.
  Future<void> updateTask(TaskItem task);
  Future<void> toggleTaskComplete({
    required String taskId,
    required String completedByMemberId,
  });

  /// Conclui ou reabre a tarefa (pode ser repetido sem inverter de novo, por
  /// isso entra na fila offline). [at] é quando foi concluída.
  Future<void> setTaskCompleted({
    required String taskId,
    required bool completed,
    required String completedByMemberId,
    DateTime? at,
  });
  Future<void> deleteTask(String taskId);
}
