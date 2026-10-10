import 'package:equatable/equatable.dart';
import '../../../../core/domain/value_objects/money.dart';

enum TaskPriority {
  low,
  medium,
  high,
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
  });

  bool get isOverdue {
    if (isCompleted || dueDate == null) return false;
    final now = DateTime.now();
    return dueDate!.isBefore(DateTime(now.year, now.month, now.day));
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
      ];
}
