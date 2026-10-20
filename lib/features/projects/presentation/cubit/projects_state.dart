import '../../../finance/domain/entities/savings_vault.dart';
import 'package:equatable/equatable.dart';
import '../../../../core/domain/value_objects/money.dart';
import '../../../finance/domain/entities/house_expense.dart';
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
  final List<HouseExpense>? selectedProjectExpenses;
  final Map<String, Money> projectTotals;
  final List<SavingsVault> vaults;

  const ProjectsLoaded({
    required this.projects,
    this.selectedProject,
    this.settlementSummary,
    this.selectedProjectExpenses,
    this.projectTotals = const {},
    this.vaults = const [],
  });

  ProjectsLoaded copyWith({
    List<SharedProject>? projects,
    SharedProject? selectedProject,
    bool clearSelectedProject = false,
    ProjectSettlementSummary? settlementSummary,
    List<HouseExpense>? selectedProjectExpenses,
    Map<String, Money>? projectTotals,
    List<SavingsVault>? vaults,
  }) {
    return ProjectsLoaded(
      projects: projects ?? this.projects,
      selectedProject: clearSelectedProject ? null : (selectedProject ?? this.selectedProject),
      settlementSummary: clearSelectedProject ? null : (settlementSummary ?? this.settlementSummary),
      selectedProjectExpenses: clearSelectedProject ? null : (selectedProjectExpenses ?? this.selectedProjectExpenses),
      projectTotals: projectTotals ?? this.projectTotals,
      vaults: vaults ?? this.vaults,
    );
  }

  @override
  List<Object?> get props => [
        projects,
        selectedProject,
        settlementSummary,
        selectedProjectExpenses,
        projectTotals,
        vaults,
      ];
}

class ProjectsError extends ProjectsState {
  final String message;

  const ProjectsError(this.message);

  @override
  List<Object?> get props => [message];
}
