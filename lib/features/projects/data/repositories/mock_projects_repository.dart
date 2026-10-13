import '../../../../core/domain/value_objects/money.dart';
import '../../domain/entities/project_participant.dart';
import '../../domain/entities/shared_project.dart';
import '../../domain/repositories/projects_repository.dart';

class MockProjectsRepository implements ProjectsRepository {
  final List<SharedProject> _projects = [];

  MockProjectsRepository() {
    final now = DateTime.now();
    _projects.addAll([
      SharedProject(
        id: 'proj_trip_praia',
        houseId: 'house_demo',
        title: 'Férias em Floripa 🏖️',
        description: 'Aluguel de casa, combustível, passeios de barco e comida',
        type: ProjectType.trip,
        targetBudget: const Money(450000), // R$ 4.500,00
        status: ProjectStatus.active,
        startDate: now.subtract(const Duration(days: 2)),
        endDate: now.add(const Duration(days: 5)),
        participants: [
          ProjectParticipant(
            id: 'part_floripa_carlos',
            projectId: 'proj_trip_praia',
            userId: 'member_carlos',
            externalName: 'Carlos',
            defaultSplitPercent: 50.0,
            createdAt: now,
          ),
          ProjectParticipant(
            id: 'part_floripa_marina',
            projectId: 'proj_trip_praia',
            userId: 'member_marina',
            externalName: 'Marina',
            defaultSplitPercent: 50.0,
            createdAt: now,
          ),
        ],
        createdBy: 'member_carlos',
        createdAt: now.subtract(const Duration(days: 10)),
        updatedAt: now,
      ),
      SharedProject(
        id: 'proj_reforma_cozinha',
        houseId: 'house_demo',
        title: 'Reforma da Cozinha & Bancada 🛠️',
        description: 'Pedras de granito, marcenaria e iluminação',
        type: ProjectType.assetPurchase,
        targetBudget: const Money(1200000), // R$ 12.000,00
        status: ProjectStatus.active,
        startDate: now.subtract(const Duration(days: 15)),
        participants: [
          ProjectParticipant(
            id: 'part_reforma_carlos',
            projectId: 'proj_reforma_cozinha',
            userId: 'member_carlos',
            externalName: 'Carlos',
            defaultSplitPercent: 50.0,
            createdAt: now,
          ),
          ProjectParticipant(
            id: 'part_reforma_marina',
            projectId: 'proj_reforma_cozinha',
            userId: 'member_marina',
            externalName: 'Marina',
            defaultSplitPercent: 50.0,
            createdAt: now,
          ),
        ],
        createdBy: 'member_carlos',
        createdAt: now.subtract(const Duration(days: 20)),
        updatedAt: now,
      ),
    ]);
  }

  @override
  Future<List<SharedProject>> getProjects({required String houseId}) async {
    return List.unmodifiable(_projects);
  }

  @override
  Future<SharedProject?> getProjectById(String id) async {
    try {
      return _projects.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> createProject(SharedProject project) async {
    _projects.add(project);
  }

  @override
  Future<void> updateProject(SharedProject project) async {
    final index = _projects.indexWhere((p) => p.id == project.id);
    if (index != -1) {
      _projects[index] = project;
    }
  }

  @override
  Future<void> deleteProject(String id) async {
    _projects.removeWhere((p) => p.id == id);
  }

  @override
  Future<void> setParticipants(String projectId, List<ProjectParticipant> participants) async {
    final index = _projects.indexWhere((p) => p.id == projectId);
    if (index != -1) {
      _projects[index] = _projects[index].copyWith(participants: participants);
    }
  }
}
