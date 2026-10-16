import 'package:equatable/equatable.dart';

/// Status da conta no Omni Lar (migration 0068).
enum AccountStatus {
  pending('Em análise'),
  active('Liberada'),
  rejected('Recusada'),
  suspended('Suspensa');

  final String label;
  const AccountStatus(this.label);

  static AccountStatus fromName(String? name) =>
      values.firstWhere((s) => s.name == name, orElse: () => AccountStatus.pending);
}

/// O que a conta logada pode fazer: o status dela e se administra o app.
class AccountAccess extends Equatable {
  final AccountStatus status;
  final String? reason;
  final bool isAdmin;

  const AccountAccess({required this.status, this.reason, this.isAdmin = false});

  /// Conta do modo demo ou sem servidor: sempre liberada.
  static const unrestricted = AccountAccess(status: AccountStatus.active);

  bool get isActive => status == AccountStatus.active;

  factory AccountAccess.fromJson(Map<String, dynamic> json) => AccountAccess(
        status: AccountStatus.fromName(json['status'] as String?),
        reason: json['reason'] as String?,
        isAdmin: json['is_admin'] == true,
      );

  @override
  List<Object?> get props => [status, reason, isAdmin];
}
