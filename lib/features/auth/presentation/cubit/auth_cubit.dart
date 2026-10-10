import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/repositories/auth_repository.dart';
import 'auth_state.dart';

class AuthCubit extends Cubit<AuthState> {
  final AuthRepository _repository;
  StreamSubscription? _authSubscription;
  StreamSubscription? _houseSubscription;

  AuthCubit(this._repository)
      : super(_repository.currentUser == null
            ? const AuthState(status: AuthStatus.unauthenticated)
            : _repository.currentHouse == null
                ? AuthState(
                    status: AuthStatus.authenticatedNoHouse,
                    user: _repository.currentUser,
                  )
                : AuthState(
                    status: AuthStatus.authenticatedWithHouse,
                    user: _repository.currentUser,
                    house: _repository.currentHouse,
                  )) {
    _authSubscription = _repository.authStateChanges.listen((user) {
      if (user == null) {
        emit(const AuthState(status: AuthStatus.unauthenticated));
      } else {
        final house = _repository.currentHouse;
        if (house == null) {
          emit(AuthState(
            status: AuthStatus.authenticatedNoHouse,
            user: user,
          ));
        } else {
          emit(AuthState(
            status: AuthStatus.authenticatedWithHouse,
            user: user,
            house: house,
          ));
        }
      }
    });

    _houseSubscription = _repository.houseChanges.listen((house) {
      if (state.user != null) {
        if (house == null) {
          emit(AuthState(
            status: AuthStatus.authenticatedNoHouse,
            user: state.user,
          ));
        } else {
          emit(AuthState(
            status: AuthStatus.authenticatedWithHouse,
            user: state.user,
            house: house,
          ));
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
      emit(AuthState(
        status: AuthStatus.authenticatedNoHouse,
        user: user,
      ));
    } else {
      emit(AuthState(
        status: AuthStatus.authenticatedWithHouse,
        user: user,
        house: house,
      ));
    }
  }

  Future<void> signInWithEmailPassword(String email, String password) async {
    emit(state.copyWith(status: AuthStatus.loading, errorMessage: null));
    try {
      final user = await _repository.signInWithEmailPassword(email, password);
      final house = _repository.currentHouse;
      emit(AuthState(
        status: house != null
            ? AuthStatus.authenticatedWithHouse
            : AuthStatus.authenticatedNoHouse,
        user: user,
        house: house,
      ));
    } catch (e) {
      emit(state.copyWith(
        status: AuthStatus.failure,
        errorMessage: e.toString(),
      ));
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
      emit(AuthState(
        status: AuthStatus.authenticatedNoHouse,
        user: user,
      ));
    } catch (e) {
      emit(state.copyWith(
        status: AuthStatus.failure,
        errorMessage: e.toString(),
      ));
    }
  }

  Future<void> signInDemo({String memberId = 'member_carlos'}) async {
    emit(state.copyWith(status: AuthStatus.loading, errorMessage: null));
    try {
      await _repository.signInDemo(memberId: memberId);
      final user = _repository.currentUser;
      final house = _repository.currentHouse;
      emit(AuthState(
        status: AuthStatus.authenticatedWithHouse,
        user: user,
        house: house,
      ));
    } catch (e) {
      emit(state.copyWith(
        status: AuthStatus.failure,
        errorMessage: e.toString(),
      ));
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
      emit(AuthState(
        status: AuthStatus.authenticatedWithHouse,
        user: state.user,
        house: house,
      ));
    } catch (e) {
      emit(state.copyWith(
        status: AuthStatus.failure,
        errorMessage: e.toString(),
      ));
    }
  }

  Future<void> joinHouseWithInvite(String inviteCode) async {
    emit(state.copyWith(status: AuthStatus.loading, errorMessage: null));
    try {
      final house = await _repository.joinHouseWithInvite(inviteCode);
      emit(AuthState(
        status: AuthStatus.authenticatedWithHouse,
        user: state.user,
        house: house,
      ));
    } catch (e) {
      emit(state.copyWith(
        status: AuthStatus.failure,
        errorMessage: e.toString(),
      ));
    }
  }

  Future<void> signOut() async {
    emit(state.copyWith(status: AuthStatus.loading));
    try {
      await _repository.signOut();
      emit(const AuthState(status: AuthStatus.unauthenticated));
    } catch (e) {
      emit(state.copyWith(
        status: AuthStatus.failure,
        errorMessage: e.toString(),
      ));
    }
  }

  @override
  Future<void> close() {
    _authSubscription?.cancel();
    _houseSubscription?.cancel();
    return super.close();
  }
}
