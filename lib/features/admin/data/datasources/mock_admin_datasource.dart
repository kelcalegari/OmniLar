import 'dart:async';

import '../../../../core/errors/failures.dart';
import '../../domain/entities/account_access.dart';
import '../../domain/entities/admin_models.dart';
import 'admin_datasource.dart';

/// Painel no modo demo: a conta demo administra o app e vê contas de exemplo.
/// Segue as mesmas regras do banco (motivo para recusar e suspender, ninguém
/// muda o próprio status ou o próprio acesso de administrador).
class MockAdminDataSource implements AdminDataSource {
  final String Function() currentUserId;
  final _changes = StreamController<void>.broadcast();
  final _audit = <AdminAuditEntry>[];
  var _settings = const AdminSettings();

  late final List<AdminAccount> _accounts;

  MockAdminDataSource({String Function()? currentUserId})
      : currentUserId = currentUserId ?? (() => 'member_carlos') {
    final now = DateTime.now();
    _accounts = [
      AdminAccount(
        userId: 'member_carlos',
        fullName: 'Carlos Demo',
        email: 'carlos@omnilar.com',
        status: AccountStatus.active,
        createdAt: now.subtract(const Duration(days: 120)),
        lastSignInAt: now,
        approvedAt: now.subtract(const Duration(days: 120)),
        houses: 1,
        isAdmin: true,
      ),
      AdminAccount(
        userId: 'member_marina',
        fullName: 'Marina Demo',
        email: 'marina@omnilar.com',
        status: AccountStatus.active,
        createdAt: now.subtract(const Duration(days: 110)),
        lastSignInAt: now.subtract(const Duration(days: 1)),
        approvedAt: now.subtract(const Duration(days: 110)),
        houses: 1,
      ),
      AdminAccount(
        userId: 'demo_pending_1',
        fullName: 'Paula Souza',
        email: 'paula@exemplo.com',
        status: AccountStatus.pending,
        createdAt: now.subtract(const Duration(hours: 5)),
        lastSignInAt: now.subtract(const Duration(hours: 5)),
      ),
      AdminAccount(
        userId: 'demo_pending_2',
        fullName: 'Rafael Lima',
        email: 'rafael@exemplo.com',
        status: AccountStatus.pending,
        createdAt: now.subtract(const Duration(days: 2)),
      ),
      AdminAccount(
        userId: 'demo_suspended',
        fullName: 'Teste Antigo',
        email: 'teste@exemplo.com',
        status: AccountStatus.suspended,
        statusReason: 'Conta de teste',
        createdAt: now.subtract(const Duration(days: 60)),
      ),
    ];
  }

  @override
  Future<AccountAccess> getMyAccess() async => const AccountAccess(status: AccountStatus.active, isAdmin: true);

  @override
  Stream<void> watchMyAccess() => const Stream.empty();

  /// Notifica quem acompanha as contas (usado pelos testes).
  Stream<void> get changes => _changes.stream;

  @override
  Future<AdminOverview> getOverview() async {
    final byStatus = <AccountStatus, int>{};
    for (final a in _accounts) {
      byStatus[a.status] = (byStatus[a.status] ?? 0) + 1;
    }
    final weekAgo = DateTime.now().subtract(const Duration(days: 7));
    return AdminOverview(
      accountsTotal: _accounts.length,
      accountsByStatus: byStatus,
      accountsNew7d: _accounts.where((a) => a.createdAt?.isAfter(weekAgo) ?? false).length,
      housesTotal: 1,
      housesActive30d: 1,
      aiReadsToday: 3,
      aiReadsMonth: 41,
      admins: _accounts.where((a) => a.isAdmin).length,
    );
  }

  @override
  Future<List<AdminAccount>> listAccounts({String? search, AccountStatus? status}) async {
    final q = search?.trim().toLowerCase() ?? '';
    final list = _accounts
        .where((a) => status == null || a.status == status)
        .where((a) => q.isEmpty || a.fullName.toLowerCase().contains(q) || a.email.toLowerCase().contains(q))
        .toList()
      ..sort((a, b) {
        final pending = (b.status == AccountStatus.pending ? 1 : 0) - (a.status == AccountStatus.pending ? 1 : 0);
        if (pending != 0) return pending;
        return (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0));
      });
    return list;
  }

  AdminAccount _find(String userId) => _accounts.firstWhere(
        (a) => a.userId == userId,
        orElse: () => throw const ServerFailure('Conta não encontrada.'),
      );

  @override
  Future<AdminAccountDetail> getAccountDetail(String userId) async {
    final account = _find(userId);
    return AdminAccountDetail(
      account: account,
      houses: account.houses > 0
          ? [AdminAccountHouse(name: 'Casa Demo', role: account.isAdmin ? 'owner' : 'member')]
          : const [],
      aiReadsToday: account.houses > 0 ? 1 : 0,
      aiReadsMonth: account.houses > 0 ? 12 : 0,
      history: _audit.where((e) => e.targetUserId == userId).toList(),
    );
  }

  @override
  Future<int> setAccountStatus(List<String> userIds, AccountStatus status, {String? reason}) async {
    if (status == AccountStatus.pending) throw const ServerFailure('Status inválido.');
    final trimmed = reason?.trim() ?? '';
    if (status != AccountStatus.active && trimmed.isEmpty) {
      throw const ServerFailure('Informe o motivo.');
    }
    if (userIds.contains(currentUserId())) {
      throw const ServerFailure('Você não pode mudar o status da sua própria conta.');
    }
    var changed = 0;
    for (final id in userIds.toSet()) {
      final index = _accounts.indexWhere((a) => a.userId == id);
      if (index == -1 || _accounts[index].status == status) continue;
      final old = _accounts[index].status;
      _accounts[index] = _accounts[index].copyWith(
        status: status,
        statusReason: status == AccountStatus.active ? null : trimmed,
        clearReason: status == AccountStatus.active,
      );
      _audit.insert(
        0,
        AdminAuditEntry(
          createdAt: DateTime.now(),
          action: 'set_status',
          actorName: 'Carlos Demo',
          targetUserId: id,
          targetName: _accounts[index].fullName,
          details: {'from': old.name, 'to': status.name, if (trimmed.isNotEmpty) 'reason': trimmed},
        ),
      );
      changed++;
    }
    if (changed > 0) _changes.add(null);
    return changed;
  }

  @override
  Future<AdminSettings> getSettings() async => _settings;

  @override
  Future<void> updateSettings(AdminSettings settings) async {
    final emails = {
      for (final e in settings.autoApproveEmails)
        if (e.trim().isNotEmpty) e.trim().toLowerCase(),
    }.toList()
      ..sort();
    if (emails.any((e) => !RegExp(r'^.+@.+$').hasMatch(e))) {
      throw const ServerFailure('Há um e-mail inválido na lista.');
    }
    final domains = {
      for (final d in settings.autoApproveDomains)
        if (d.trim().replaceFirst('@', '').isNotEmpty) d.trim().replaceFirst('@', '').toLowerCase(),
    }.toList()
      ..sort();
    _settings = AdminSettings(
      requireApproval: settings.requireApproval,
      autoApproveInvited: settings.autoApproveInvited,
      autoApproveDomains: domains,
      autoApproveEmails: emails,
      updatedAt: DateTime.now(),
      updatedByName: 'Carlos Demo',
    );
    _audit.insert(0, AdminAuditEntry(createdAt: DateTime.now(), action: 'update_settings', actorName: 'Carlos Demo'));
  }

  @override
  Future<List<AdminAuditEntry>> listAudit({int limit = 100}) async => _audit.take(limit).toList();

  @override
  Future<void> setPlatformAdmin(String userId, bool isAdmin) async {
    if (userId == currentUserId()) {
      throw const ServerFailure('Você não pode mudar o seu próprio acesso de administrador.');
    }
    final index = _accounts.indexWhere((a) => a.userId == userId);
    if (index == -1) throw const ServerFailure('Conta não encontrada.');
    if (isAdmin && _accounts[index].status != AccountStatus.active) {
      throw const ServerFailure('Só uma conta liberada pode administrar o app.');
    }
    _accounts[index] = _accounts[index].copyWith(isAdmin: isAdmin);
    _audit.insert(
      0,
      AdminAuditEntry(
        createdAt: DateTime.now(),
        action: isAdmin ? 'grant_admin' : 'revoke_admin',
        actorName: 'Carlos Demo',
        targetUserId: userId,
        targetName: _accounts[index].fullName,
      ),
    );
  }
}
