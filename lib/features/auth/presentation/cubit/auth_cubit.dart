import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/entities/user_profile.dart';
import '../../domain/entities/house.dart';
import '../../domain/repositories/auth_repository.dart';
import 'auth_state.dart';

class AuthCubit extends Cubit<AuthState> {
  final AuthRepository _repository;
  final void Function()? onSignOut;
  StreamSubscription? _authSubscription;
  StreamSubscription? _houseSubscription;

  AuthCubit(this._repository, {this.onSignOut})
    : super(const AuthState(status: AuthStatus.initial)) {
    // Dá um tempo mínimo para a splash renderizar a identidade visual e carregar a sessão do Supabase/Cache
    Future.microtask(() => checkAuthStatus());
    _authSubscription = _repository.authStateChanges.listen((user) {
      if (user == null) {
        emit(const AuthState(status: AuthStatus.unauthenticated));
      } else {
        final house = _repository.currentHouse;
        if (house == null) {
          emit(AuthState(status: AuthStatus.authenticatedNoHouse, user: user));
        } else {
          emit(
            AuthState(
              status: AuthStatus.authenticatedWithHouse,
              user: user,
              house: house,
            ),
          );
        }
      }
    });

    _houseSubscription = _repository.houseChanges.listen((house) {
      if (state.user != null) {
        if (house == null) {
          emit(
            AuthState(
              status: AuthStatus.authenticatedNoHouse,
              user: state.user,
            ),
          );
        } else {
          emit(
            AuthState(
              status: AuthStatus.authenticatedWithHouse,
              user: state.user,
              house: house,
            ),
          );
        }
      }
    });
  }

  void checkAuthStatus() {
    final user = _repository.currentUser;
    final house = _repository.currentHouse;

    if (user == null) {
      emit(const AuthState(status: AuthStatus.unauthenticated));
    } else if (house == null) {
      emit(AuthState(status: AuthStatus.authenticatedNoHouse, user: user));
    } else {
      emit(
        AuthState(
          status: AuthStatus.authenticatedWithHouse,
          user: user,
          house: house,
        ),
      );
    }
  }

  Future<void> signInWithEmailPassword(String email, String password) async {
    emit(state.copyWith(status: AuthStatus.loading, errorMessage: null));
    try {
      final user = await _repository.signInWithEmailPassword(email, password);
      final house = _repository.currentHouse;
      emit(
        AuthState(
          status: house != null
              ? AuthStatus.authenticatedWithHouse
              : AuthStatus.authenticatedNoHouse,
          user: user,
          house: house,
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(status: AuthStatus.failure, errorMessage: e.toString()),
      );
    }
  }

  Future<void> signUpWithEmailPassword({
    required String email,
    required String password,
    required String fullName,
  }) async {
    emit(state.copyWith(status: AuthStatus.loading, errorMessage: null));
    try {
      final user = await _repository.signUpWithEmailPassword(
        email: email,
        password: password,
        fullName: fullName,
      );
      emit(AuthState(status: AuthStatus.authenticatedNoHouse, user: user));
    } catch (e) {
      emit(
        state.copyWith(status: AuthStatus.failure, errorMessage: e.toString()),
      );
    }
  }

  Future<void> signInDemo({String memberId = 'member_carlos'}) async {
    emit(state.copyWith(status: AuthStatus.loading, errorMessage: null));
    try {
      await _repository.signInDemo(memberId: memberId);
      final user = _repository.currentUser;
      final house = _repository.currentHouse;
      emit(
        AuthState(
          status: AuthStatus.authenticatedWithHouse,
          user: user,
          house: house,
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(status: AuthStatus.failure, errorMessage: e.toString()),
      );
    }
  }

  Future<void> createHouse({
    required String name,
    int cycleStartDay = 5,
  }) async {
    emit(state.copyWith(status: AuthStatus.loading, errorMessage: null));
    try {
      final house = await _repository.createHouse(
        name: name,
        cycleStartDay: cycleStartDay,
      );
      emit(
        AuthState(
          status: AuthStatus.authenticatedWithHouse,
          user: state.user,
          house: house,
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(status: AuthStatus.failure, errorMessage: e.toString()),
      );
    }
  }

  Future<void> joinHouseWithInvite(String inviteCode) async {
    emit(state.copyWith(status: AuthStatus.loading, errorMessage: null));
    try {
      final house = await _repository.joinHouseWithInvite(inviteCode);
      emit(
        AuthState(
          status: AuthStatus.authenticatedWithHouse,
          user: state.user,
          house: house,
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(status: AuthStatus.failure, errorMessage: e.toString()),
      );
    }
  }

  Future<void> signOut() async {
    emit(state.copyWith(status: AuthStatus.loading));
    try {
      await _repository.signOut();
      try {
        onSignOut?.call();
      } catch (_) {}
      emit(const AuthState(status: AuthStatus.unauthenticated));
    } catch (e) {
      emit(
        state.copyWith(status: AuthStatus.failure, errorMessage: e.toString()),
      );
    }
  }

  Future<UserProfile?> updateProfile({
    required String fullName,
    String? email,
    String? pixKey,
  }) async {
    try {
      final updatedUser = await _repository.updateProfile(
        fullName: fullName,
        email: email,
        pixKey: pixKey,
      );
      emit(state.copyWith(user: updatedUser, errorMessage: null));
      return updatedUser;
    } catch (e) {
      emit(state.copyWith(errorMessage: e.toString()));
      rethrow;
    }
  }

  Future<House?> updateHouse({
    required String houseId,
    String? name,
    int? cycleStartDay,
    String? pixKey,
    String? pixKeyType,
    String? pixKeyHolderName,
    String? pixKeyBank,
  }) async {
    try {
      final updatedHouse = await _repository.updateHouse(
        houseId: houseId,
        name: name,
        cycleStartDay: cycleStartDay,
        pixKey: pixKey,
        pixKeyType: pixKeyType,
        pixKeyHolderName: pixKeyHolderName,
        pixKeyBank: pixKeyBank,
      );
      emit(state.copyWith(house: updatedHouse, errorMessage: null));
      return updatedHouse;
    } catch (e) {
      emit(state.copyWith(errorMessage: e.toString()));
      rethrow;
    }
  }

  @override
  Future<void> close() {
    _authSubscription?.cancel();
    _houseSubscription?.cancel();
    return super.close();
  }
}
