import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/domain/enums/recurrence.dart';
import '../../../../core/domain/value_objects/money.dart';
import '../../../../core/errors/failures.dart';
import '../../domain/entities/calendar_event.dart';
import '../../domain/entities/event_participant.dart';
import '../../domain/entities/task_item.dart';
import 'calendar_datasource.dart';

class SupabaseCalendarDataSource implements CalendarDataSource {
  final SupabaseClient client;
  final String Function() getCurrentHouseId;

  SupabaseCalendarDataSource({
    required this.client,
    required this.getCurrentHouseId,
  });

  String get _houseId => getCurrentHouseId();

  bool _isUuid(String id) {
    final uuidRegex = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    );
    return uuidRegex.hasMatch(id);
  }

  @override
  Future<List<CalendarEvent>> getEvents() async {
    try {
      final rows = await client
          .from('events')
          .select('*, event_participants(*)')
          .eq('house_id', _houseId)
          .order('start_time', ascending: true);

      return rows.map((r) {
        final rawParticipants = (r['event_participants'] as List<dynamic>? ?? []);
        final participants = rawParticipants.map((p) {
          final pMap = p as Map<String, dynamic>;
          final isEssential = (pMap['is_essential'] as bool?) ?? false;
          final statusStr = pMap['rsvp_status'] as String? ?? 'pending';
          final respondedAtStr = pMap['responded_at'] as String?;

          RsvpStatus rsvpStatus;
          switch (statusStr) {
            case 'accepted':
              rsvpStatus = RsvpStatus.accepted;
              break;
            case 'declined':
              rsvpStatus = RsvpStatus.declined;
              break;
            case 'tentative':
              rsvpStatus = RsvpStatus.tentative;
              break;
            default:
              rsvpStatus = RsvpStatus.pending;
          }

          return EventParticipant(
            id: pMap['id'] as String,
            eventId: pMap['event_id'] as String,
            memberId: pMap['user_id'] as String,
            memberName: 'Membro',
            role: isEssential ? ParticipantRole.required : ParticipantRole.optional,
            rsvpStatus: rsvpStatus,
            respondedAt: respondedAtStr != null ? DateTime.tryParse(respondedAtStr) : null,
          );
        }).toList();

        final visibilityStr = r['visibility'] as String? ?? 'house';
        EventVisibility visibility;
        switch (visibilityStr) {
          case 'restricted':
            visibility = EventVisibility.restricted;
            break;
          case 'private':
            visibility = EventVisibility.private;
            break;
          default:
            visibility = EventVisibility.house;
        }

        return CalendarEvent(
          id: r['id'] as String,
          title: r['title'] as String,
          description: r['description'] as String?,
          location: r['location'] as String?,
          startTime: DateTime.parse(r['start_time'] as String),
          endTime: DateTime.parse(r['end_time'] as String),
          isAllDay: (r['is_all_day'] as bool?) ?? false,
          createdByMemberId: r['created_by'] as String? ?? '',
          visibility: visibility,
          participants: participants,
        );
      }).toList();
    } catch (e) {
      throw ServerFailure('Erro ao carregar eventos da agenda: $e');
    }
  }

  @override
  Future<void> addEvent(CalendarEvent event) async {
    try {
      final currentUserId = client.auth.currentUser?.id;
      final eventRow = {
        if (_isUuid(event.id)) 'id': event.id,
        'house_id': _houseId,
        'title': event.title,
        'description': event.description,
        'location': event.location,
        'start_time': event.startTime.toIso8601String(),
        'end_time': event.endTime.toIso8601String(),
        'is_all_day': event.isAllDay,
        'visibility': event.visibility.name,
        'created_by': currentUserId ?? event.createdByMemberId,
      };

      final inserted = await client.from('events').insert(eventRow).select('id').single();
      final realEventId = inserted['id'] as String;

      if (event.participants.isNotEmpty) {
        final participantRows = event.participants.map((p) {
          return {
            if (_isUuid(p.id)) 'id': p.id,
            'event_id': realEventId,
            'user_id': p.memberId,
            'is_essential': p.isEssential,
            'rsvp_status': p.rsvpStatus.name,
            'responded_at': p.respondedAt?.toIso8601String(),
          };
        }).toList();

        await client.from('event_participants').insert(participantRows);
      }
    } catch (e) {
      throw ServerFailure('Erro ao adicionar evento na agenda: $e');
    }
  }

  @override
  Future<void> updateEvent(
    CalendarEvent event, {
    RecurrenceScope scope = RecurrenceScope.thisInstanceOnly,
  }) async {
    try {
      await client.from('events').update({
        'title': event.title,
        'description': event.description,
        'location': event.location,
        'start_time': event.startTime.toIso8601String(),
        'end_time': event.endTime.toIso8601String(),
        'is_all_day': event.isAllDay,
        'visibility': event.visibility.name,
      }).eq('id', event.id);
    } catch (e) {
      throw ServerFailure('Erro ao atualizar evento da agenda: $e');
    }
  }

  @override
  Future<void> deleteEvent(
    String eventId, {
    RecurrenceScope scope = RecurrenceScope.thisInstanceOnly,
  }) async {
    try {
      await client.from('events').delete().eq('id', eventId);
    } catch (e) {
      throw ServerFailure('Erro ao excluir evento da agenda: $e');
    }
  }

  @override
  Future<void> updateRsvp({
    required String eventId,
    required String memberId,
    required RsvpStatus status,
  }) async {
    try {
      await client
          .from('event_participants')
          .update({
            'rsvp_status': status.name,
            'responded_at': DateTime.now().toIso8601String(),
          })
          .eq('event_id', eventId)
          .eq('user_id', memberId);
    } catch (e) {
      throw ServerFailure('Erro ao responder RSVP: $e');
    }
  }

  @override
  Future<void> cancelEvent(String eventId) async {
    try {
      await client.from('events').delete().eq('id', eventId);
    } catch (e) {
      throw ServerFailure('Erro ao cancelar evento: $e');
    }
  }

  @override
  Future<List<TaskItem>> getTasks() async {
    try {
      final rows = await client
          .from('tasks')
          .select()
          .eq('house_id', _houseId)
          .order('created_at', ascending: false);

      return rows.map((r) {
        final priorityStr = r['priority'] as String? ?? 'medium';
        TaskPriority priority;
        switch (priorityStr) {
          case 'low':
            priority = TaskPriority.low;
            break;
          case 'high':
            priority = TaskPriority.high;
            break;
          default:
            priority = TaskPriority.medium;
        }

        final costCents = r['cost_cents'] as int?;

        return TaskItem(
          id: r['id'] as String,
          title: r['title'] as String,
          description: r['description'] as String?,
          dueDate: r['due_date'] != null ? DateTime.tryParse(r['due_date'] as String) : null,
          assignedToMemberId: r['assigned_to'] as String?,
          isCompleted: (r['is_completed'] as bool?) ?? false,
          completedAt: r['completed_at'] != null ? DateTime.tryParse(r['completed_at'] as String) : null,
          completedByMemberId: r['completed_by'] as String?,
          priority: priority,
          cost: costCents != null ? Money(costCents) : null,
          createdByMemberId: r['created_by'] as String? ?? '',
          createdAt: DateTime.parse(r['created_at'] as String),
        );
      }).toList();
    } catch (e) {
      throw ServerFailure('Erro ao carregar tarefas: $e');
    }
  }

  @override
  Future<void> addTask(TaskItem task) async {
    try {
      final currentUserId = client.auth.currentUser?.id;
      final taskRow = {
        if (_isUuid(task.id)) 'id': task.id,
        'house_id': _houseId,
        'title': task.title,
        'description': task.description,
        'due_date': task.dueDate?.toIso8601String().split('T')[0],
        'assigned_to': task.assignedToMemberId,
        'is_completed': task.isCompleted,
        'priority': task.priority.name,
        'cost_cents': task.cost?.cents,
        'created_by': currentUserId ?? task.createdByMemberId,
      };

      await client.from('tasks').insert(taskRow);
    } catch (e) {
      throw ServerFailure('Erro ao adicionar tarefa: $e');
    }
  }

  @override
  Future<void> toggleTaskComplete({
    required String taskId,
    required String completedByMemberId,
  }) async {
    try {
      final current = await client
          .from('tasks')
          .select('is_completed')
          .eq('id', taskId)
          .single();

      final isDone = !(current['is_completed'] as bool? ?? false);

      await client.from('tasks').update({
        'is_completed': isDone,
        'completed_at': isDone ? DateTime.now().toIso8601String() : null,
        'completed_by': isDone ? completedByMemberId : null,
      }).eq('id', taskId);
    } catch (e) {
      throw ServerFailure('Erro ao alternar status da tarefa: $e');
    }
  }

  @override
  Future<void> deleteTask(String taskId) async {
    try {
      await client.from('tasks').delete().eq('id', taskId);
    } catch (e) {
      throw ServerFailure('Erro ao excluir tarefa: $e');
    }
  }
}
