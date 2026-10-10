import 'package:equatable/equatable.dart';

enum AssistantRole {
  user,
  assistant,
  system,
}

enum AssistantActionStatus {
  proposed,
  confirmed,
  cancelled,
  executed,
}

class AssistantActionProposal extends Equatable {
  final String id;
  final String title;
  final String description;
  final String toolName;
  final Map<String, dynamic> arguments;
  final AssistantActionStatus status;
  final bool isHighRisk; // RN07: ações de risco (renegociar, perdoar, excluir) pedem confirmação reforçada

  const AssistantActionProposal({
    required this.id,
    required this.title,
    required this.description,
    required this.toolName,
    required this.arguments,
    this.status = AssistantActionStatus.proposed,
    this.isHighRisk = false,
  });

  AssistantActionProposal copyWith({
    String? id,
    String? title,
    String? description,
    String? toolName,
    Map<String, dynamic>? arguments,
    AssistantActionStatus? status,
    bool? isHighRisk,
  }) {
    return AssistantActionProposal(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      toolName: toolName ?? this.toolName,
      arguments: arguments ?? this.arguments,
      status: status ?? this.status,
      isHighRisk: isHighRisk ?? this.isHighRisk,
    );
  }

  @override
  List<Object?> get props => [id, title, description, toolName, arguments, status, isHighRisk];
}

class AssistantMessage extends Equatable {
  final String id;
  final AssistantRole role;
  final String content;
  final DateTime createdAt;
  final List<AssistantActionProposal> proposedActions;
  final List<String>? quickFollowups;

  const AssistantMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.createdAt,
    this.proposedActions = const [],
    this.quickFollowups,
  });

  @override
  List<Object?> get props => [id, role, content, createdAt, proposedActions, quickFollowups];
}
