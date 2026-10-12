import 'package:equatable/equatable.dart';

class UserProfile extends Equatable {
  final String id;
  final String email;
  final String fullName;
  final String? avatarUrl;
  final String? phone;
  final String? pixKey;

  const UserProfile({
    required this.id,
    required this.email,
    required this.fullName,
    this.avatarUrl,
    this.phone,
    this.pixKey,
  });

  UserProfile copyWith({
    String? id,
    String? email,
    String? fullName,
    String? avatarUrl,
    String? phone,
    String? pixKey,
  }) {
    return UserProfile(
      id: id ?? this.id,
      email: email ?? this.email,
      fullName: fullName ?? this.fullName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      phone: phone ?? this.phone,
      pixKey: pixKey ?? this.pixKey,
    );
  }

  @override
  List<Object?> get props => [id, email, fullName, avatarUrl, phone, pixKey];
}
