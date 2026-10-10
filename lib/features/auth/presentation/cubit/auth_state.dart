import 'package:equatable/equatable.dart';
import '../../domain/entities/user_profile.dart';
import '../../domain/entities/house.dart';

enum AuthStatus {
  initial,
  loading,
  unauthenticated,
  authenticatedNoHouse,
  authenticatedWithHouse,
  failure,
}

class AuthState extends Equatable {
  final AuthStatus status;
  final UserProfile? user;
  final House? house;
  final String? errorMessage;

  const AuthState({
    this.status = AuthStatus.initial,
    this.user,
    this.house,
    this.errorMessage,
  });

  bool get isAuthenticated => user != null;
  bool get hasHouse => house != null;

  AuthState copyWith({
    AuthStatus? status,
    UserProfile? user,
    House? house,
    String? errorMessage,
  }) {
    return AuthState(
      status: status ?? this.status,
      user: user ?? this.user,
      house: house ?? this.house,
      errorMessage: errorMessage,
    );
  }

  @override
  List<Object?> get props => [status, user, house, errorMessage];
}
