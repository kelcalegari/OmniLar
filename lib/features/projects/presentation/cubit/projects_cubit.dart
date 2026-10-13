import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../finance/domain/repositories/finance_repository.dart';
import '../../domain/entities/project_participant.dart';
import '../../domain/entities/shared_project.dart';
import '../../domain/repositories/projects_repository.dart';
import '../../domain/services/project_settlement_service.dart';
import 'projects_state.dart';

class ProjectsCubit extends BlocBase<ProjectsState> {
  final ProjectsRepository projectsRepository;
  final FinanceRepository financeRepository;
  final ProjectSettlementService settlementService;

  /// Casa e usuário da sessão; nulos no modo demo, que usa os ids de demonstração.
  final String? Function()? currentHouseId;
  final String? Function()? currentUserId;

  static const demoHouseId = 'house_demo';
  static const demoUserId = 'user_1';

  ProjectsCubit({
    required this.projectsRepository,
    required this.financeRepository,
    this.settlementService = const ProjectSettlementService(),
    this.currentHouseId,
    this.currentUserId,
  }) : super(const ProjectsInitial());

  String get _houseId => currentHouseId?.call() ?? demoHouseId;

  Future<void> loadProjects({String? houseId}) async {
    emit(const ProjectsLoading());
    try {
      final projects = await projectsRepository.getProjects(houseId: houseId ?? _houseId);
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

  /// Cria um projeto na casa atual com todos os moradores como participantes,
  /// cada um com o seu percentual padrão de rateio.
  Future<void> createProjectForHouse({
    required String title,
    required ProjectType type,
  }) async {
    final now = DateTime.now();
    final projectId = 'proj_${now.millisecondsSinceEpoch}';
    final userId = currentUserId?.call() ?? demoUserId;

    var participants = <ProjectParticipant>[];
    try {
      final members = await financeRepository.getMembers();
      participants = [
        for (final m in members)
          ProjectParticipant(
            id: 'part_${m.id}',
            projectId: projectId,
            userId: m.id,
            externalName: m.name.split(' ').first,
            defaultSplitPercent: m.defaultSplitPercent,
            createdAt: now,
          ),
      ];
    } catch (_) {}
    if (participants.isEmpty) {
      participants = [
        ProjectParticipant(
          id: 'part_me',
          projectId: projectId,
          userId: userId,
          externalName: 'Eu',
          createdAt: now,
        ),
      ];
    }

    await createProject(
      SharedProject(
        id: projectId,
        houseId: _houseId,
        title: title,
        type: type,
        participants: participants,
        createdBy: userId,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  /// Troca os participantes do projeto e refaz o acerto com a lista nova.
  Future<bool> setParticipants(SharedProject project, List<ProjectParticipant> participants) async {
    try {
      await projectsRepository.setParticipants(project.id, participants);
      await loadProjects(houseId: project.houseId);
      final current = state;
      if (current is ProjectsLoaded) {
        final updated = current.projects.where((p) => p.id == project.id).firstOrNull;
        if (updated != null) await selectProject(updated);
      }
      return true;
    } catch (e) {
      emit(ProjectsError('Falha ao atualizar participantes: $e'));
      return false;
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
