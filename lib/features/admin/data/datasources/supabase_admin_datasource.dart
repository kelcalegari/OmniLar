import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/errors/failures.dart';
import '../../domain/entities/account_access.dart';
import '../../domain/entities/admin_models.dart';
import 'admin_datasource.dart';

class SupabaseAdminDataSource implements AdminDataSource {
  final SupabaseClient client;

  SupabaseAdminDataSource({required this.client});

  /// Mensagem do banco sem o prefixo técnico do PostgREST.
  static String _message(Object e) {
    if (e is PostgrestException) return e.message;
    return e.toString();
  }

  Future<T> _call<T>(Future<T> Function() run, String failure) async {
    try {
      return await run();
    } catch (e) {
      if (e is Failure) rethrow;
      throw ServerFailure('$failure: ${_message(e)}');
    }
  }

  @override
  Future<AccountAccess> getMyAccess() => _call(() async {
        final data = await client.rpc('my_account_access');
        return AccountAccess.fromJson(Map<String, dynamic>.from(data as Map));
      }, 'Erro ao consultar a sua conta');

  @override
  Stream<void> watchMyAccess() {
    final userId = client.auth.currentUser?.id;
    if (userId == null) return const Stream.empty();
    RealtimeChannel? channel;
    late final StreamController<void> controller;
    controller = StreamController<void>.broadcast(
      onListen: () {
        // Tempo real da própria linha de account_status (migration 0068)
        channel = client
            .channel('account-status-$userId-${identityHashCode(controller)}')
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'account_status',
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'user_id',
                value: userId,
              ),
              callback: (_) {
                if (!controller.isClosed) controller.add(null);
              },
            )
            .subscribe();
      },
      onCancel: () {
        final current = channel;
        channel = null;
        if (current != null) client.removeChannel(current);
      },
    );
    return controller.stream;
  }

  @override
  Future<AdminOverview> getOverview() => _call(() async {
        final data = await client.rpc('admin_overview');
        return AdminOverview.fromJson(Map<String, dynamic>.from(data as Map));
      }, 'Erro ao carregar a visão geral');

  @override
  Future<List<AdminAccount>> listAccounts({String? search, AccountStatus? status}) => _call(() async {
        final rows = await client.rpc('admin_list_accounts', params: {
          'p_search': (search == null || search.trim().isEmpty) ? null : search.trim(),
          'p_status': status?.name,
        });
        return [for (final r in (rows as List).cast<Map>()) AdminAccount.fromJson(Map<String, dynamic>.from(r))];
      }, 'Erro ao carregar as contas');

  @override
  Future<AdminAccountDetail> getAccountDetail(String userId) => _call(() async {
        final data = await client.rpc('admin_account_detail', params: {'p_user_id': userId});
        return AdminAccountDetail.fromJson(Map<String, dynamic>.from(data as Map));
      }, 'Erro ao carregar a conta');

  @override
  Future<int> setAccountStatus(List<String> userIds, AccountStatus status, {String? reason}) =>
      _call(() async {
        final changed = await client.rpc('admin_set_account_status', params: {
          'p_user_ids': userIds,
          'p_status': status.name,
          'p_reason': reason,
        });
        return (changed as num?)?.toInt() ?? 0;
      }, 'Erro ao mudar o status');

  @override
  Future<AdminSettings> getSettings() => _call(() async {
        final data = await client.rpc('admin_get_settings');
        return AdminSettings.fromJson(Map<String, dynamic>.from(data as Map));
      }, 'Erro ao carregar as configurações');

  @override
  Future<void> updateSettings(AdminSettings settings) => _call(() async {
        await client.rpc('admin_update_settings', params: {
          'p_require_approval': settings.requireApproval,
          'p_auto_approve_invited': settings.autoApproveInvited,
          'p_auto_approve_domains': settings.autoApproveDomains,
          'p_auto_approve_emails': settings.autoApproveEmails,
        });
      }, 'Erro ao salvar as configurações');

  @override
  Future<List<AdminAuditEntry>> listAudit({int limit = 100}) => _call(() async {
        final rows = await client.rpc('admin_list_audit', params: {'p_limit': limit});
        return [for (final r in (rows as List).cast<Map>()) AdminAuditEntry.fromJson(Map<String, dynamic>.from(r))];
      }, 'Erro ao carregar o histórico');

  @override
  Future<void> setPlatformAdmin(String userId, bool isAdmin) => _call(() async {
        await client.rpc('admin_set_platform_admin', params: {'p_user_id': userId, 'p_is_admin': isAdmin});
      }, 'Erro ao mudar o acesso de administrador');

  @override
  Future<int> setPlan(List<String> userIds, AccountPlan plan, {DateTime? expiresAt, String? note}) =>
      _call(() async {
        final changed = await client.rpc('admin_set_plan', params: {
          'p_user_ids': userIds,
          'p_plan': plan.name,
          'p_expires_at': plan == AccountPlan.premium ? expiresAt?.toUtc().toIso8601String() : null,
          'p_note': note,
        });
        return (changed as num?)?.toInt() ?? 0;
      }, 'Erro ao trocar o plano');

  @override
  Future<List<PlanLimit>> getPlanLimits() => _call(() async {
        final rows = await client.rpc('admin_get_plan_limits');
        return [
          for (final r in (rows as List).cast<Map>())
            if (PlanLimit.fromJson(Map<String, dynamic>.from(r)) case final limit?) limit,
        ];
      }, 'Erro ao carregar os limites dos planos');

  @override
  Future<void> setPlanLimit(AccountPlan plan, PlanResource resource, int? maxValue) => _call(() async {
        await client.rpc('admin_set_plan_limit', params: {
          'p_plan': plan.name,
          'p_resource': resource.key,
          'p_max_value': maxValue,
        });
      }, 'Erro ao salvar o limite');
}
