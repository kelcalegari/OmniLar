import '../../domain/entities/account_access.dart';
import '../../domain/entities/admin_models.dart';

/// Status da própria conta e, para quem administra o app, as funções do painel
/// (migration 0068). Toda função do painel é conferida também no banco.
abstract class AdminDataSource {
  Future<AccountAccess> getMyAccess();

  /// Avisa quando o status da própria conta muda (aprovação, suspensão).
  Stream<void> watchMyAccess();

  Future<AdminOverview> getOverview();
  Future<List<AdminAccount>> listAccounts({String? search, AccountStatus? status});
  Future<AdminAccountDetail> getAccountDetail(String userId);

  /// Aprova, recusa, suspende ou reativa uma ou várias contas. Devolve quantas mudaram.
  Future<int> setAccountStatus(List<String> userIds, AccountStatus status, {String? reason});

  Future<AdminSettings> getSettings();
  Future<void> updateSettings(AdminSettings settings);
  Future<List<AdminAuditEntry>> listAudit({int limit = 100});
  Future<void> setPlatformAdmin(String userId, bool isAdmin);

  /// Troca o plano de uma ou várias contas (validade só vale para o Premium).
  Future<int> setPlan(List<String> userIds, AccountPlan plan, {DateTime? expiresAt, String? note});

  Future<List<PlanLimit>> getPlanLimits();

  /// Nulo = sem limite.
  Future<void> setPlanLimit(AccountPlan plan, PlanResource resource, int? maxValue);
}
