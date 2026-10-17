import 'package:equatable/equatable.dart';

/// O que acontece com cada casa ao excluir a conta (migration 0081).
enum HouseDeletionAction {
  /// Único morador: a casa é apagada junto.
  deleteHouse,

  /// Dono com outros moradores: a casa passa para [HouseDeletionImpact.newOwnerName].
  transfer,

  /// Morador comum: só sai da casa.
  leave;

  static HouseDeletionAction fromName(String? name) => switch (name) {
        'delete_house' => deleteHouse,
        'transfer' => transfer,
        _ => leave,
      };
}

class HouseDeletionImpact extends Equatable {
  final String houseName;
  final HouseDeletionAction action;
  final String? newOwnerName;

  const HouseDeletionImpact({required this.houseName, required this.action, this.newOwnerName});

  @override
  List<Object?> get props => [houseName, action, newOwnerName];
}

/// Empréstimo com saldo em aberto: continua no histórico depois da exclusão.
class OpenLoanImpact extends Equatable {
  final String title;
  final int openCents;

  /// Quem exclui a conta é quem deve.
  final bool isBorrower;
  final String otherName;

  const OpenLoanImpact({
    required this.title,
    required this.openCents,
    required this.isBorrower,
    required this.otherName,
  });

  @override
  List<Object?> get props => [title, openCents, isBorrower, otherName];
}

/// Prévia da exclusão de conta, mostrada antes de confirmar.
class AccountDeletionPreview extends Equatable {
  final List<HouseDeletionImpact> houses;
  final List<OpenLoanImpact> openLoans;

  const AccountDeletionPreview({this.houses = const [], this.openLoans = const []});

  factory AccountDeletionPreview.fromJson(Map<String, dynamic> json) => AccountDeletionPreview(
        houses: [
          for (final h in (json['houses'] as List? ?? const []).cast<Map>())
            HouseDeletionImpact(
              houseName: h['name'] as String? ?? 'Casa',
              action: HouseDeletionAction.fromName(h['action'] as String?),
              newOwnerName: h['new_owner_name'] as String?,
            ),
        ],
        openLoans: [
          for (final l in (json['open_loans'] as List? ?? const []).cast<Map>())
            OpenLoanImpact(
              title: l['title'] as String? ?? '',
              openCents: (l['open_cents'] as num?)?.toInt() ?? 0,
              isBorrower: l['side'] == 'borrower',
              otherName: l['other_name'] as String? ?? '',
            ),
        ],
      );

  @override
  List<Object?> get props => [houses, openLoans];
}
