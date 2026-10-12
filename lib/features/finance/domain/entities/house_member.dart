import 'package:equatable/equatable.dart';

class HouseMember extends Equatable {
  final String id;
  final String name;
  final String? avatarUrl;
  final String role; // 'owner', 'admin', 'member'
  final double defaultSplitPercent; // ex: 50.0
  final int? defaultFixedAmountCents; // ex: 70000 (R$ 700,00) para modelo de aportes fixos
  final String? pixKey;

  const HouseMember({
    required this.id,
    required this.name,
    this.avatarUrl,
    this.role = 'member',
    this.defaultSplitPercent = 50.0,
    this.defaultFixedAmountCents,
    this.pixKey,
  });

  HouseMember copyWith({
    String? id,
    String? name,
    String? avatarUrl,
    String? role,
    double? defaultSplitPercent,
    int? defaultFixedAmountCents,
    String? pixKey,
  }) {
    return HouseMember(
      id: id ?? this.id,
      name: name ?? this.name,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      role: role ?? this.role,
      defaultSplitPercent: defaultSplitPercent ?? this.defaultSplitPercent,
      defaultFixedAmountCents: defaultFixedAmountCents ?? this.defaultFixedAmountCents,
      pixKey: pixKey ?? this.pixKey,
    );
  }

  @override
  List<Object?> get props => [
        id,
        name,
        avatarUrl,
        role,
        defaultSplitPercent,
        defaultFixedAmountCents,
        pixKey,
      ];
}
