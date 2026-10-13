import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/repositories/p2p_repository.dart';
import '../../domain/entities/p2p_loan.dart';
import '../../../../core/domain/value_objects/money.dart';
import '../../../auth/domain/repositories/auth_repository.dart';
import 'p2p_state.dart';

class P2PCubit extends Cubit<P2PState> {
  final P2PRepository _repository;
  final AuthRepository? _authRepository;
  StreamSubscription? _authSubscription;

  P2PCubit(this._repository, [this._authRepository])
      : super(P2PState(
          currentUserId: _resolveInitialUserId(_authRepository),
        )) {
    _authSubscription = _authRepository?.authStateChanges.listen((user) {
      if (user != null) {
        switchUser(user.id);
      } else {
        resetState();
      }
    });
  }

  void resetState() {
    emit(P2PState(currentUserId: _resolveInitialUserId(_authRepository)));
  }

  static String _resolveInitialUserId(AuthRepository? auth) {
    if (auth != null) {
      if (auth.isDemoMode) {
        return auth.currentUser?.id ?? 'member_carlos';
      }
      return auth.currentUser?.id ?? '';
    }
    return '';
  }

  String get _effectiveUserId {
    final auth = _authRepository;
    if (auth != null) {
      if (auth.isDemoMode) {
        return auth.currentUser?.id ?? (state.currentUserId.isNotEmpty ? state.currentUserId : 'member_carlos');
      }
      return auth.currentUser?.id ?? state.currentUserId;
    }
    return state.currentUserId;
  }

  Future<void> loadLoans() async {
    final activeUserId = _effectiveUserId;
    emit(state.copyWith(status: P2PStatus.loading, currentUserId: activeUserId));
    try {
      final loans = await _repository.getLoans();
      emit(state.copyWith(
        status: P2PStatus.success,
        allLoans: loans,
        currentUserId: activeUserId,
      ));
    } catch (e) {
      emit(state.copyWith(
        status: P2PStatus.failure,
        errorMessage: 'Erro ao carregar empréstimos: $e',
      ));
    }
  }

  void switchUser(String newUserId) {
    emit(state.copyWith(currentUserId: newUserId));
  }

  Future<bool> createLoan(P2PLoan loan) async {
    try {
      await _repository.createLoan(loan);
      await loadLoans();
      return true;
    } catch (e) {
      emit(state.copyWith(
        status: P2PStatus.failure,
        errorMessage: 'Erro ao criar empréstimo: $e',
      ));
      return false;
    }
  }

  Future<bool> payInstallment(String installmentId, Money amount, {String? vaultId}) async {
    try {
      await _repository.payInstallment(installmentId, amount, vaultId: vaultId);
      await loadLoans();
      return true;
    } catch (e) {
      emit(state.copyWith(
        status: P2PStatus.failure,
        errorMessage: 'Erro ao registrar pagamento: $e',
      ));
      return false;
    }
  }

  Future<bool> payLoan(String loanId, Money amount, {String? vaultId}) async {
    try {
      await _repository.payLoan(loanId, amount, vaultId: vaultId);
      await loadLoans();
      return true;
    } catch (e) {
      emit(state.copyWith(
        status: P2PStatus.failure,
        errorMessage: 'Erro ao registrar abatimento: $e',
      ));
      return false;
    }
  }

  Future<bool> setSettleInCycle(String loanId, bool settleInCycle) async {
    try {
      await _repository.setSettleInCycle(loanId, settleInCycle);
      await loadLoans();
      return true;
    } catch (e) {
      emit(state.copyWith(
        status: P2PStatus.failure,
        errorMessage: 'Erro ao atualizar empréstimo: $e',
      ));
      return false;
    }
  }

  Future<bool> forgiveLoan(String loanId) async {
    try {
      await _repository.forgiveLoan(loanId);
      await loadLoans();
      return true;
    } catch (e) {
      emit(state.copyWith(
        status: P2PStatus.failure,
        errorMessage: 'Erro ao perdoar empréstimo: $e',
      ));
      return false;
    }
  }

  Future<bool> deleteLoan(String loanId) async {
    try {
      await _repository.deleteLoan(loanId);
      await loadLoans();
      return true;
    } catch (e) {
      emit(state.copyWith(
        status: P2PStatus.failure,
        errorMessage: 'Erro ao excluir empréstimo: $e',
      ));
      return false;
    }
  }

  Future<bool> renegotiateLoan(String loanId, int newInstallmentsCount, DateTime newFirstDueDate) async {
    try {
      await _repository.renegotiateLoan(loanId, newInstallmentsCount, newFirstDueDate);
      await loadLoans();
      return true;
    } catch (e) {
      emit(state.copyWith(
        status: P2PStatus.failure,
        errorMessage: 'Erro ao renegociar empréstimo: $e',
      ));
      return false;
    }
  }

  @override
  Future<void> close() {
    _authSubscription?.cancel();
    return super.close();
  }
}
