import 'package:equatable/equatable.dart';
import '../../domain/entities/house_member.dart';
import '../../domain/entities/category.dart';
import '../../domain/entities/payment_method.dart';
import '../../domain/entities/house_expense.dart';
import '../../domain/entities/contribution.dart';
import '../../domain/entities/financial_cycle_summary.dart';
import '../../domain/entities/savings_vault.dart';
import '../../domain/entities/cycle_funding_estimate.dart';
import '../../../../core/domain/value_objects/money.dart';
import '../../../../core/domain/value_objects/financial_cycle.dart';

enum FinanceStatus { initial, loading, success, failure }

class FinanceState extends Equatable {
  final FinanceStatus status;
  final FinancialCycle currentCycle;
  final FinancialCycleSummary? summary;
  final CycleFundingEstimate? fundingEstimate;
  final FundingEstimateMode fundingEstimateMode;
  final Map<String, Money> customCategoryOverrides;
  final List<HouseExpense> expenses;
  final List<Contribution> contributions;
  final List<HouseMember> members;
  final List<ExpenseCategory> categories;
  final List<PaymentMethod> paymentMethods;
  final List<SavingsVault> savingsVaults;
  final String splitModel; // 'percentage', 'fixed' ou 'category'
  final String? errorMessage;

  const FinanceState({
    this.status = FinanceStatus.initial,
    required this.currentCycle,
    this.summary,
    this.fundingEstimate,
    this.fundingEstimateMode = FundingEstimateMode.historicalAverage,
    this.customCategoryOverrides = const {},
    this.expenses = const [],
    this.contributions = const [],
    this.members = const [],
    this.categories = const [],
    this.paymentMethods = const [],
    this.savingsVaults = const [],
    this.splitModel = 'percentage',
    this.errorMessage,
  });

  Money get totalSavings =>
      savingsVaults.fold(const Money.zero(), (total, v) => total + v.currentBalance);

  FinanceState copyWith({
    FinanceStatus? status,
    FinancialCycle? currentCycle,
    FinancialCycleSummary? summary,
    CycleFundingEstimate? fundingEstimate,
    FundingEstimateMode? fundingEstimateMode,
    Map<String, Money>? customCategoryOverrides,
    List<HouseExpense>? expenses,
    List<Contribution>? contributions,
    List<HouseMember>? members,
    List<ExpenseCategory>? categories,
    List<PaymentMethod>? paymentMethods,
    List<SavingsVault>? savingsVaults,
    String? splitModel,
    String? errorMessage,
  }) {
    return FinanceState(
      status: status ?? this.status,
      currentCycle: currentCycle ?? this.currentCycle,
      summary: summary ?? this.summary,
      fundingEstimate: fundingEstimate ?? this.fundingEstimate,
      fundingEstimateMode: fundingEstimateMode ?? this.fundingEstimateMode,
      customCategoryOverrides: customCategoryOverrides ?? this.customCategoryOverrides,
      expenses: expenses ?? this.expenses,
      contributions: contributions ?? this.contributions,
      members: members ?? this.members,
      categories: categories ?? this.categories,
      paymentMethods: paymentMethods ?? this.paymentMethods,
      savingsVaults: savingsVaults ?? this.savingsVaults,
      splitModel: splitModel ?? this.splitModel,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  @override
  List<Object?> get props => [
        status,
        currentCycle,
        summary,
        fundingEstimate,
        fundingEstimateMode,
        customCategoryOverrides,
        expenses,
        contributions,
        members,
        categories,
        paymentMethods,
        savingsVaults,
        splitModel,
        errorMessage,
      ];
}
