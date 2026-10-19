import 'package:equatable/equatable.dart';

/// Status da conta no Omni Lar (migration 0068).
enum AccountStatus {
  pending('Em análise'),
  active('Liberada'),
  rejected('Recusada'),
  suspended('Suspensa'),

  /// Excluída pelo próprio usuário (migration 0081): sem ações no painel.
  deleted('Excluída');

  final String label;
  const AccountStatus(this.label);

  static AccountStatus fromName(String? name) =>
      values.firstWhere((s) => s.name == name, orElse: () => AccountStatus.pending);
}

/// Plano da conta (migration 0069). A casa segue o plano de quem é o dono dela.
enum AccountPlan {
  free('Free'),
  premium('Premium');

  final String label;
  const AccountPlan(this.label);

  static AccountPlan fromName(String? name) => name == 'premium' ? AccountPlan.premium : AccountPlan.free;
}

/// O que a conta logada pode fazer: o status dela, se administra o app e o plano.
class AccountAccess extends Equatable {
  final AccountStatus status;
  final String? reason;
  final bool isAdmin;
  final AccountPlan plan;

  /// Validade do Premium (nula = sem validade ou plano Free).
  final DateTime? planExpiresAt;

  const AccountAccess({
    required this.status,
    this.reason,
    this.isAdmin = false,
    this.plan = AccountPlan.free,
    this.planExpiresAt,
  });

  /// Conta do modo demo ou sem servidor: sempre liberada.
  static const unrestricted = AccountAccess(status: AccountStatus.active);

  bool get isActive => status == AccountStatus.active;
  bool get isPremium => plan == AccountPlan.premium || isAdmin;

  factory AccountAccess.fromJson(Map<String, dynamic> json) => AccountAccess(
        status: AccountStatus.fromName(json['status'] as String?),
        reason: json['reason'] as String?,
        isAdmin: json['is_admin'] == true,
        plan: AccountPlan.fromName(json['plan'] as String?),
        planExpiresAt: json['plan_expires_at'] == null
            ? null
            : DateTime.tryParse(json['plan_expires_at'] as String)?.toLocal(),
      );

  @override
  List<Object?> get props => [status, reason, isAdmin, plan, planExpiresAt];
}
