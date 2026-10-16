import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../auth/domain/repositories/auth_repository.dart';
import '../../data/datasources/admin_datasource.dart';
import '../../domain/entities/account_access.dart';

class AccountAccessState extends Equatable {
  /// Nulo enquanto não se sabe (sem login ou ainda carregando).
  final AccountAccess? access;

  const AccountAccessState({this.access});

  /// Conta conhecida e não liberada: o app mostra a tela de espera.
  bool get isBlocked => access != null && !access!.isActive;
  bool get isAdmin => access?.isAdmin ?? false;

  @override
  List<Object?> get props => [access];
}

/// Status da conta logada (migration 0068). Recarrega ao trocar de conta e
/// quando o administrador muda o status (tempo real), para a tela de espera
/// mudar sozinha.
class AccountAccessCubit extends Cubit<AccountAccessState> {
  final AdminDataSource _dataSource;
  final AuthRepository _authRepository;
  StreamSubscription? _authSubscription;
  StreamSubscription<void>? _changesSubscription;

  AccountAccessCubit(this._dataSource, this._authRepository) : super(const AccountAccessState()) {
    _authSubscription = _authRepository.authStateChanges.listen((user) {
      _stopWatching();
      if (user == null) {
        emit(const AccountAccessState());
      } else {
        refresh();
      }
    });
    if (_authRepository.currentUser != null) refresh();
  }

  Future<void> refresh() async {
    if (isClosed) return;
    if (_authRepository.isDemoMode) {
      emit(AccountAccessState(access: await _dataSource.getMyAccess()));
      return;
    }
    try {
      final access = await _dataSource.getMyAccess();
      if (isClosed) return;
      emit(AccountAccessState(access: access));
      _watch();
    } catch (_) {
      // Sem resposta do servidor não prende ninguém na tela de espera: o banco
      // continua recusando o que a conta não pode fazer.
    }
  }

  void _watch() {
    if (_changesSubscription != null || isClosed) return;
    try {
      _changesSubscription = _dataSource.watchMyAccess().listen((_) => refresh());
    } catch (_) {}
  }

  void _stopWatching() {
    _changesSubscription?.cancel();
    _changesSubscription = null;
  }

  void reset() {
    _stopWatching();
    if (!isClosed) emit(const AccountAccessState());
  }

  @override
  Future<void> close() {
    _authSubscription?.cancel();
    _stopWatching();
    return super.close();
  }
}
