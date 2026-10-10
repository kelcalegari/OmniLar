import 'package:equatable/equatable.dart';
import '../../domain/entities/house_member.dart';
import '../../domain/entities/category.dart';
import '../../domain/entities/payment_method.dart';
import '../../domain/entities/house_expense.dart';
import '../../domain/entities/contribution.dart';
import '../../domain/entities/financial_cycle_summary.dart';
import '../../domain/entities/savings_vault.dart';
import '../../../../core/domain/value_objects/money.dart';
import '../../../../core/domain/value_objects/financial_cycle.dart';

enum FinanceStatus { initial, loading, success, failure }

class FinanceState extends Equatable {
  final FinanceStatus status;
  final FinancialCycle currentCycle;
  final FinancialCycleSummary? summary;
  final List<HouseExpense> expenses;
  final List<Contribution> contributions;
  final List<HouseMember> members;
  final List<ExpenseCategory> categories;
  final List<PaymentMethod> paymentMethods;
  final List<SavingsVault> savingsVaults;
  final String? errorMessage;

  const FinanceState({
    this.status = FinanceStatus.initial,
    required this.currentCycle,
    this.summary,
    this.expenses = const [],
    this.contributions = const [],
    this.members = const [],
    this.categories = const [],
    this.paymentMethods = const [],
    this.savingsVaults = const [],
    this.errorMessage,
  });

  Money get totalSavings =>
      savingsVaults.fold(const Money.zero(), (total, v) => total + v.currentBalance);

  FinanceState copyWith({
    FinanceStatus? status,
    FinancialCycle? currentCycle,
    FinancialCycleSummary? summary,
    List<HouseExpense>? expenses,
    List<Contribution>? contributions,
    List<HouseMember>? members,
    List<ExpenseCategory>? categories,
    List<PaymentMethod>? paymentMethods,
    List<SavingsVault>? savingsVaults,
    String? errorMessage,
  }) {
    return FinanceState(
      status: status ?? this.status,
      currentCycle: currentCycle ?? this.currentCycle,
      summary: summary ?? this.summary,
      expenses: expenses ?? this.expenses,
      contributions: contributions ?? this.contributions,
      members: members ?? this.members,
      categories: categories ?? this.categories,
      paymentMethods: paymentMethods ?? this.paymentMethods,
      savingsVaults: savingsVaults ?? this.savingsVaults,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  @override
  List<Object?> get props => [
        status,
        currentCycle,
        summary,
        expenses,
        contributions,
        members,
        categories,
        paymentMethods,
        savingsVaults,
        errorMessage,
      ];
}
