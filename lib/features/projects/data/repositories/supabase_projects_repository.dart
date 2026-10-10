import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/domain/value_objects/money.dart';
import '../../../../core/errors/failures.dart';
import '../../domain/entities/project_participant.dart';
import '../../domain/entities/shared_project.dart';
import '../../domain/repositories/projects_repository.dart';

class SupabaseProjectsRepository implements ProjectsRepository {
  final SupabaseClient client;

  SupabaseProjectsRepository(this.client);

  bool _isUuid(String id) {
    final uuidRegex = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    );
    return uuidRegex.hasMatch(id);
  }

  ProjectType _parseType(String typeStr) {
    switch (typeStr) {
      case 'trip':
        return ProjectType.trip;
      case 'asset_purchase':
        return ProjectType.assetPurchase;
      case 'investment':
        return ProjectType.investment;
      case 'event':
        return ProjectType.event;
      default:
        return ProjectType.generic;
    }
  }

  String _typeToString(ProjectType type) {
    switch (type) {
      case ProjectType.trip:
        return 'trip';
      case ProjectType.assetPurchase:
        return 'asset_purchase';
      case ProjectType.investment:
        return 'investment';
      case ProjectType.event:
        return 'event';
      case ProjectType.generic:
        return 'generic';
    }
  }

  ProjectStatus _parseStatus(String statusStr) {
    switch (statusStr) {
      case 'planning':
        return ProjectStatus.planning;
      case 'settled':
        return ProjectStatus.settled;
      case 'archived':
        return ProjectStatus.archived;
      default:
        return ProjectStatus.active;
    }
  }

  String _statusToString(ProjectStatus status) {
    switch (status) {
      case ProjectStatus.planning:
        return 'planning';
      case ProjectStatus.settled:
        return 'settled';
      case ProjectStatus.archived:
        return 'archived';
      case ProjectStatus.active:
        return 'active';
    }
  }

  SharedProject _mapRowToProject(Map<String, dynamic> r) {
    final rawParticipants = (r['project_participants'] as List<dynamic>? ?? []);
    final participants = rawParticipants.map((p) {
      final pMap = p as Map<String, dynamic>;
      return ProjectParticipant(
        id: pMap['id'] as String,
        projectId: pMap['project_id'] as String,
        userId: pMap['user_id'] as String?,
        externalName: pMap['external_name'] as String?,
        defaultSplitPercent: (pMap['default_split_percent'] as num?)?.toDouble(),
        createdAt: DateTime.parse(pMap['created_at'] as String),
      );
    }).toList();

    final targetBudgetCents = r['target_budget_cents'] as int?;

    return SharedProject(
      id: r['id'] as String,
      houseId: r['house_id'] as String,
      title: r['title'] as String,
      description: r['description'] as String?,
      type: _parseType(r['type'] as String? ?? 'generic'),
      targetBudget: targetBudgetCents != null ? Money(targetBudgetCents) : null,
      status: _parseStatus(r['status'] as String? ?? 'active'),
      startDate: r['start_date'] != null ? DateTime.tryParse(r['start_date'] as String) : null,
      endDate: r['end_date'] != null ? DateTime.tryParse(r['end_date'] as String) : null,
      currency: r['currency'] as String? ?? 'BRL',
      participants: participants,
      createdBy: r['created_by'] as String? ?? '',
      createdAt: DateTime.parse(r['created_at'] as String),
      updatedAt: DateTime.parse(r['updated_at'] as String),
    );
  }

  @override
  Future<List<SharedProject>> getProjects({required String houseId}) async {
    try {
      final rows = await client
          .from('shared_projects')
          .select('*, project_participants(*)')
          .eq('house_id', houseId)
          .isFilter('deleted_at', null)
          .order('created_at', ascending: false);

      return rows.map(_mapRowToProject).toList();
    } catch (e) {
      throw ServerFailure('Erro ao carregar projetos compartilhados: $e');
    }
  }

  @override
  Future<SharedProject?> getProjectById(String id) async {
    try {
      final rows = await client
          .from('shared_projects')
          .select('*, project_participants(*)')
          .eq('id', id)
          .isFilter('deleted_at', null);

      if (rows.isEmpty) return null;
      return _mapRowToProject(rows.first);
    } catch (e) {
      throw ServerFailure('Erro ao buscar projeto compartilhado: $e');
    }
  }

  @override
  Future<void> createProject(SharedProject project) async {
    try {
      final currentUserId = client.auth.currentUser?.id;
      final projectRow = {
        if (_isUuid(project.id)) 'id': project.id,
        'house_id': project.houseId,
        'title': project.title,
        'description': project.description,
        'type': _typeToString(project.type),
        'target_budget_cents': project.targetBudget?.cents,
        'status': _statusToString(project.status),
        'start_date': project.startDate?.toIso8601String().split('T')[0],
        'end_date': project.endDate?.toIso8601String().split('T')[0],
        'currency': project.currency,
        'created_by': currentUserId ?? project.createdBy,
      };

      final inserted = await client
          .from('shared_projects')
          .insert(projectRow)
          .select('id')
          .single();

      final realProjectId = inserted['id'] as String;

      if (project.participants.isNotEmpty) {
        final participantRows = project.participants.map((p) {
          return {
            if (_isUuid(p.id)) 'id': p.id,
            'project_id': realProjectId,
            'user_id': p.userId,
            'external_name': p.externalName,
            'default_split_percent': p.defaultSplitPercent,
          };
        }).toList();

        await client.from('project_participants').insert(participantRows);
      }
    } catch (e) {
      throw ServerFailure('Erro ao criar projeto compartilhado: $e');
    }
  }

  @override
  Future<void> updateProject(SharedProject project) async {
    try {
      await client.from('shared_projects').update({
        'title': project.title,
        'description': project.description,
        'type': _typeToString(project.type),
        'target_budget_cents': project.targetBudget?.cents,
        'status': _statusToString(project.status),
        'start_date': project.startDate?.toIso8601String().split('T')[0],
        'end_date': project.endDate?.toIso8601String().split('T')[0],
        'currency': project.currency,
      }).eq('id', project.id);
    } catch (e) {
      throw ServerFailure('Erro ao atualizar projeto compartilhado: $e');
    }
  }

  @override
  Future<void> deleteProject(String id) async {
    try {
      await client
          .from('shared_projects')
          .update({'deleted_at': DateTime.now().toIso8601String()})
          .eq('id', id);
    } catch (e) {
      throw ServerFailure('Erro ao excluir projeto compartilhado: $e');
    }
  }
}
