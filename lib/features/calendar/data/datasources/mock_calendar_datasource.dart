import '../../../../core/domain/value_objects/money.dart';
import '../../../../core/domain/enums/recurrence.dart';
import '../../domain/entities/calendar_event.dart';
import '../../domain/entities/event_participant.dart';
import '../../domain/entities/task_item.dart';
import 'calendar_datasource.dart';

class MockCalendarDataSource implements CalendarDataSource {
  final List<CalendarEvent> _events = [
    CalendarEvent(
      id: 'event_1',
      title: 'Jantar de Aniversário de Carlos',
      description: 'Restaurante italiano no centro da cidade',
      location: 'Cantina do Gigi',
      startTime: DateTime.now().add(const Duration(days: 2, hours: 4)),
      endTime: DateTime.now().add(const Duration(days: 2, hours: 7)),
      createdByMemberId: 'member_carlos',
      participants: const [
        EventParticipant(
          id: 'part_1_1',
          eventId: 'event_1',
          memberId: 'member_carlos',
          memberName: 'Carlos',
          role: ParticipantRole.required,
          rsvpStatus: RsvpStatus.accepted,
        ),
        EventParticipant(
          id: 'part_1_2',
          eventId: 'event_1',
          memberId: 'member_marina',
          memberName: 'Marina',
          role: ParticipantRole.required,
          rsvpStatus: RsvpStatus.accepted,
        ),
      ],
    ),
    CalendarEvent(
      id: 'event_2',
      title: 'Dedetização do Apartamento',
      description: 'Precisa esvaziar armários e sair por 4 horas',
      location: 'Em Casa',
      startTime: DateTime.now().add(const Duration(days: 4, hours: 2)),
      endTime: DateTime.now().add(const Duration(days: 4, hours: 6)),
      createdByMemberId: 'member_marina',
      participants: const [
        EventParticipant(
          id: 'part_2_1',
          eventId: 'event_2',
          memberId: 'member_marina',
          memberName: 'Marina',
          role: ParticipantRole.required,
          rsvpStatus: RsvpStatus.accepted,
        ),
        EventParticipant(
          id: 'part_2_2',
          eventId: 'event_2',
          memberId: 'member_carlos',
          memberName: 'Carlos',
          role: ParticipantRole.required,
          rsvpStatus: RsvpStatus.pending, // Aguardando resposta do Carlos
        ),
      ],
    ),
    CalendarEvent(
      id: 'event_3',
      title: 'Visita do Técnico da Internet',
      description: 'Troca de modem de fibra óptica',
      location: 'Em Casa',
      startTime: DateTime.now().add(const Duration(days: 6, hours: 1)),
      endTime: DateTime.now().add(const Duration(days: 6, hours: 3)),
      createdByMemberId: 'member_marina',
      participants: const [
        EventParticipant(
          id: 'part_3_1',
          eventId: 'event_3',
          memberId: 'member_marina',
          memberName: 'Marina',
          role: ParticipantRole.required,
          rsvpStatus: RsvpStatus.accepted,
        ),
        EventParticipant(
          id: 'part_3_2',
          eventId: 'event_3',
          memberId: 'member_carlos',
          memberName: 'Carlos',
          role: ParticipantRole.required,
          rsvpStatus: RsvpStatus.declined, // Carlos recusou devido a plantão
        ),
      ],
    ),
  ];

  final List<TaskItem> _tasks = [
    TaskItem(
      id: 'task_1',
      title: 'Comprar botijão de gás',
      description: 'Pedir pelo app com entrega até as 18h',
      dueDate: DateTime.now(),
      assignedToMemberId: 'member_marina',
      assignedToMemberName: 'Marina',
      isCompleted: false,
      priority: TaskPriority.high,
      cost: const Money(12000), // R$ 120,00
      createdByMemberId: 'member_marina',
      createdAt: DateTime.now().subtract(const Duration(days: 1)),
    ),
    TaskItem(
      id: 'task_2',
      title: 'Lavar tapetes da sala',
      description: 'Levar na lavanderia express ou lavar no quintal',
      dueDate: DateTime.now().add(const Duration(days: 2)),
      assignedToMemberId: 'member_carlos',
      assignedToMemberName: 'Carlos',
      isCompleted: false,
      priority: TaskPriority.medium,
      createdByMemberId: 'member_carlos',
      createdAt: DateTime.now().subtract(const Duration(days: 2)),
    ),
    TaskItem(
      id: 'task_3',
      title: 'Trocar lâmpada do corredor',
      description: 'Lâmpada LED amarela',
      dueDate: DateTime.now().subtract(const Duration(days: 1)),
      assignedToMemberId: 'member_carlos',
      assignedToMemberName: 'Carlos',
      isCompleted: true,
      completedAt: DateTime.now().subtract(const Duration(hours: 12)),
      completedByMemberId: 'member_carlos',
      priority: TaskPriority.low,
      cost: const Money(2200), // R$ 22,00
      createdByMemberId: 'member_marina',
      createdAt: DateTime.now().subtract(const Duration(days: 3)),
    ),
  ];

  @override
  Future<List<CalendarEvent>> getEvents() async => List.unmodifiable(_events);

  @override
  Future<void> addEvent(CalendarEvent event) async {
    if (event.recurrenceFrequency == RecurrenceFrequency.none) {
      _events.insert(0, event);
      return;
    }

    final seriesId = event.seriesId ?? 'series_${DateTime.now().millisecondsSinceEpoch}_${event.id}';
    final masterEvent = event.copyWith(seriesId: seriesId);
    _events.insert(0, masterEvent);

    int count = 0;
    switch (event.recurrenceFrequency) {
      case RecurrenceFrequency.daily:
        count = 14;
        break;
      case RecurrenceFrequency.weekly:
        count = 8;
        break;
      case RecurrenceFrequency.biweekly:
        count = 4;
        break;
      case RecurrenceFrequency.monthly:
        count = 6;
        break;
      case RecurrenceFrequency.yearly:
        count = 2;
        break;
      case RecurrenceFrequency.none:
        count = 0;
        break;
    }

    final duration = event.endTime.difference(event.startTime);

    for (int i = 1; i <= count; i++) {
      DateTime nextStart;
      switch (event.recurrenceFrequency) {
        case RecurrenceFrequency.daily:
          nextStart = event.startTime.add(Duration(days: i));
          break;
        case RecurrenceFrequency.weekly:
          nextStart = event.startTime.add(Duration(days: 7 * i));
          break;
        case RecurrenceFrequency.biweekly:
          nextStart = event.startTime.add(Duration(days: 14 * i));
          break;
        case RecurrenceFrequency.monthly:
          nextStart = DateTime(
            event.startTime.year,
            event.startTime.month + i,
            event.startTime.day,
            event.startTime.hour,
            event.startTime.minute,
          );
          break;
        case RecurrenceFrequency.yearly:
          nextStart = DateTime(
            event.startTime.year + i,
            event.startTime.month,
            event.startTime.day,
            event.startTime.hour,
            event.startTime.minute,
          );
          break;
        case RecurrenceFrequency.none:
          nextStart = event.startTime;
          break;
      }

      if (event.recurrenceEndDate != null && nextStart.isAfter(event.recurrenceEndDate!)) {
        break;
      }

      final instance = event.copyWith(
        id: '${seriesId}_instance_$i',
        seriesId: seriesId,
        startTime: nextStart,
        endTime: nextStart.add(duration),
      );
      _events.add(instance);
    }
  }

  @override
  Future<void> updateEvent(
    CalendarEvent event, {
    RecurrenceScope scope = RecurrenceScope.thisInstanceOnly,
  }) async {
    final index = _events.indexWhere((e) => e.id == event.id);
    if (index == -1) return;
    final current = _events[index];

    switch (scope) {
      case RecurrenceScope.thisInstanceOnly:
        _events[index] = event.copyWith(
          clearSeriesId: current.seriesId != null,
          recurrenceFrequency: RecurrenceFrequency.none,
          isRecurringException: current.seriesId != null,
        );
        break;

      case RecurrenceScope.thisAndFuture:
        if (current.seriesId != null) {
          final targetSeriesId = current.seriesId!;
          final fromTime = current.startTime;
          for (int i = 0; i < _events.length; i++) {
            final e = _events[i];
            if (e.seriesId == targetSeriesId && !e.startTime.isBefore(fromTime)) {
              final duration = e.endTime.difference(e.startTime);
              final newStartTime = DateTime(
                e.startTime.year,
                e.startTime.month,
                e.startTime.day,
                event.startTime.hour,
                event.startTime.minute,
              );
              _events[i] = e.copyWith(
                title: event.title,
                description: event.description,
                location: event.location,
                startTime: newStartTime,
                endTime: newStartTime.add(duration),
                isAllDay: event.isAllDay,
                visibility: event.visibility,
                participants: event.participants,
              );
            }
          }
        } else {
          _events[index] = event;
        }
        break;

      case RecurrenceScope.allInstances:
        if (current.seriesId != null) {
          final targetSeriesId = current.seriesId!;
          for (int i = 0; i < _events.length; i++) {
            final e = _events[i];
            if (e.seriesId == targetSeriesId) {
              final duration = e.endTime.difference(e.startTime);
              final newStartTime = DateTime(
                e.startTime.year,
                e.startTime.month,
                e.startTime.day,
                event.startTime.hour,
                event.startTime.minute,
              );
              _events[i] = e.copyWith(
                title: event.title,
                description: event.description,
                location: event.location,
                startTime: newStartTime,
                endTime: newStartTime.add(duration),
                isAllDay: event.isAllDay,
                visibility: event.visibility,
                participants: event.participants,
              );
            }
          }
        } else {
          _events[index] = event;
        }
        break;
    }
  }

  @override
  Future<void> deleteEvent(
    String eventId, {
    RecurrenceScope scope = RecurrenceScope.thisInstanceOnly,
  }) async {
    final index = _events.indexWhere((e) => e.id == eventId);
    if (index == -1) return;
    final current = _events[index];

    switch (scope) {
      case RecurrenceScope.thisInstanceOnly:
        _events.removeAt(index);
        break;

      case RecurrenceScope.thisAndFuture:
        if (current.seriesId != null) {
          final targetSeriesId = current.seriesId!;
          final fromTime = current.startTime;
          _events.removeWhere((e) => e.seriesId == targetSeriesId && !e.startTime.isBefore(fromTime));
        } else {
          _events.removeAt(index);
        }
        break;

      case RecurrenceScope.allInstances:
        if (current.seriesId != null) {
          final targetSeriesId = current.seriesId!;
          _events.removeWhere((e) => e.seriesId == targetSeriesId);
        } else {
          _events.removeAt(index);
        }
        break;
    }
  }

  @override
  Future<void> updateRsvp({
    required String eventId,
    required String memberId,
    required RsvpStatus status,
  }) async {
    final eventIndex = _events.indexWhere((e) => e.id == eventId);
    if (eventIndex == -1) return;

    final event = _events[eventIndex];
    final updatedParticipants = event.participants.map((p) {
      if (p.memberId == memberId) {
        return p.copyWith(
          rsvpStatus: status,
          respondedAt: DateTime.now(),
        );
      }
      return p;
    }).toList();

    _events[eventIndex] = event.copyWith(participants: updatedParticipants);
  }

  @override
  Future<void> cancelEvent(String eventId) async {
    final eventIndex = _events.indexWhere((e) => e.id == eventId);
    if (eventIndex != -1) {
      _events[eventIndex] = _events[eventIndex].copyWith(isCancelled: true);
    }
  }

  @override
  Future<List<TaskItem>> getTasks() async => List.unmodifiable(_tasks);

  @override
  Future<void> addTask(TaskItem task) async {
    _tasks.insert(0, task);
  }

  @override
  Future<void> toggleTaskComplete({
    required String taskId,
    required String completedByMemberId,
  }) async {
    final taskIndex = _tasks.indexWhere((t) => t.id == taskId);
    if (taskIndex == -1) return;

    final task = _tasks[taskIndex];
    final isDone = !task.isCompleted;

    _tasks[taskIndex] = task.copyWith(
      isCompleted: isDone,
      completedAt: isDone ? DateTime.now() : null,
      completedByMemberId: isDone ? completedByMemberId : null,
    );
  }

  @override
  Future<void> deleteTask(String taskId) async {
    _tasks.removeWhere((t) => t.id == taskId);
  }
}
