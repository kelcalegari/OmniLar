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

  /// Avisos de mudança na casa feitos em outro aparelho (empréstimos e parcelas).
  final Stream<void> Function()? _houseChanges;
  StreamSubscription<void>? _houseChangesSubscription;
  Timer? _houseChangesDebounce;

  P2PCubit(this._repository, [this._authRepository, this._houseChanges])
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
    // Troca de conta ou de casa: o aviso volta a ser ligado para a casa nova
    _stopWatchingHouseChanges();
    emit(P2PState(currentUserId: _resolveInitialUserId(_authRepository)));
  }

  /// Liga o aviso de mudanças da casa, se ainda não estiver ligado. Enquanto a
  /// casa não carregou a fonte recusa; a próxima carga tenta de novo.
  void _watchHouseChanges() {
    final changes = _houseChanges;
    if (changes == null || _houseChangesSubscription != null || isClosed) return;
    try {
      _houseChangesSubscription = changes().listen(
        (_) {
          // Um pagamento gera vários avisos seguidos: recarrega uma vez só
          _houseChangesDebounce?.cancel();
          _houseChangesDebounce = Timer(const Duration(milliseconds: 600), () {
            if (!isClosed) _reloadQuietly();
          });
        },
        onError: (_) {},
      );
    } catch (_) {}
  }

  void _stopWatchingHouseChanges() {
    _houseChangesDebounce?.cancel();
    _houseChangesDebounce = null;
    _houseChangesSubscription?.cancel();
    _houseChangesSubscription = null;
  }

  /// Relê os empréstimos sem passar pelo estado de carregando.
  Future<void> _reloadQuietly() async {
    try {
      final loans = await _repository.getLoans();
      if (!isClosed) emit(state.copyWith(status: P2PStatus.success, allLoans: loans));
    } catch (_) {}
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
      _watchHouseChanges();
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

  Future<bool> acceptLoan(String loanId) async {
    try {
      await _repository.acceptLoan(loanId);
      await loadLoans();
      return true;
    } catch (e) {
      emit(state.copyWith(status: P2PStatus.failure, errorMessage: 'Erro ao aceitar o empréstimo: $e'));
      return false;
    }
  }

  /// Aprova ou recusa o empréstimo que passou do limite de aprovação da casa (0104).
  Future<bool> decideLoanApproval(String loanId, {required bool approve}) async {
    try {
      await _repository.decideLoanApproval(loanId, approve: approve);
      await loadLoans();
      return true;
    } catch (e) {
      emit(state.copyWith(
        status: P2PStatus.failure,
        errorMessage: 'Erro ao ${approve ? 'aprovar' : 'recusar'} o empréstimo: $e',
      ));
      return false;
    }
  }

  Future<bool> declineLoan(String loanId) async {
    try {
      await _repository.declineLoan(loanId);
      await loadLoans();
      return true;
    } catch (e) {
      emit(state.copyWith(status: P2PStatus.failure, errorMessage: 'Erro ao recusar o empréstimo: $e'));
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
    _stopWatchingHouseChanges();
    return super.close();
  }
}
