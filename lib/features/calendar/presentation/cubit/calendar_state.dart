import 'package:equatable/equatable.dart';
import '../../domain/entities/calendar_event.dart';
import '../../domain/entities/task_item.dart';

enum CalendarViewType {
  events,
  tasks,
}

enum CalendarCubitStatus {
  initial,
  loading,
  loaded,
  error,
}

class CalendarState extends Equatable {
  final CalendarCubitStatus status;
  final CalendarViewType activeView;
  final List<CalendarEvent> events;
  final List<TaskItem> tasks;
  final String? errorMessage;
  final String activeMemberId; // Usuário atual simulado (ex: 'member_marina')

  const CalendarState({
    this.status = CalendarCubitStatus.initial,
    this.activeView = CalendarViewType.events,
    this.events = const [],
    this.tasks = const [],
    this.errorMessage,
    this.activeMemberId = 'member_marina',
  });

  CalendarState copyWith({
    CalendarCubitStatus? status,
    CalendarViewType? activeView,
    List<CalendarEvent>? events,
    List<TaskItem>? tasks,
    String? errorMessage,
    String? activeMemberId,
  }) {
    return CalendarState(
      status: status ?? this.status,
      activeView: activeView ?? this.activeView,
      events: events ?? this.events,
      tasks: tasks ?? this.tasks,
      errorMessage: errorMessage ?? this.errorMessage,
      activeMemberId: activeMemberId ?? this.activeMemberId,
    );
  }

  @override
  List<Object?> get props => [status, activeView, events, tasks, errorMessage, activeMemberId];
}
