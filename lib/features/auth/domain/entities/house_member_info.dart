import 'package:equatable/equatable.dart';
import 'user_profile.dart';

class HouseMemberInfo extends Equatable {
  final String id;
  final String houseId;
  final String userId;
  final String role; // 'owner', 'admin', 'member'
  final DateTime joinedAt;
  final UserProfile? profile;

  const HouseMemberInfo({
    required this.id,
    required this.houseId,
    required this.userId,
    required this.role,
    required this.joinedAt,
    this.profile,
  });

  bool get isAdmin => role == 'owner' || role == 'admin';
  bool get isOwner => role == 'owner';

  @override
  List<Object?> get props => [id, houseId, userId, role, joinedAt, profile];
}
