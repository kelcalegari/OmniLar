import '../../domain/entities/account_access.dart';
import '../../domain/entities/admin_models.dart';
import 'admin_datasource.dart';

class DynamicAdminDataSource implements AdminDataSource {
  final AdminDataSource remote;
  final AdminDataSource mock;
  final bool Function() isDemoMode;

  DynamicAdminDataSource({
    required this.remote,
    required this.mock,
    required this.isDemoMode,
  });

  AdminDataSource get _active => isDemoMode() ? mock : remote;

  @override
  Future<AccountAccess> getMyAccess() => _active.getMyAccess();

  @override
  Stream<void> watchMyAccess() => _active.watchMyAccess();

  @override
  Future<AdminOverview> getOverview() => _active.getOverview();

  @override
  Future<List<AdminAccount>> listAccounts({String? search, AccountStatus? status}) =>
      _active.listAccounts(search: search, status: status);

  @override
  Future<AdminAccountDetail> getAccountDetail(String userId) => _active.getAccountDetail(userId);

  @override
  Future<int> setAccountStatus(List<String> userIds, AccountStatus status, {String? reason}) =>
      _active.setAccountStatus(userIds, status, reason: reason);

  @override
  Future<AdminSettings> getSettings() => _active.getSettings();

  @override
  Future<void> updateSettings(AdminSettings settings) => _active.updateSettings(settings);

  @override
  Future<List<AdminAuditEntry>> listAudit({int limit = 100}) => _active.listAudit(limit: limit);

  @override
  Future<void> setPlatformAdmin(String userId, bool isAdmin) => _active.setPlatformAdmin(userId, isAdmin);

  @override
  Future<int> setPlan(List<String> userIds, AccountPlan plan, {DateTime? expiresAt, String? note}) =>
      _active.setPlan(userIds, plan, expiresAt: expiresAt, note: note);

  @override
  Future<List<PlanLimit>> getPlanLimits() => _active.getPlanLimits();

  @override
  Future<void> setPlanLimit(AccountPlan plan, PlanResource resource, int? maxValue) =>
      _active.setPlanLimit(plan, resource, maxValue);
}
