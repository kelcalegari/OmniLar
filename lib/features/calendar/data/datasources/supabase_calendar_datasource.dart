import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/domain/enums/recurrence.dart';
import '../../../../core/domain/value_objects/money.dart';
import '../../../../core/errors/failures.dart';
import '../../domain/entities/calendar_event.dart';
import '../../domain/entities/event_participant.dart';
import '../../domain/entities/task_item.dart';
import '../../domain/services/event_recurrence.dart';
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
      List<dynamic> rows;
      try {
        rows = await client
            .from('events')
            .select('*, event_participants(*)')
            .eq('house_id', _houseId)
            .order('start_time', ascending: true);
      } catch (innerError) {
        // Fallback defensivo: se houver erro ao carregar os participantes juntos, tenta carregar apenas os eventos
        rows = await client
            .from('events')
            .select('*')
            .eq('house_id', _houseId)
            .order('start_time', ascending: true);
      }

      final userIds = <String>{};
      for (final r in rows) {
        final rawParticipants = (r['event_participants'] as List<dynamic>? ?? []);
        for (final p in rawParticipants) {
          final uId = (p as Map<String, dynamic>)['user_id'] as String?;
          if (uId != null && uId.isNotEmpty) {
            userIds.add(uId);
          }
        }
      }

      final Map<String, String> profileNames = {};
      if (userIds.isNotEmpty) {
        try {
          final profiles = await client
              .from('profiles')
              .select('id, full_name')
              .filter('id', 'in', userIds.toList());
          for (final prof in profiles) {
            final id = prof['id'] as String?;
            final fullName = prof['full_name'] as String?;
            if (id != null && fullName != null && fullName.trim().isNotEmpty) {
              profileNames[id] = fullName.trim();
            }
          }
        } catch (_) {
          // Fallback resiliente
        }
      }

      return rows.map((r) {
        final rawParticipants = (r['event_participants'] as List<dynamic>? ?? []);
        final participants = rawParticipants.map((p) {
          final pMap = p as Map<String, dynamic>;
          final isEssential = (pMap['is_essential'] as bool?) ?? false;
          final statusStr = pMap['rsvp_status'] as String? ?? 'pending';
          final respondedAtStr = pMap['responded_at'] as String?;
          final userId = pMap['user_id'] as String;

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
            memberId: userId,
            memberName: profileNames[userId] ?? 'Membro',
            role: isEssential ? ParticipantRole.required : ParticipantRole.optional,
            rsvpStatus: rsvpStatus,
            respondedAt: respondedAtStr != null ? DateTime.tryParse(respondedAtStr)?.toLocal() : null,
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
          startTime: DateTime.parse(r['start_time'] as String).toLocal(),
          endTime: DateTime.parse(r['end_time'] as String).toLocal(),
          isAllDay: (r['is_all_day'] as bool?) ?? false,
          createdByMemberId: r['created_by'] as String? ?? '',
          visibility: visibility,
          participants: participants,
          recurrenceFrequency: RecurrenceFrequency.values.firstWhere(
            (frequency) => frequency.name == r['recurrence_frequency'],
            orElse: () => RecurrenceFrequency.none,
          ),
          seriesId: r['recurring_series_id'] as String?,
          recurrenceEndDate: r['recurrence_end_date'] != null
              ? DateTime.tryParse(r['recurrence_end_date'] as String)
              : null,
        );
      }).toList();
    } catch (e) {
      throw ServerFailure('Erro ao carregar eventos da agenda: $e');
    }
  }

  List<Map<String, dynamic>> _participantRows(
    String eventId,
    String houseId,
    List<EventParticipant> participants,
  ) => [
    for (final p in participants)
      if (_isUuid(p.memberId))
        {
          'event_id': eventId,
          'user_id': p.memberId,
          'house_id': houseId,
          'is_essential': p.isEssential,
          'rsvp_status': p.rsvpStatus.name,
          'responded_at': p.respondedAt?.toUtc().toIso8601String(),
        },
  ];

  Future<void> _upsertParticipants(
    String eventId,
    List<EventParticipant> participants,
  ) async {
    final rows = _participantRows(eventId, _houseId, participants);
    if (rows.isEmpty) return;
    await client
        .from('event_participants')
        .upsert(rows, onConflict: 'event_id,user_id');
  }

  @override
  Future<void> addEvent(CalendarEvent event) async {
    try {
      final currentUserId = client.auth.currentUser?.id;
      final houseId = _houseId;

      if (!_isUuid(houseId)) {
        throw const ServerFailure('Casa não configurada ou ID inválido.');
      }

      final creatorId = (currentUserId != null && _isUuid(currentUserId))
          ? currentUserId
          : (_isUuid(event.createdByMemberId) ? event.createdByMemberId : currentUserId);

      if (creatorId == null) {
        throw const ServerFailure('Usuário não autenticado.');
      }

      // Evento, ocorrências da série e participantes entram juntos: ou tudo, ou
      // nada. Num evento recorrente a primeira ocorrência identifica a série e
      // as próximas são eventos próprios, para poderem ser editadas uma a uma.
      final duration = event.endTime.difference(event.startTime);
      final isRecurring = event.recurrenceFrequency != RecurrenceFrequency.none;
      await client.rpc('create_calendar_event', params: {
        'p_plan': {
          'event': {
            if (_isUuid(event.id)) 'id': event.id,
            'house_id': houseId,
            'title': event.title,
            'description': event.description,
            'location': event.location,
            'start_time': event.startTime.toUtc().toIso8601String(),
            'end_time': event.endTime.toUtc().toIso8601String(),
            'is_all_day': event.isAllDay,
            'visibility': event.visibility.name,
            'recurrence_frequency': event.recurrenceFrequency.name,
            if (isRecurring && event.recurrenceEndDate != null)
              'recurrence_end_date': event.recurrenceEndDate!.toIso8601String().split('T')[0],
          },
          'occurrences': [
            if (isRecurring)
              for (final start in futureOccurrenceStarts(event))
                {
                  'start_time': start.toUtc().toIso8601String(),
                  'end_time': start.add(duration).toUtc().toIso8601String(),
                },
          ],
          'participants': [
            for (final p in event.participants)
              if (_isUuid(p.memberId))
                {
                  'user_id': p.memberId,
                  'is_essential': p.isEssential,
                  'rsvp_status': p.rsvpStatus.name,
                  'responded_at': p.respondedAt?.toUtc().toIso8601String(),
                },
          ],
        },
      });
    } catch (e) {
      if (e is Failure) rethrow;
      throw ServerFailure('Erro ao adicionar evento na agenda: $e');
    }
  }

  @override
  Future<void> updateEvent(
    CalendarEvent event, {
    RecurrenceScope scope = RecurrenceScope.thisInstanceOnly,
  }) async {
    try {
      final current = await client
          .from('events')
          .select('recurring_series_id, start_time')
          .eq('id', event.id)
          .maybeSingle();
      final seriesId = current?['recurring_series_id'] as String?;

      final sharedFields = <String, dynamic>{
        'title': event.title,
        'description': event.description,
        'location': event.location,
        'is_all_day': event.isAllDay,
        'visibility': event.visibility.name,
      };

      if (seriesId == null || scope == RecurrenceScope.thisInstanceOnly) {
        await client.from('events').update({
          ...sharedFields,
          'start_time': event.startTime.toUtc().toIso8601String(),
          'end_time': event.endTime.toUtc().toIso8601String(),
          // Editada sozinha, a ocorrência deixa de fazer parte da série
          if (seriesId != null) ...{
            'recurring_series_id': null,
            'recurrence_frequency': RecurrenceFrequency.none.name,
          },
        }).eq('id', event.id);
        await _upsertParticipants(event.id, event.participants);
        return;
      }

      var seriesQuery = client
          .from('events')
          .select('id, start_time, end_time')
          .eq('recurring_series_id', seriesId);
      if (scope == RecurrenceScope.thisAndFuture) {
        seriesQuery = seriesQuery.gte('start_time', current!['start_time'] as String);
      }

      // Cada ocorrência mantém o seu dia e a sua duração; muda só o horário
      for (final row in await seriesQuery) {
        final oldStart = DateTime.parse(row['start_time'] as String).toLocal();
        final oldEnd = DateTime.parse(row['end_time'] as String).toLocal();
        final newStart = DateTime(
          oldStart.year,
          oldStart.month,
          oldStart.day,
          event.startTime.hour,
          event.startTime.minute,
        );

        await client.from('events').update({
          ...sharedFields,
          'start_time': newStart.toUtc().toIso8601String(),
          'end_time': newStart.add(oldEnd.difference(oldStart)).toUtc().toIso8601String(),
        }).eq('id', row['id'] as String);
        await _upsertParticipants(row['id'] as String, event.participants);
      }
    } catch (e) {
      if (e is Failure) rethrow;
      throw ServerFailure('Erro ao atualizar evento da agenda: $e');
    }
  }

  @override
  Future<void> deleteEvent(
    String eventId, {
    RecurrenceScope scope = RecurrenceScope.thisInstanceOnly,
  }) async {
    try {
      if (scope != RecurrenceScope.thisInstanceOnly) {
        final current = await client
            .from('events')
            .select('recurring_series_id, start_time')
            .eq('id', eventId)
            .maybeSingle();
        final seriesId = current?['recurring_series_id'] as String?;

        if (seriesId != null) {
          var deletion = client
              .from('events')
              .delete()
              .eq('recurring_series_id', seriesId);
          if (scope == RecurrenceScope.thisAndFuture) {
            deletion = deletion.gte('start_time', current!['start_time'] as String);
          }
          await deletion;
          return;
        }
      }

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
            'responded_at': DateTime.now().toUtc().toIso8601String(),
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
  Future<List<TaskItem>> getTasks({bool includeArchived = false}) async {
    try {
      var query = client
          .from('tasks')
          .select()
          .eq('house_id', _houseId);

      if (!includeArchived) {
        final cutoff = DateTime.now().subtract(const Duration(days: 15)).toUtc().toIso8601String();
        query = query.or('is_completed.eq.false,completed_at.gte.$cutoff');
      }

      final rows = await query.order('created_at', ascending: false);

      final userIds = <String>{};
      for (final r in rows) {
        final assigned = r['assigned_to'] as String?;
        if (assigned != null && assigned.isNotEmpty) {
          userIds.add(assigned);
        }
      }

      final Map<String, String> profileNames = {};
      if (userIds.isNotEmpty) {
        try {
          final profiles = await client
              .from('profiles')
              .select('id, full_name')
              .filter('id', 'in', userIds.toList());
          for (final prof in profiles) {
            final id = prof['id'] as String?;
            final fullName = prof['full_name'] as String?;
            if (id != null && fullName != null && fullName.trim().isNotEmpty) {
              profileNames[id] = fullName.trim();
            }
          }
        } catch (_) {
          // Fallback resiliente
        }
      }

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
        final assignedTo = r['assigned_to'] as String?;

        return TaskItem(
          id: r['id'] as String,
          title: r['title'] as String,
          description: r['description'] as String?,
          dueDate: r['due_date'] != null ? DateTime.tryParse(r['due_date'] as String) : null,
          assignedToMemberId: assignedTo,
          assignedToMemberName: assignedTo != null ? profileNames[assignedTo] : null,
          isCompleted: (r['is_completed'] as bool?) ?? false,
          completedAt: r['completed_at'] != null ? DateTime.tryParse(r['completed_at'] as String)?.toLocal() : null,
          completedByMemberId: r['completed_by'] as String?,
          priority: priority,
          cost: costCents != null ? Money(costCents) : null,
          createdByMemberId: r['created_by'] as String? ?? '',
          createdAt: DateTime.parse(r['created_at'] as String).toLocal(),
        );
      }).toList();
    } catch (e) {
      throw ServerFailure('Erro ao carregar tarefas: $e');
    }
  }

  @override
  Stream<List<TaskItem>> watchTasks({bool includeArchived = false}) {
    return client
        .from('tasks')
        .stream(primaryKey: ['id'])
        .eq('house_id', _houseId)
        .order('created_at', ascending: false)
        .map((rows) {
          final cutoff = DateTime.now().subtract(const Duration(days: 15));
          return rows.where((r) {
            if (includeArchived) return true;
            final isCompleted = (r['is_completed'] as bool?) ?? false;
            if (!isCompleted) return true;
            final completedAtStr = r['completed_at'] as String?;
            final completedAt = completedAtStr != null ? DateTime.tryParse(completedAtStr) : null;
            return completedAt != null && completedAt.isAfter(cutoff);
          }).map((r) {
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
            final assignedTo = r['assigned_to'] as String?;

            return TaskItem(
              id: r['id'] as String,
              title: r['title'] as String,
              description: r['description'] as String?,
              dueDate: r['due_date'] != null ? DateTime.tryParse(r['due_date'] as String) : null,
              assignedToMemberId: assignedTo,
              isCompleted: (r['is_completed'] as bool?) ?? false,
              completedAt: r['completed_at'] != null ? DateTime.tryParse(r['completed_at'] as String)?.toLocal() : null,
              completedByMemberId: r['completed_by'] as String?,
              priority: priority,
              cost: costCents != null ? Money(costCents) : null,
              createdByMemberId: r['created_by'] as String? ?? '',
              createdAt: DateTime.tryParse(r['created_at'] as String? ?? '')?.toLocal() ?? DateTime.now(),
            );
          }).toList();
        });
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
  Future<void> updateTask(TaskItem task) async {
    try {
      await client.from('tasks').update({
        'title': task.title,
        'description': task.description,
        'due_date': task.dueDate?.toIso8601String().split('T')[0],
        'assigned_to': task.assignedToMemberId,
        'priority': task.priority.name,
        'cost_cents': task.cost?.cents,
      }).eq('id', task.id);
    } catch (e) {
      throw ServerFailure('Erro ao atualizar tarefa: $e');
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
        'completed_at': isDone ? DateTime.now().toUtc().toIso8601String() : null,
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
