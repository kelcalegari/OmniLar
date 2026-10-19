import 'package:equatable/equatable.dart';
import '../../../../core/domain/value_objects/money.dart';

enum TaskPriority {
  low,
  medium,
  high,
}

/// Repetição de uma tarefa com rodízio (coluna `tasks.recurrence`, 0104).
/// Sem repetição, a tarefa é única, como sempre foi.
enum TaskRecurrence {
  none('none'),
  daily('daily'),
  weekly('weekly'),
  monthly('monthly');

  final String dbValue;
  const TaskRecurrence(this.dbValue);

  /// Valor ausente ou desconhecido vale tarefa única.
  static TaskRecurrence fromDb(Object? value) {
    for (final r in values) {
      if (r.dbValue == value) return r;
    }
    return none;
  }

  String get label => switch (this) {
        TaskRecurrence.none => 'Única',
        TaskRecurrence.daily => 'Diária',
        TaskRecurrence.weekly => 'Semanal',
        TaskRecurrence.monthly => 'Mensal',
      };

  /// Dia seguinte a [from] nesta repetição (mensal mantém o dia, ou o último do mês).
  DateTime next(DateTime from) {
    switch (this) {
      case TaskRecurrence.none:
        return from;
      case TaskRecurrence.daily:
        return DateTime(from.year, from.month, from.day + 1);
      case TaskRecurrence.weekly:
        return DateTime(from.year, from.month, from.day + 7);
      case TaskRecurrence.monthly:
        final lastDay = DateTime(from.year, from.month + 2, 0).day;
        return DateTime(from.year, from.month + 1, from.day > lastDay ? lastDay : from.day);
    }
  }
}

class TaskItem extends Equatable {
  final String id;
  final String title;
  final String? description;
  final DateTime? dueDate;
  final String? assignedToMemberId;
  final String? assignedToMemberName;
  final bool isCompleted;
  final DateTime? completedAt;
  final String? completedByMemberId;
  final TaskPriority priority;
  final Money? cost;
  final String createdByMemberId;
  final DateTime createdAt;

  /// Repetição da tarefa (0104); ao concluir, nasce a próxima ocorrência.
  final TaskRecurrence recurrence;

  /// Moradores que se revezam na tarefa, na ordem do rodízio (0104).
  final List<String> rotationMemberIds;

  /// Quem pega a próxima ocorrência (0104); nulo: o seguinte do rodízio.
  final String? nextAssigneeMemberId;

  const TaskItem({
    required this.id,
    required this.title,
    this.description,
    this.dueDate,
    this.assignedToMemberId,
    this.assignedToMemberName,
    this.isCompleted = false,
    this.completedAt,
    this.completedByMemberId,
    this.priority = TaskPriority.medium,
    this.cost,
    required this.createdByMemberId,
    required this.createdAt,
    this.recurrence = TaskRecurrence.none,
    this.rotationMemberIds = const [],
    this.nextAssigneeMemberId,
  });

  bool get isOverdue {
    if (isCompleted || dueDate == null) return false;
    final now = DateTime.now();
    return dueDate!.isBefore(DateTime(now.year, now.month, now.day));
  }

  bool get isRecurring => recurrence != TaskRecurrence.none;

  /// Quem vem depois de [current] no rodízio [members]; quem não está nele (ou
  /// ninguém) volta ao primeiro. Sem rodízio, nulo.
  static String? rotationAfter(List<String> members, String? current) {
    if (members.isEmpty) return null;
    final index = current == null ? -1 : members.indexOf(current);
    return members[(index + 1) % members.length];
  }

  /// A próxima ocorrência desta tarefa, criada quando ela é concluída (o banco
  /// faz o mesmo no gatilho da 0104). Nulo se a tarefa não se repete. O
  /// vencimento anda uma repetição e, se já passou, continua andando até hoje.
  TaskItem? nextOccurrence({required String id, required DateTime now}) {
    if (!isRecurring) return null;
    final today = DateTime(now.year, now.month, now.day);
    var due = recurrence.next(dueDate ?? today);
    while (due.isBefore(today)) {
      due = recurrence.next(due);
    }
    final assignee = nextAssigneeMemberId ?? rotationAfter(rotationMemberIds, assignedToMemberId) ?? assignedToMemberId;
    return TaskItem(
      id: id,
      title: title,
      description: description,
      dueDate: due,
      assignedToMemberId: assignee,
      priority: priority,
      cost: cost,
      createdByMemberId: createdByMemberId,
      createdAt: now,
      recurrence: recurrence,
      rotationMemberIds: rotationMemberIds,
      nextAssigneeMemberId: rotationAfter(rotationMemberIds, assignee),
    );
  }

  TaskItem copyWith({
    String? id,
    String? title,
    String? description,
    DateTime? dueDate,
    String? assignedToMemberId,
    String? assignedToMemberName,
    bool? isCompleted,
    DateTime? completedAt,
    String? completedByMemberId,
    TaskPriority? priority,
    Money? cost,
    String? createdByMemberId,
    DateTime? createdAt,
    TaskRecurrence? recurrence,
    List<String>? rotationMemberIds,
    String? nextAssigneeMemberId,
    bool clearNextAssignee = false,
  }) {
    return TaskItem(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      dueDate: dueDate ?? this.dueDate,
      assignedToMemberId: assignedToMemberId ?? this.assignedToMemberId,
      assignedToMemberName: assignedToMemberName ?? this.assignedToMemberName,
      isCompleted: isCompleted ?? this.isCompleted,
      completedAt: completedAt ?? this.completedAt,
      completedByMemberId: completedByMemberId ?? this.completedByMemberId,
      priority: priority ?? this.priority,
      cost: cost ?? this.cost,
      createdByMemberId: createdByMemberId ?? this.createdByMemberId,
      createdAt: createdAt ?? this.createdAt,
      recurrence: recurrence ?? this.recurrence,
      rotationMemberIds: rotationMemberIds ?? this.rotationMemberIds,
      nextAssigneeMemberId: clearNextAssignee ? null : (nextAssigneeMemberId ?? this.nextAssigneeMemberId),
    );
  }

  @override
  List<Object?> get props => [
        id,
        title,
        description,
        dueDate,
        assignedToMemberId,
        assignedToMemberName,
        isCompleted,
        completedAt,
        completedByMemberId,
        priority,
        cost,
        createdByMemberId,
        createdAt,
        recurrence,
        rotationMemberIds,
        nextAssigneeMemberId,
      ];
}
