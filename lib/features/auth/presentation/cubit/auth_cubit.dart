import 'dart:async';
import '../../domain/entities/account_deletion_preview.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/errors/failures.dart';
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
    _authSubscription = _repository.authStateChanges.listen((user) async {
      if (isClosed || _repository.isRestoringSession) return;
      if (user == null) {
        if (!isClosed) emit(const AuthState(status: AuthStatus.unauthenticated));
      } else {
        final house = _repository.currentHouse;
        List<House> houses = const [];
        try {
          houses = await _repository.getUserHouses();
        } catch (_) {}
        if (isClosed) return;
        if (house == null) {
          emit(AuthState(status: AuthStatus.authenticatedNoHouse, user: user, userHouses: houses));
        } else {
          emit(
            AuthState(
              status: AuthStatus.authenticatedWithHouse,
              user: user,
              house: house,
              userHouses: houses,
            ),
          );
        }
      }
    });

    _houseSubscription = _repository.houseChanges.listen((house) async {
      if (isClosed || _repository.isRestoringSession) return;
      if (state.user != null) {
        List<House> houses = state.userHouses;
        try {
          houses = await _repository.getUserHouses();
        } catch (_) {}
        if (isClosed) return;
        if (house == null) {
          emit(
            AuthState(
              status: AuthStatus.authenticatedNoHouse,
              user: state.user,
              userHouses: houses,
            ),
          );
        } else {
          emit(
            AuthState(
              status: AuthStatus.authenticatedWithHouse,
              user: state.user,
              house: house,
              userHouses: houses,
            ),
          );
        }
      }
    });
  }

  Future<void> checkAuthStatus() async {
    // Sessão salva ainda carregando: mantém o estado inicial em vez de concluir "deslogado"
    if (isClosed || _repository.isRestoringSession) return;

    final user = _repository.currentUser;
    final house = _repository.currentHouse;
    List<House> houses = const [];
    if (user != null) {
      try {
        houses = await _repository.getUserHouses();
      } catch (_) {}
    }
    if (isClosed) return;

    if (user == null) {
      emit(const AuthState(status: AuthStatus.unauthenticated));
    } else if (house == null) {
      emit(AuthState(status: AuthStatus.authenticatedNoHouse, user: user, userHouses: houses));
    } else {
      emit(
        AuthState(
          status: AuthStatus.authenticatedWithHouse,
          user: user,
          house: house,
          userHouses: houses,
        ),
      );
    }
  }

  Future<List<House>> _fetchUserHouses() async {
    try {
      return await _repository.getUserHouses();
    } catch (_) {
      return state.userHouses;
    }
  }

  Future<void> signInWithEmailPassword(String email, String password) async {
    emit(state.copyWith(status: AuthStatus.loading, errorMessage: null));
    try {
      final user = await _repository.signInWithEmailPassword(email, password);
      final house = _repository.currentHouse;
      final houses = await _fetchUserHouses();
      emit(
        AuthState(
          status: house != null
              ? AuthStatus.authenticatedWithHouse
              : AuthStatus.authenticatedNoHouse,
          user: user,
          house: house,
          userHouses: houses,
        ),
      );
    } on EmailNotConfirmedFailure catch (e) {
      // Conta criada mas não confirmada: manda um código novo e abre a tela dele
      String? resendError;
      try {
        await _repository.resendSignUpCode(e.email);
      } catch (err) {
        resendError = err.toString();
      }
      emit(
        AuthState(
          status: AuthStatus.awaitingEmailConfirmation,
          pendingEmail: e.email,
          errorMessage: resendError,
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
      if (user == null) {
        emit(
          AuthState(
            status: AuthStatus.awaitingEmailConfirmation,
            pendingEmail: email.trim(),
          ),
        );
        return;
      }
      emit(AuthState(status: AuthStatus.authenticatedNoHouse, user: user));
    } catch (e) {
      emit(
        state.copyWith(status: AuthStatus.failure, errorMessage: e.toString()),
      );
    }
  }

  Future<void> verifySignUpCode(String code) async {
    final email = state.pendingEmail;
    if (email == null) return;
    emit(state.copyWith(status: AuthStatus.loading, errorMessage: null));
    try {
      final user = await _repository.verifySignUpCode(email: email, code: code);
      final house = _repository.currentHouse;
      final houses = await _fetchUserHouses();
      emit(
        AuthState(
          status: house != null
              ? AuthStatus.authenticatedWithHouse
              : AuthStatus.authenticatedNoHouse,
          user: user,
          house: house,
          userHouses: houses,
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(status: AuthStatus.failure, errorMessage: e.toString()),
      );
    }
  }

  /// Reenvia o código; devolve `true` se o envio deu certo.
  Future<bool> resendSignUpCode() async {
    final email = state.pendingEmail;
    if (email == null) return false;
    try {
      await _repository.resendSignUpCode(email);
      emit(
        state.copyWith(
          status: AuthStatus.awaitingEmailConfirmation,
          errorMessage: null,
        ),
      );
      return true;
    } catch (e) {
      emit(
        state.copyWith(status: AuthStatus.failure, errorMessage: e.toString()),
      );
      return false;
    }
  }

  /// Envia o código de redefinição de senha. Lança a falha para a tela mostrar.
  Future<void> requestPasswordReset(String email) {
    return _repository.requestPasswordReset(email);
  }

  /// Troca a senha com o código e entra. Lança a falha para a tela mostrar,
  /// sem mexer no estado (o roteador tiraria a pessoa da tela).
  Future<void> resetPasswordWithCode({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    final user = await _repository.resetPasswordWithCode(
      email: email,
      code: code,
      newPassword: newPassword,
    );
    final house = _repository.currentHouse;
    final houses = await _fetchUserHouses();
    emit(
      AuthState(
        status: house != null
            ? AuthStatus.authenticatedWithHouse
            : AuthStatus.authenticatedNoHouse,
        user: user,
        house: house,
        userHouses: houses,
      ),
    );
  }

  String? get pendingEmailChange => _repository.pendingEmailChange;
  List<String> get signInProviders => _repository.signInProviders;

  /// Troca a senha de quem está logado. Lança a falha para a tela mostrar.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) {
    return _repository.changePassword(
      currentPassword: currentPassword,
      newPassword: newPassword,
    );
  }

  /// Aceita a versão atual dos Termos e da Política. Lança a falha para a tela mostrar.
  Future<void> acceptTerms(String version) => _repository.acceptTerms(version);

  /// Permite ou retira a leitura por IA. Lança a falha para a tela mostrar.
  Future<void> setAiConsent(bool given) => _repository.setAiConsent(given);

  /// Os dados da própria conta em JSON. Lança a falha para a tela mostrar.
  Future<String> exportMyData() => _repository.exportMyData();

  /// O que a exclusão da conta faria. Lança a falha para a tela mostrar.
  Future<AccountDeletionPreview> getAccountDeletionPreview() => _repository.getAccountDeletionPreview();

  /// Exclui a conta e sai. Lança a falha para a tela mostrar.
  Future<void> deleteAccount({required String password}) async {
    await _repository.deleteAccount(password: password);
    await signOut();
  }

  /// Pede a troca do e-mail. Lança a falha para a tela mostrar.
  Future<void> requestEmailChange(String newEmail) {
    return _repository.requestEmailChange(newEmail);
  }

  /// Confere um código da troca de e-mail; `true` quando a troca terminou.
  Future<bool> confirmEmailChange({
    required String email,
    required String code,
  }) async {
    final done = await _repository.confirmEmailChange(email: email, code: code);
    final user = _repository.currentUser;
    if (done && user != null) {
      emit(state.copyWith(user: user, errorMessage: null));
    }
    return done;
  }

  /// Desiste da confirmação (e-mail errado ou já confirmado pelo link).
  void cancelEmailConfirmation() {
    emit(const AuthState(status: AuthStatus.unauthenticated));
  }

  Future<void> signInWithGoogle() async {
    emit(state.copyWith(status: AuthStatus.loading, errorMessage: null));
    try {
      final user = await _repository.signInWithGoogle();
      if (user == null) {
        // Web: a página já está indo para o Google. Celular: a pessoa desistiu.
        if (!kIsWeb) emit(const AuthState(status: AuthStatus.unauthenticated));
        return;
      }
      final house = _repository.currentHouse;
      final houses = await _fetchUserHouses();
      emit(
        AuthState(
          status: house != null
              ? AuthStatus.authenticatedWithHouse
              : AuthStatus.authenticatedNoHouse,
          user: user,
          house: house,
          userHouses: houses,
        ),
      );
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
      final houses = await _fetchUserHouses();
      emit(
        AuthState(
          status: AuthStatus.authenticatedWithHouse,
          user: user,
          house: house,
          userHouses: houses,
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(status: AuthStatus.failure, errorMessage: e.toString()),
      );
    }
  }

  /// Cria a casa. [initialReserveCents] e [initialCashCents]: o dinheiro que
  /// ela já tinha (reserva guardada e saldo na conta da casa), opcionais.
  Future<void> createHouse({
    required String name,
    int cycleStartDay = 5,
    int initialReserveCents = 0,
    int initialCashCents = 0,
  }) async {
    emit(state.copyWith(status: AuthStatus.loading, errorMessage: null));
    try {
      final house = await _repository.createHouse(
        name: name,
        cycleStartDay: cycleStartDay,
        initialReserveCents: initialReserveCents,
        initialCashCents: initialCashCents,
      );
      final houses = await _fetchUserHouses();
      emit(
        AuthState(
          status: AuthStatus.authenticatedWithHouse,
          user: state.user,
          house: house,
          userHouses: houses,
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
      final houses = await _fetchUserHouses();
      emit(
        AuthState(
          status: AuthStatus.authenticatedWithHouse,
          user: state.user,
          house: house,
          userHouses: houses,
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(status: AuthStatus.failure, errorMessage: e.toString()),
      );
    }
  }

  /// Alterna a casa ativa para o morador e emite o novo estado.
  Future<void> switchHouse(String houseId) async {
    if (state.house?.id == houseId) return;
    emit(state.copyWith(status: AuthStatus.loading, errorMessage: null));
    try {
      await _repository.selectHouse(houseId);
      final houses = await _fetchUserHouses();
      final house = _repository.currentHouse;
      if (house != null) {
        emit(
          AuthState(
            status: AuthStatus.authenticatedWithHouse,
            user: state.user,
            house: house,
            userHouses: houses,
          ),
        );
      } else {
        emit(state.copyWith(status: AuthStatus.authenticatedWithHouse));
      }
    } catch (e) {
      emit(
        state.copyWith(status: AuthStatus.failure, errorMessage: e.toString()),
      );
    }
  }

  /// Recarrega a lista de casas do morador no estado atual.
  Future<void> loadUserHouses() async {
    final houses = await _fetchUserHouses();
    emit(state.copyWith(userHouses: houses));
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
      if (isClosed) return updatedUser;
      emit(state.copyWith(user: updatedUser, errorMessage: null));
      return updatedUser;
    } catch (e) {
      if (!isClosed) emit(state.copyWith(errorMessage: e.toString()));
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
