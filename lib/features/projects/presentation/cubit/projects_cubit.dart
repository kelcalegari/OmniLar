import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../finance/domain/repositories/finance_repository.dart';
import '../../domain/entities/shared_project.dart';
import '../../domain/repositories/projects_repository.dart';
import '../../domain/services/project_settlement_service.dart';
import 'projects_state.dart';

class ProjectsCubit extends BlocBase<ProjectsState> {
  final ProjectsRepository projectsRepository;
  final FinanceRepository financeRepository;
  final ProjectSettlementService settlementService;

  ProjectsCubit({
    required this.projectsRepository,
    required this.financeRepository,
    this.settlementService = const ProjectSettlementService(),
  }) : super(const ProjectsInitial());

  Future<void> loadProjects({String houseId = 'house_demo'}) async {
    emit(const ProjectsLoading());
    try {
      final projects = await projectsRepository.getProjects(houseId: houseId);
      emit(ProjectsLoaded(projects: projects));
    } catch (e) {
      emit(ProjectsError('Falha ao carregar projetos: $e'));
    }
  }

  Future<void> selectProject(SharedProject project) async {
    final currentState = state;
    if (currentState is ProjectsLoaded) {
      emit(currentState.copyWith(selectedProject: project));

      // Busca todas as despesas vinculadas a este projeto (independente do ciclo/mês)
      final projectExpenses = await financeRepository.getExpensesForProject(project.id);

      final summary = settlementService.computeProjectSettlement(
        project: project,
        expenses: projectExpenses,
        participants: project.participants,
      );

      emit(currentState.copyWith(
        selectedProject: project,
        settlementSummary: summary,
      ));
    }
  }

  Future<void> createProject(SharedProject project) async {
    try {
      await projectsRepository.createProject(project);
      await loadProjects(houseId: project.houseId);
    } catch (e) {
      emit(ProjectsError('Falha ao criar projeto: $e'));
    }
  }
}
