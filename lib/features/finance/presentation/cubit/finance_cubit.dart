import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/repositories/finance_repository.dart';
import '../../domain/entities/house_expense.dart';
import '../../domain/entities/contribution.dart';
import '../../domain/entities/category.dart';
import '../../domain/entities/payment_method.dart';
import '../../domain/entities/savings_vault.dart';
import '../../../../core/domain/value_objects/money.dart';
import '../../../../core/domain/value_objects/financial_cycle.dart';
import 'finance_state.dart';

class FinanceCubit extends Cubit<FinanceState> {
  final FinanceRepository _repository;
  static const int defaultCycleStartDay = 5;

  FinanceCubit(this._repository)
      : super(
          FinanceState(
            currentCycle: FinancialCycle.fromDate(
              date: DateTime.now(),
              cycleStartDay: defaultCycleStartDay,
            ),
          ),
        );

  Future<void> loadCycleData({FinancialCycle? cycle}) async {
    final targetCycle = cycle ?? state.currentCycle;
    emit(state.copyWith(status: FinanceStatus.loading, currentCycle: targetCycle));

    try {
      final members = await _repository.getMembers();
      final categories = await _repository.getCategories();
      final paymentMethods = await _repository.getPaymentMethods();
      final summary = await _repository.getCycleSummary(targetCycle);
      final expenses = await _repository.getExpensesForCycle(targetCycle);
      final contributions = await _repository.getContributionsForCycle(targetCycle);
      final vaults = await _repository.getSavingsVaults();

      emit(state.copyWith(
        status: FinanceStatus.success,
        currentCycle: targetCycle,
        summary: summary,
        expenses: expenses,
        contributions: contributions,
        members: members,
        categories: categories,
        paymentMethods: paymentMethods,
        savingsVaults: vaults,
      ));
    } catch (e) {
      emit(state.copyWith(
        status: FinanceStatus.failure,
        errorMessage: 'Erro ao carregar dados do ciclo: $e',
      ));
    }
  }

  void nextCycle() {
    final next = state.currentCycle.next(defaultCycleStartDay);
    loadCycleData(cycle: next);
  }

  void previousCycle() {
    final prev = state.currentCycle.previous(defaultCycleStartDay);
    loadCycleData(cycle: prev);
  }

  Future<void> addExpense(HouseExpense expense) async {
    try {
      await _repository.addExpense(expense);
      await loadCycleData(cycle: state.currentCycle);
    } catch (e) {
      emit(state.copyWith(
        status: FinanceStatus.failure,
        errorMessage: 'Erro ao adicionar despesa: $e',
      ));
    }
  }

  Future<void> addContribution(Contribution contribution) async {
    try {
      await _repository.addContribution(contribution);
      await loadCycleData(cycle: state.currentCycle);
    } catch (e) {
      emit(state.copyWith(
        status: FinanceStatus.failure,
        errorMessage: 'Erro ao registrar aporte: $e',
      ));
    }
  }

  Future<void> addCategory(ExpenseCategory category) async {
    try {
      await _repository.addCategory(category);
      await loadCycleData(cycle: state.currentCycle);
    } catch (e) {
      emit(state.copyWith(
        status: FinanceStatus.failure,
        errorMessage: 'Erro ao cadastrar categoria: $e',
      ));
    }
  }

  Future<void> addPaymentMethod(PaymentMethod paymentMethod) async {
    try {
      await _repository.addPaymentMethod(paymentMethod);
      await loadCycleData(cycle: state.currentCycle);
    } catch (e) {
      emit(state.copyWith(
        status: FinanceStatus.failure,
        errorMessage: 'Erro ao cadastrar forma de pagamento: $e',
      ));
    }
  }

  // --- Ações de Caixinhas & Metas da Casa (Dinheiro Blindado) ---
  Future<void> createSavingsVault(SavingsVault vault) async {
    try {
      await _repository.createSavingsVault(vault);
      await loadCycleData(cycle: state.currentCycle);
    } catch (e) {
      emit(state.copyWith(
        status: FinanceStatus.failure,
        errorMessage: 'Erro ao criar caixinha: $e',
      ));
    }
  }

  Future<void> depositToVault({
    required String vaultId,
    required String memberId,
    required Money amount,
    required String description,
  }) async {
    try {
      await _repository.depositToVault(
        vaultId: vaultId,
        memberId: memberId,
        amount: amount,
        description: description,
      );
      await loadCycleData(cycle: state.currentCycle);
    } catch (e) {
      emit(state.copyWith(
        status: FinanceStatus.failure,
        errorMessage: 'Erro ao guardar dinheiro na caixinha: $e',
      ));
    }
  }

  Future<void> withdrawFromVault({
    required String vaultId,
    required String memberId,
    required Money amount,
    required String description,
  }) async {
    try {
      await _repository.withdrawFromVault(
        vaultId: vaultId,
        memberId: memberId,
        amount: amount,
        description: description,
      );
      await loadCycleData(cycle: state.currentCycle);
    } catch (e) {
      emit(state.copyWith(
        status: FinanceStatus.failure,
        errorMessage: 'Erro ao resgatar dinheiro da caixinha: $e',
      ));
    }
  }
}
