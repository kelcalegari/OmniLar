import '../../../../core/domain/enums/recurrence.dart';
import '../../../../core/domain/value_objects/money.dart';
import '../../domain/entities/calendar_event.dart';
import '../../domain/entities/event_participant.dart';
import '../../domain/entities/task_item.dart';

/// Serialização de eventos e tarefas para a fila offline.

T _enumByName<T extends Enum>(List<T> values, Object? name, T fallback) =>
    values.firstWhere((v) => v.name == name, orElse: () => fallback);

Map<String, dynamic> calendarEventToJson(CalendarEvent event) => {
  'id': event.id,
  'title': event.title,
  'description': event.description,
  'location': event.location,
  'startTime': event.startTime.toIso8601String(),
  'endTime': event.endTime.toIso8601String(),
  'isAllDay': event.isAllDay,
  'createdByMemberId': event.createdByMemberId,
  'visibility': event.visibility.name,
  'recurrenceFrequency': event.recurrenceFrequency.name,
  'recurrenceEndDate': event.recurrenceEndDate?.toIso8601String(),
  'participants': [
    for (final p in event.participants)
      {
        'id': p.id,
        'eventId': p.eventId,
        'memberId': p.memberId,
        'memberName': p.memberName,
        'role': p.role.name,
        'rsvpStatus': p.rsvpStatus.name,
        'respondedAt': p.respondedAt?.toIso8601String(),
      },
  ],
};

CalendarEvent calendarEventFromJson(Map<String, dynamic> json) => CalendarEvent(
  id: json['id'] as String,
  title: json['title'] as String,
  description: json['description'] as String?,
  location: json['location'] as String?,
  startTime: DateTime.parse(json['startTime'] as String),
  endTime: DateTime.parse(json['endTime'] as String),
  isAllDay: json['isAllDay'] as bool? ?? false,
  createdByMemberId: json['createdByMemberId'] as String,
  visibility: _enumByName(EventVisibility.values, json['visibility'], EventVisibility.house),
  recurrenceFrequency: _enumByName(
    RecurrenceFrequency.values,
    json['recurrenceFrequency'],
    RecurrenceFrequency.none,
  ),
  recurrenceEndDate: json['recurrenceEndDate'] != null
      ? DateTime.parse(json['recurrenceEndDate'] as String)
      : null,
  participants: [
    for (final raw in (json['participants'] as List? ?? const []))
      EventParticipant(
        id: (raw as Map)['id'] as String,
        eventId: raw['eventId'] as String,
        memberId: raw['memberId'] as String,
        memberName: raw['memberName'] as String? ?? 'Membro',
        role: _enumByName(ParticipantRole.values, raw['role'], ParticipantRole.required),
        rsvpStatus: _enumByName(RsvpStatus.values, raw['rsvpStatus'], RsvpStatus.pending),
        respondedAt: raw['respondedAt'] != null
            ? DateTime.parse(raw['respondedAt'] as String)
            : null,
      ),
  ],
);

Map<String, dynamic> taskItemToJson(TaskItem task) => {
  'id': task.id,
  'title': task.title,
  'description': task.description,
  'dueDate': task.dueDate?.toIso8601String(),
  'assignedToMemberId': task.assignedToMemberId,
  'assignedToMemberName': task.assignedToMemberName,
  'isCompleted': task.isCompleted,
  'completedAt': task.completedAt?.toIso8601String(),
  'completedByMemberId': task.completedByMemberId,
  'priority': task.priority.name,
  'costCents': task.cost?.cents,
  'createdByMemberId': task.createdByMemberId,
  'createdAt': task.createdAt.toIso8601String(),
};

TaskItem taskItemFromJson(Map<String, dynamic> json) => TaskItem(
  id: json['id'] as String,
  title: json['title'] as String,
  description: json['description'] as String?,
  dueDate: json['dueDate'] != null ? DateTime.parse(json['dueDate'] as String) : null,
  assignedToMemberId: json['assignedToMemberId'] as String?,
  assignedToMemberName: json['assignedToMemberName'] as String?,
  isCompleted: json['isCompleted'] as bool? ?? false,
  completedAt: json['completedAt'] != null ? DateTime.parse(json['completedAt'] as String) : null,
  completedByMemberId: json['completedByMemberId'] as String?,
  priority: _enumByName(TaskPriority.values, json['priority'], TaskPriority.medium),
  cost: json['costCents'] != null ? Money((json['costCents'] as num).toInt()) : null,
  createdByMemberId: json['createdByMemberId'] as String,
  createdAt: DateTime.parse(json['createdAt'] as String),
);
