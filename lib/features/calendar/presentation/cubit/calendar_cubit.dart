import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/domain/enums/recurrence.dart';
import '../../domain/entities/calendar_event.dart';
import '../../domain/entities/event_participant.dart';
import '../../domain/entities/task_item.dart';
import '../../domain/repositories/calendar_repository.dart';
import '../../../auth/domain/repositories/auth_repository.dart';
import 'calendar_state.dart';

class CalendarCubit extends Cubit<CalendarState> {
  final CalendarRepository _repository;
  final AuthRepository? _authRepository;
  StreamSubscription<List<TaskItem>>? _tasksSubscription;

  CalendarCubit(this._repository, [this._authRepository])
      : super(CalendarState(
          activeMemberId: (_authRepository?.isDemoMode == true)
              ? (_authRepository?.currentUser?.id ?? 'member_carlos')
              : (_authRepository?.currentUser?.id ?? ''),
        ));

  void resetState() {
    _tasksSubscription?.cancel();
    _tasksSubscription = null;
    emit(CalendarState(
      activeMemberId: (_authRepository?.isDemoMode == true)
          ? (_authRepository?.currentUser?.id ?? 'member_carlos')
          : (_authRepository?.currentUser?.id ?? ''),
    ));
  }

  void _listenToTasks(bool includeArchived) {
    _tasksSubscription?.cancel();
    _tasksSubscription = _repository.watchTasks(includeArchived: includeArchived).listen(
      (tasks) async {
        if (isClosed) return;
        // A sincronização em tempo real traz só o id do responsável: o nome
        // vem do que já está carregado; se faltar algum, recarrega com os nomes.
        final names = {
          for (final t in state.tasks)
            if (t.assignedToMemberId != null && t.assignedToMemberName != null)
              t.assignedToMemberId!: t.assignedToMemberName!,
        };
        final named = [
          for (final t in tasks)
            t.assignedToMemberName == null && names.containsKey(t.assignedToMemberId)
                ? t.copyWith(assignedToMemberName: names[t.assignedToMemberId])
                : t,
        ];
        emit(state.copyWith(tasks: named));

        final missingName =
            named.any((t) => t.assignedToMemberId != null && t.assignedToMemberName == null);
        if (missingName) {
          try {
            final full = await _repository.getTasks(includeArchived: includeArchived);
            if (!isClosed) emit(state.copyWith(tasks: full));
          } catch (_) {}
        }
      },
      onError: (e) {
        debugPrint('Aviso: Sincronização em tempo real de tarefas indisponível: $e');
      },
    );
  }

  Future<void> loadCalendarData({bool? includeHistory}) async {
    emit(state.copyWith(status: CalendarCubitStatus.loading));
    try {
      final showHistory = includeHistory ?? state.isShowingHistory;
      final events = await _repository.getEvents();
      final tasks = await _repository.getTasks(includeArchived: showHistory);

      final currentUserId = _authRepository?.currentUser?.id;
      final isDemo = _authRepository?.isDemoMode ?? false;
      final String activeMember;
      if (isDemo) {
        activeMember = currentUserId ?? (state.activeMemberId.isNotEmpty ? state.activeMemberId : 'member_carlos');
      } else {
        activeMember = (currentUserId != null && currentUserId.isNotEmpty)
            ? currentUserId
            : state.activeMemberId;
      }

      emit(state.copyWith(
        status: CalendarCubitStatus.loaded,
        events: events,
        tasks: tasks,
        activeMemberId: activeMember,
        isShowingHistory: showHistory,
      ));

      _listenToTasks(showHistory);
    } catch (e) {
      emit(state.copyWith(
        status: CalendarCubitStatus.error,
        errorMessage: 'Erro ao carregar agenda: $e',
      ));
    }
  }

  void switchView(CalendarViewType view) {
    emit(state.copyWith(activeView: view));
  }

  void switchActiveMember(String memberId) {
    emit(state.copyWith(activeMemberId: memberId));
  }

  Future<void> answerRsvp({
    required String eventId,
    required RsvpStatus status,
  }) async {
    try {
      await _repository.updateRsvp(
        eventId: eventId,
        memberId: state.activeMemberId,
        status: status,
      );
      final events = await _repository.getEvents();
      emit(state.copyWith(events: events));
    } catch (e) {
      emit(state.copyWith(errorMessage: 'Erro ao responder convite: $e'));
    }
  }

  Future<void> addEvent(CalendarEvent event) async {
    try {
      await _repository.addEvent(event);
      final events = await _repository.getEvents();
      emit(state.copyWith(events: events, errorMessage: null));
    } catch (e) {
      emit(state.copyWith(errorMessage: 'Erro ao criar evento: $e'));
      rethrow;
    }
  }

  Future<void> updateEvent(
    CalendarEvent event, {
    RecurrenceScope scope = RecurrenceScope.thisInstanceOnly,
  }) async {
    try {
      await _repository.updateEvent(event, scope: scope);
      final events = await _repository.getEvents();
      emit(state.copyWith(events: events, errorMessage: null));
    } catch (e) {
      emit(state.copyWith(errorMessage: 'Erro ao atualizar evento: $e'));
      rethrow;
    }
  }

  Future<void> deleteEvent(
    String eventId, {
    RecurrenceScope scope = RecurrenceScope.thisInstanceOnly,
  }) async {
    try {
      await _repository.deleteEvent(eventId, scope: scope);
      final events = await _repository.getEvents();
      emit(state.copyWith(events: events, errorMessage: null));
    } catch (e) {
      emit(state.copyWith(errorMessage: 'Erro ao excluir evento: $e'));
      rethrow;
    }
  }

  Future<void> cancelEvent(String eventId) async {
    try {
      await _repository.cancelEvent(eventId);
      final events = await _repository.getEvents();
      emit(state.copyWith(events: events, errorMessage: null));
    } catch (e) {
      emit(state.copyWith(errorMessage: 'Erro ao cancelar evento: $e'));
      rethrow;
    }
  }

  Future<void> toggleShowHistory() async {
    final newShowHistory = !state.isShowingHistory;
    try {
      final tasks = await _repository.getTasks(includeArchived: newShowHistory);
      emit(state.copyWith(
        tasks: tasks,
        isShowingHistory: newShowHistory,
      ));
      _listenToTasks(newShowHistory);
    } catch (e) {
      emit(state.copyWith(errorMessage: 'Erro ao alternar histórico de tarefas: $e'));
    }
  }

  Future<void> toggleTask(String taskId) async {
    try {
      await _repository.toggleTaskComplete(
        taskId: taskId,
        completedByMemberId: state.activeMemberId,
      );
      final tasks = await _repository.getTasks(includeArchived: state.isShowingHistory);
      emit(state.copyWith(tasks: tasks));
    } catch (e) {
      emit(state.copyWith(errorMessage: 'Erro ao alternar status da tarefa: $e'));
    }
  }

  Future<bool> addTask(TaskItem task) async {
    try {
      await _repository.addTask(task);
      final tasks = await _repository.getTasks(includeArchived: state.isShowingHistory);
      emit(state.copyWith(tasks: tasks));
      return true;
    } catch (e) {
      emit(state.copyWith(errorMessage: 'Erro ao criar tarefa: $e'));
      return false;
    }
  }

  Future<bool> updateTask(TaskItem task) async {
    try {
      await _repository.updateTask(task);
      final tasks = await _repository.getTasks(includeArchived: state.isShowingHistory);
      emit(state.copyWith(tasks: tasks));
      return true;
    } catch (e) {
      emit(state.copyWith(errorMessage: 'Erro ao atualizar tarefa: $e'));
      return false;
    }
  }

  Future<bool> deleteTask(String taskId) async {
    try {
      await _repository.deleteTask(taskId);
      final tasks = await _repository.getTasks(includeArchived: state.isShowingHistory);
      emit(state.copyWith(tasks: tasks));
      return true;
    } catch (e) {
      emit(state.copyWith(errorMessage: 'Erro ao remover tarefa: $e'));
      return false;
    }
  }

  @override
  Future<void> close() {
    _tasksSubscription?.cancel();
    return super.close();
  }
}
