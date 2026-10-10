import '../entities/shared_project.dart';

abstract class ProjectsRepository {
  Future<List<SharedProject>> getProjects({required String houseId});
  Future<SharedProject?> getProjectById(String id);
  Future<void> createProject(SharedProject project);
  Future<void> updateProject(SharedProject project);
  Future<void> deleteProject(String id);
}
