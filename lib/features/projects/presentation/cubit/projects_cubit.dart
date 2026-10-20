import '../../../finance/domain/entities/savings_vault.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/domain/value_objects/money.dart';
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
      final targetHouseId = houseId ?? _houseId;
      final projects = await projectsRepository.getProjects(houseId: targetHouseId);

      // Calcula os totais gastos de cada projeto para exibir no card
      final totals = <String, Money>{};
      for (final p in projects) {
        try {
          final exp = await financeRepository.getExpensesForProject(p.id);
          final cents = exp.fold<int>(0, (sum, e) => sum + e.amount.cents);
          totals[p.id] = Money(cents);
        } catch (_) {
          totals[p.id] = const Money.zero();
        }
      }

      List<SavingsVault> vaults = const [];
      try {
        vaults = await financeRepository.getSavingsVaults();
      } catch (_) {}

      emit(ProjectsLoaded(
        projects: projects,
        projectTotals: totals,
        vaults: vaults,
      ));
    } catch (e, stackTrace) {
      addError(e, stackTrace);
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

      final totals = Map<String, Money>.from(currentState.projectTotals);
      totals[project.id] = summary.totalExpenses;

      emit(currentState.copyWith(
        selectedProject: project,
        settlementSummary: summary,
        selectedProjectExpenses: projectExpenses,
        projectTotals: totals,
      ));
    }
  }

  /// Cria um projeto na casa atual com todos os moradores como participantes,
  /// cada um com o seu percentual padrão de rateio.
  Future<void> createProjectForHouse({
    required String title,
    required ProjectType type,
    String? description,
    Money? targetBudget,
    DateTime? startDate,
    DateTime? endDate,
    String? vaultId,
    ProjectStatus status = ProjectStatus.active,
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
        description: description,
        type: type,
        targetBudget: targetBudget,
        status: status,
        startDate: startDate,
        endDate: endDate,
        vaultId: vaultId,
        participants: participants,
        createdBy: userId,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  /// Atualiza os dados de um projeto existente.
  Future<void> updateProject(SharedProject project) async {
    try {
      await projectsRepository.updateProject(project);
      await loadProjects(houseId: project.houseId);
      final current = state;
      if (current is ProjectsLoaded) {
        final updated = current.projects.where((p) => p.id == project.id).firstOrNull;
        if (updated != null && current.selectedProject?.id == project.id) {
          await selectProject(updated);
        }
      }
    } catch (e, stackTrace) {
      addError(e, stackTrace);
      emit(ProjectsError('Falha ao atualizar projeto: $e'));
    }
  }

  /// Altera o status do projeto (active, settled, archived, planning).
  Future<void> changeProjectStatus(SharedProject project, ProjectStatus newStatus) async {
    final updated = project.copyWith(
      status: newStatus,
      updatedAt: DateTime.now(),
    );
    await updateProject(updated);
  }

  /// Exclui um projeto.
  Future<void> deleteProject(SharedProject project) async {
    try {
      final current = state;
      if (current is ProjectsLoaded) {
        // Remove imediatamente da memória local para a tela atualizar sem esperar a rede
        final updatedList = current.projects.where((p) => p.id != project.id).toList();
        final updatedTotals = Map<String, Money>.from(current.projectTotals)..remove(project.id);
        emit(current.copyWith(
          projects: updatedList,
          projectTotals: updatedTotals,
          clearSelectedProject: current.selectedProject?.id == project.id,
        ));
      }
      await projectsRepository.deleteProject(project.id);
      await loadProjects(houseId: project.houseId);
    } catch (e, stackTrace) {
      addError(e, stackTrace);
      emit(ProjectsError('Falha ao excluir projeto: $e'));
    }
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
    } catch (e, stackTrace) {
      addError(e, stackTrace);
      emit(ProjectsError('Falha ao atualizar participantes: $e'));
      return false;
    }
  }

  Future<void> createProject(SharedProject project) async {
    try {
      await projectsRepository.createProject(project);
      await loadProjects(houseId: project.houseId);
    } catch (e, stackTrace) {
      addError(e, stackTrace);
      emit(ProjectsError('Falha ao criar projeto: $e'));
    }
  }
}
