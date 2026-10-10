import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/domain/enums/recurrence.dart';
import '../../domain/entities/calendar_event.dart';
import '../../domain/entities/event_participant.dart';
import '../../domain/entities/task_item.dart';
import '../../domain/repositories/calendar_repository.dart';
import 'calendar_state.dart';

class CalendarCubit extends Cubit<CalendarState> {
  final CalendarRepository _repository;

  CalendarCubit(this._repository) : super(const CalendarState());

  Future<void> loadCalendarData() async {
    emit(state.copyWith(status: CalendarCubitStatus.loading));
    try {
      final events = await _repository.getEvents();
      final tasks = await _repository.getTasks();
      emit(state.copyWith(
        status: CalendarCubitStatus.loaded,
        events: events,
        tasks: tasks,
      ));
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
      emit(state.copyWith(events: events));
    } catch (e) {
      emit(state.copyWith(errorMessage: 'Erro ao criar evento: $e'));
    }
  }

  Future<void> updateEvent(
    CalendarEvent event, {
    RecurrenceScope scope = RecurrenceScope.thisInstanceOnly,
  }) async {
    try {
      await _repository.updateEvent(event, scope: scope);
      final events = await _repository.getEvents();
      emit(state.copyWith(events: events));
    } catch (e) {
      emit(state.copyWith(errorMessage: 'Erro ao atualizar evento: $e'));
    }
  }

  Future<void> deleteEvent(
    String eventId, {
    RecurrenceScope scope = RecurrenceScope.thisInstanceOnly,
  }) async {
    try {
      await _repository.deleteEvent(eventId, scope: scope);
      final events = await _repository.getEvents();
      emit(state.copyWith(events: events));
    } catch (e) {
      emit(state.copyWith(errorMessage: 'Erro ao excluir evento: $e'));
    }
  }

  Future<void> cancelEvent(String eventId) async {
    try {
      await _repository.cancelEvent(eventId);
      final events = await _repository.getEvents();
      emit(state.copyWith(events: events));
    } catch (e) {
      emit(state.copyWith(errorMessage: 'Erro ao cancelar evento: $e'));
    }
  }

  Future<void> toggleTask(String taskId) async {
    try {
      await _repository.toggleTaskComplete(
        taskId: taskId,
        completedByMemberId: state.activeMemberId,
      );
      final tasks = await _repository.getTasks();
      emit(state.copyWith(tasks: tasks));
    } catch (e) {
      emit(state.copyWith(errorMessage: 'Erro ao alternar status da tarefa: $e'));
    }
  }

  Future<void> addTask(TaskItem task) async {
    try {
      await _repository.addTask(task);
      final tasks = await _repository.getTasks();
      emit(state.copyWith(tasks: tasks));
    } catch (e) {
      emit(state.copyWith(errorMessage: 'Erro ao criar tarefa: $e'));
    }
  }

  Future<void> deleteTask(String taskId) async {
    try {
      await _repository.deleteTask(taskId);
      final tasks = await _repository.getTasks();
      emit(state.copyWith(tasks: tasks));
    } catch (e) {
      emit(state.copyWith(errorMessage: 'Erro ao remover tarefa: $e'));
    }
  }
}
