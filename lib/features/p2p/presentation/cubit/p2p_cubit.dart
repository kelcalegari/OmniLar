import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/repositories/p2p_repository.dart';
import '../../domain/entities/p2p_loan.dart';
import '../../../../core/domain/value_objects/money.dart';
import 'p2p_state.dart';

class P2PCubit extends Cubit<P2PState> {
  final P2PRepository _repository;

  P2PCubit(this._repository) : super(const P2PState());

  Future<void> loadLoans() async {
    emit(state.copyWith(status: P2PStatus.loading));
    try {
      final loans = await _repository.getLoans();
      emit(state.copyWith(
        status: P2PStatus.success,
        allLoans: loans,
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

  Future<void> createLoan(P2PLoan loan) async {
    try {
      await _repository.createLoan(loan);
      await loadLoans();
    } catch (e) {
      emit(state.copyWith(
        status: P2PStatus.failure,
        errorMessage: 'Erro ao criar empréstimo: $e',
      ));
    }
  }

  Future<void> payInstallment(String installmentId, Money amount) async {
    try {
      await _repository.payInstallment(installmentId, amount);
      await loadLoans();
    } catch (e) {
      emit(state.copyWith(
        status: P2PStatus.failure,
        errorMessage: 'Erro ao registrar pagamento: $e',
      ));
    }
  }

  Future<void> forgiveLoan(String loanId) async {
    try {
      await _repository.forgiveLoan(loanId);
      await loadLoans();
    } catch (e) {
      emit(state.copyWith(
        status: P2PStatus.failure,
        errorMessage: 'Erro ao perdoar empréstimo: $e',
      ));
    }
  }

  Future<void> renegotiateLoan(String loanId, int newInstallmentsCount, DateTime newFirstDueDate) async {
    try {
      await _repository.renegotiateLoan(loanId, newInstallmentsCount, newFirstDueDate);
      await loadLoans();
    } catch (e) {
      emit(state.copyWith(
        status: P2PStatus.failure,
        errorMessage: 'Erro ao renegociar empréstimo: $e',
      ));
    }
  }
}
