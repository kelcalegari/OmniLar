import 'package:equatable/equatable.dart';

import 'account_access.dart';

DateTime? _date(Object? v) => v == null ? null : DateTime.tryParse(v as String)?.toLocal();
int _int(Object? v) => (v as num?)?.toInt() ?? 0;

String _shortDay(DateTime? d) {
  if (d == null) return '—';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)}/${two(d.month)}/${d.year}';
}

/// Números do app inteiro. Só contagens: o painel nunca vê dados financeiros das casas.
class AdminOverview extends Equatable {
  final int accountsTotal;
  final Map<AccountStatus, int> accountsByStatus;
  final Map<AccountPlan, int> accountsByPlan;
  final int premiumExpiring30d;
  final int accountsNew7d;
  final int housesTotal;
  final int housesActive30d;
  final int aiReadsToday;
  final int aiReadsMonth;
  final int admins;

  const AdminOverview({
    required this.accountsTotal,
    required this.accountsByStatus,
    this.accountsByPlan = const {},
    this.premiumExpiring30d = 0,
    required this.accountsNew7d,
    required this.housesTotal,
    required this.housesActive30d,
    required this.aiReadsToday,
    required this.aiReadsMonth,
    required this.admins,
  });

  int count(AccountStatus status) => accountsByStatus[status] ?? 0;
  int countPlan(AccountPlan plan) => accountsByPlan[plan] ?? 0;

  factory AdminOverview.fromJson(Map<String, dynamic> j) {
    final byStatus = (j['accounts_by_status'] as Map?) ?? const {};
    final byPlan = (j['accounts_by_plan'] as Map?) ?? const {};
    return AdminOverview(
      accountsTotal: _int(j['accounts_total']),
      accountsByStatus: {
        for (final e in byStatus.entries) AccountStatus.fromName(e.key as String): _int(e.value),
      },
      accountsByPlan: {
        for (final e in byPlan.entries) AccountPlan.fromName(e.key as String): _int(e.value),
      },
      premiumExpiring30d: _int(j['premium_expiring_30d']),
      accountsNew7d: _int(j['accounts_new_7d']),
      housesTotal: _int(j['houses_total']),
      housesActive30d: _int(j['houses_active_30d']),
      aiReadsToday: _int(j['ai_reads_today']),
      aiReadsMonth: _int(j['ai_reads_month']),
      admins: _int(j['admins']),
    );
  }

  @override
  List<Object?> get props => [
        accountsTotal,
        accountsByStatus,
        accountsByPlan,
        premiumExpiring30d,
        accountsNew7d,
        housesTotal,
        housesActive30d,
        aiReadsToday,
        aiReadsMonth,
        admins,
      ];
}

/// Uma linha da lista de contas.
class AdminAccount extends Equatable {
  final String userId;
  final String fullName;
  final String email;
  final AccountStatus status;
  final String? statusReason;
  final DateTime? createdAt;
  final DateTime? lastSignInAt;
  final DateTime? approvedAt;
  final int houses;
  final bool isAdmin;
  final AccountPlan plan;
  final DateTime? planExpiresAt;
  final String? planNote;

  const AdminAccount({
    required this.userId,
    required this.fullName,
    required this.email,
    required this.status,
    this.statusReason,
    this.createdAt,
    this.lastSignInAt,
    this.approvedAt,
    this.houses = 0,
    this.isAdmin = false,
    this.plan = AccountPlan.free,
    this.planExpiresAt,
    this.planNote,
  });

  factory AdminAccount.fromJson(Map<String, dynamic> j) => AdminAccount(
        userId: j['user_id'] as String,
        fullName: (j['full_name'] as String?) ?? (j['email'] as String? ?? ''),
        email: (j['email'] as String?) ?? '',
        status: AccountStatus.fromName(j['status'] as String?),
        statusReason: j['status_reason'] as String?,
        createdAt: _date(j['created_at']),
        lastSignInAt: _date(j['last_sign_in_at']),
        approvedAt: _date(j['approved_at']),
        houses: _int(j['houses']),
        isAdmin: j['is_admin'] == true,
        plan: AccountPlan.fromName(j['plan'] as String?),
        planExpiresAt: _date(j['plan_expires_at']),
        planNote: j['plan_note'] as String?,
      );

  AdminAccount copyWith({
    AccountStatus? status,
    String? statusReason,
    bool clearReason = false,
    bool? isAdmin,
    AccountPlan? plan,
    DateTime? planExpiresAt,
    bool clearPlanExpiresAt = false,
    String? planNote,
    bool clearPlanNote = false,
  }) =>
      AdminAccount(
        userId: userId,
        fullName: fullName,
        email: email,
        status: status ?? this.status,
        statusReason: clearReason ? null : (statusReason ?? this.statusReason),
        createdAt: createdAt,
        lastSignInAt: lastSignInAt,
        approvedAt: approvedAt,
        houses: houses,
        isAdmin: isAdmin ?? this.isAdmin,
        plan: plan ?? this.plan,
        planExpiresAt: clearPlanExpiresAt ? null : (planExpiresAt ?? this.planExpiresAt),
        planNote: clearPlanNote ? null : (planNote ?? this.planNote),
      );

  @override
  List<Object?> get props => [
        userId,
        fullName,
        email,
        status,
        statusReason,
        createdAt,
        lastSignInAt,
        approvedAt,
        houses,
        isAdmin,
        plan,
        planExpiresAt,
        planNote,
      ];
}

class AdminAccountHouse extends Equatable {
  final String name;
  final String role;
  final DateTime? joinedAt;

  /// Plano que vale na casa (o de quem é o dono dela).
  final AccountPlan plan;

  const AdminAccountHouse({required this.name, required this.role, this.joinedAt, this.plan = AccountPlan.free});

  String get roleLabel => switch (role) {
        'owner' => 'Dono',
        'admin' => 'Administrador',
        _ => 'Morador',
      };

  @override
  List<Object?> get props => [name, role, joinedAt, plan];
}

/// Uma ação do histórico do painel.
class AdminAuditEntry extends Equatable {
  final DateTime? createdAt;
  final String action;
  final String? actorName;
  final String? targetUserId;
  final String? targetName;
  final Map<String, dynamic> details;

  const AdminAuditEntry({
    required this.createdAt,
    required this.action,
    this.actorName,
    this.targetUserId,
    this.targetName,
    this.details = const {},
  });

  factory AdminAuditEntry.fromJson(Map<String, dynamic> j) => AdminAuditEntry(
        createdAt: _date(j['created_at']),
        action: j['action'] as String? ?? '',
        actorName: j['actor_name'] as String?,
        targetUserId: j['target_user_id'] as String?,
        targetName: j['target_name'] as String?,
        details: Map<String, dynamic>.from((j['details'] as Map?) ?? const {}),
      );

  /// Frase curta do que aconteceu.
  String get description {
    String status(Object? s) => AccountStatus.fromName(s as String?).label.toLowerCase();
    final reason = details['reason'] as String?;
    return switch (action) {
      'set_status' => 'Status: ${status(details['from'])} → ${status(details['to'])}'
          '${reason == null || reason.isEmpty ? '' : ' ($reason)'}',
      'auto_approve_invite' => 'Aprovada ao entrar numa casa por convite',
      'update_settings' => 'Configurações de aprovação alteradas',
      'grant_admin' => 'Passou a administrar o app',
      'revoke_admin' => 'Deixou de administrar o app',
      'set_plan' => 'Plano: ${AccountPlan.fromName(details['from'] as String?).label} → '
          '${AccountPlan.fromName(details['to'] as String?).label}'
          '${details['expires_at'] == null ? '' : ' até ${_shortDay(_date(details['expires_at']))}'}'
          '${(details['note'] as String?)?.isNotEmpty == true ? ' (${details['note']})' : ''}',
      'set_plan_limit' => 'Limite do ${AccountPlan.fromName(details['plan'] as String?).label}: '
          '${PlanResource.fromName(details['resource'] as String?)?.label ?? details['resource']} '
          '${details['from'] ?? 'sem limite'} → ${details['to'] ?? 'sem limite'}',
      _ => action,
    };
  }

  @override
  List<Object?> get props => [createdAt, action, actorName, targetUserId, targetName, details];
}

class AdminAccountDetail extends Equatable {
  final AdminAccount account;
  final String? phone;
  final String? approvedByName;
  final List<AdminAccountHouse> houses;
  final int aiReadsToday;
  final int aiReadsMonth;
  final List<AdminAuditEntry> history;

  const AdminAccountDetail({
    required this.account,
    this.phone,
    this.approvedByName,
    this.houses = const [],
    this.aiReadsToday = 0,
    this.aiReadsMonth = 0,
    this.history = const [],
  });

  factory AdminAccountDetail.fromJson(Map<String, dynamic> j) {
    final houses = (j['houses'] as List?) ?? const [];
    final history = (j['history'] as List?) ?? const [];
    return AdminAccountDetail(
      account: AdminAccount.fromJson({...j, 'houses': houses.length}),
      phone: j['phone'] as String?,
      approvedByName: j['approved_by_name'] as String?,
      houses: [
        for (final h in houses.cast<Map>())
          AdminAccountHouse(
            name: h['name'] as String? ?? '',
            role: h['role'] as String? ?? 'member',
            joinedAt: _date(h['joined_at']),
            plan: AccountPlan.fromName(h['plan'] as String?),
          ),
      ],
      aiReadsToday: _int(j['ai_reads_today']),
      aiReadsMonth: _int(j['ai_reads_month']),
      history: [for (final h in history.cast<Map>()) AdminAuditEntry.fromJson(Map<String, dynamic>.from(h))],
    );
  }

  @override
  List<Object?> get props => [account, phone, approvedByName, houses, aiReadsToday, aiReadsMonth, history];
}

/// Parâmetros da aprovação de contas novas.
class AdminSettings extends Equatable {
  final bool requireApproval;
  final bool autoApproveInvited;
  final List<String> autoApproveDomains;
  final List<String> autoApproveEmails;
  final DateTime? updatedAt;
  final String? updatedByName;

  const AdminSettings({
    this.requireApproval = true,
    this.autoApproveInvited = true,
    this.autoApproveDomains = const [],
    this.autoApproveEmails = const [],
    this.updatedAt,
    this.updatedByName,
  });

  factory AdminSettings.fromJson(Map<String, dynamic> j) => AdminSettings(
        requireApproval: j['require_approval'] != false,
        autoApproveInvited: j['auto_approve_invited'] != false,
        autoApproveDomains: [for (final d in (j['auto_approve_domains'] as List?) ?? const []) d as String],
        autoApproveEmails: [for (final e in (j['auto_approve_emails'] as List?) ?? const []) e as String],
        updatedAt: _date(j['updated_at']),
        updatedByName: j['updated_by_name'] as String?,
      );

  AdminSettings copyWith({
    bool? requireApproval,
    bool? autoApproveInvited,
    List<String>? autoApproveDomains,
    List<String>? autoApproveEmails,
  }) =>
      AdminSettings(
        requireApproval: requireApproval ?? this.requireApproval,
        autoApproveInvited: autoApproveInvited ?? this.autoApproveInvited,
        autoApproveDomains: autoApproveDomains ?? this.autoApproveDomains,
        autoApproveEmails: autoApproveEmails ?? this.autoApproveEmails,
        updatedAt: updatedAt,
        updatedByName: updatedByName,
      );

  @override
  List<Object?> get props =>
      [requireApproval, autoApproveInvited, autoApproveDomains, autoApproveEmails, updatedAt, updatedByName];
}

/// Recurso limitado por plano (tabela plan_limits).
enum PlanResource {
  aiReadsPerDay('ai_reads_per_day', 'Leituras de IA por dia (por casa)'),
  housesOwned('houses_owned', 'Casas como dono'),
  membersPerHouse('members_per_house', 'Moradores por casa'),
  activeProjects('active_projects', 'Projetos ativos por casa');

  final String key;
  final String label;
  const PlanResource(this.key, this.label);

  static PlanResource? fromName(String? key) {
    for (final r in values) {
      if (r.key == key) return r;
    }
    return null;
  }
}

/// Um limite: plano × recurso. Nulo = sem limite.
class PlanLimit extends Equatable {
  final AccountPlan plan;
  final PlanResource resource;
  final int? maxValue;

  const PlanLimit({required this.plan, required this.resource, this.maxValue});

  static PlanLimit? fromJson(Map<String, dynamic> j) {
    final resource = PlanResource.fromName(j['resource'] as String?);
    if (resource == null) return null;
    return PlanLimit(
      plan: AccountPlan.fromName(j['plan'] as String?),
      resource: resource,
      maxValue: (j['max_value'] as num?)?.toInt(),
    );
  }

  @override
  List<Object?> get props => [plan, resource, maxValue];
}
