import '../../domain/entities/shared_project.dart';
import '../../domain/repositories/projects_repository.dart';

class DynamicProjectsRepository implements ProjectsRepository {
  final ProjectsRepository remote;
  final ProjectsRepository mock;
  final bool Function() isDemoMode;

  DynamicProjectsRepository({
    required this.remote,
    required this.mock,
    required this.isDemoMode,
  });

  ProjectsRepository get _active => isDemoMode() ? mock : remote;

  @override
  Future<List<SharedProject>> getProjects({required String houseId}) =>
      _active.getProjects(houseId: houseId);

  @override
  Future<SharedProject?> getProjectById(String id) =>
      _active.getProjectById(id);

  @override
  Future<void> createProject(SharedProject project) =>
      _active.createProject(project);

  @override
  Future<void> updateProject(SharedProject project) =>
      _active.updateProject(project);

  @override
  Future<void> deleteProject(String id) =>
      _active.deleteProject(id);
}
