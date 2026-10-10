import 'package:equatable/equatable.dart';
import '../../domain/entities/project_settlement_summary.dart';
import '../../domain/entities/shared_project.dart';

abstract class ProjectsState extends Equatable {
  const ProjectsState();

  @override
  List<Object?> get props => [];
}

class ProjectsInitial extends ProjectsState {
  const ProjectsInitial();
}

class ProjectsLoading extends ProjectsState {
  const ProjectsLoading();
}

class ProjectsLoaded extends ProjectsState {
  final List<SharedProject> projects;
  final SharedProject? selectedProject;
  final ProjectSettlementSummary? settlementSummary;

  const ProjectsLoaded({
    required this.projects,
    this.selectedProject,
    this.settlementSummary,
  });

  ProjectsLoaded copyWith({
    List<SharedProject>? projects,
    SharedProject? selectedProject,
    ProjectSettlementSummary? settlementSummary,
  }) {
    return ProjectsLoaded(
      projects: projects ?? this.projects,
      selectedProject: selectedProject ?? this.selectedProject,
      settlementSummary: settlementSummary ?? this.settlementSummary,
    );
  }

  @override
  List<Object?> get props => [projects, selectedProject, settlementSummary];
}

class ProjectsError extends ProjectsState {
  final String message;

  const ProjectsError(this.message);

  @override
  List<Object?> get props => [message];
}
