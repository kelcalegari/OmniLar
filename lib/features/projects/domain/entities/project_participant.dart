import 'package:equatable/equatable.dart';

class ProjectParticipant extends Equatable {
  final String id;
  final String projectId;
  final String? userId; // Nulo se for convidado externo sem login
  final String? externalName; // Preenchido se for convidado externo
  final double? defaultSplitPercent; // Ex: 25.0 (%)
  final DateTime createdAt;

  const ProjectParticipant({
    required this.id,
    required this.projectId,
    this.userId,
    this.externalName,
    this.defaultSplitPercent,
    required this.createdAt,
  });

  /// Nome de exibição (se for membro registrado da casa ou convidado)
  String get displayName => externalName ?? (userId != null ? 'Membro' : 'Participante');

  bool get isExternal => userId == null;

  ProjectParticipant copyWith({
    String? id,
    String? projectId,
    String? userId,
    String? externalName,
    double? defaultSplitPercent,
    DateTime? createdAt,
  }) {
    return ProjectParticipant(
      id: id ?? this.id,
      projectId: projectId ?? this.projectId,
      userId: userId ?? this.userId,
      externalName: externalName ?? this.externalName,
      defaultSplitPercent: defaultSplitPercent ?? this.defaultSplitPercent,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  List<Object?> get props => [id, projectId, userId, externalName, defaultSplitPercent, createdAt];
}
