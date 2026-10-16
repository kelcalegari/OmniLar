import 'package:equatable/equatable.dart';
import '../../domain/entities/user_profile.dart';
import '../../domain/entities/house.dart';

enum AuthStatus {
  initial,
  loading,
  unauthenticated,
  authenticatedNoHouse,
  authenticatedWithHouse,
  awaitingEmailConfirmation,
  failure,
}

class AuthState extends Equatable {
  final AuthStatus status;
  final UserProfile? user;
  final House? house;
  final String? errorMessage;

  /// E-mail de um cadastro que ainda espera o código de confirmação. Fica
  /// guardado também durante carregamento e erro, para a tela não se perder.
  final String? pendingEmail;

  const AuthState({
    this.status = AuthStatus.initial,
    this.user,
    this.house,
    this.errorMessage,
    this.pendingEmail,
  });

  bool get isAuthenticated => user != null;
  bool get hasHouse => house != null;
  bool get isAwaitingEmailConfirmation => user == null && pendingEmail != null;

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
      pendingEmail: pendingEmail,
    );
  }

  @override
  List<Object?> get props => [status, user, house, errorMessage, pendingEmail];
}
