import 'package:equatable/equatable.dart';

class HouseMember extends Equatable {
  final String id;
  final String name;
  final String? avatarUrl;
  final String role; // 'owner', 'admin', 'member'
  final double defaultSplitPercent; // ex: 50.0

  const HouseMember({
    required this.id,
    required this.name,
    this.avatarUrl,
    this.role = 'member',
    this.defaultSplitPercent = 50.0,
  });

  @override
  List<Object?> get props => [id, name, avatarUrl, role, defaultSplitPercent];
}
