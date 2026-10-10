import '../../domain/entities/house_member.dart';
import '../../domain/entities/category.dart';
import '../../domain/entities/payment_method.dart';
import '../../domain/entities/house_expense.dart';
import '../../domain/entities/contribution.dart';
import '../../domain/entities/financial_cycle_summary.dart';
import '../../domain/repositories/finance_repository.dart';
import '../datasources/mock_finance_datasource.dart';
import '../../domain/entities/savings_vault.dart';
import '../../../../core/domain/value_objects/money.dart';
import '../../../../core/domain/value_objects/financial_cycle.dart';

class FinanceRepositoryImpl implements FinanceRepository {
  final MockFinanceDataSource _dataSource;

  FinanceRepositoryImpl(this._dataSource);

  @override
  Future<List<HouseMember>> getMembers() => _dataSource.getMembers();

  @override
  Future<List<ExpenseCategory>> getCategories() => _dataSource.getCategories();

  @override
  Future<List<PaymentMethod>> getPaymentMethods() => _dataSource.getPaymentMethods();

  @override
  Future<List<HouseExpense>> getExpensesForCycle(FinancialCycle cycle) =>
      _dataSource.getExpensesForCycle(cycle);

  @override
  Future<List<Contribution>> getContributionsForCycle(FinancialCycle cycle) =>
      _dataSource.getContributionsForCycle(cycle);

  @override
  Future<FinancialCycleSummary> getCycleSummary(FinancialCycle cycle) =>
      _dataSource.getCycleSummary(cycle);

  @override
  Future<void> addExpense(HouseExpense expense) => _dataSource.addExpense(expense);

  @override
  Future<void> updateExpense(HouseExpense expense) => _dataSource.updateExpense(expense);

  @override
  Future<List<HouseExpense>> getRecurringExpenses() => _dataSource.getRecurringExpenses();

  @override
  Future<void> addContribution(Contribution contribution) =>
      _dataSource.addContribution(contribution);

  @override
  Future<void> addCategory(ExpenseCategory category) =>
      _dataSource.addCategory(category);

  @override
  Future<void> addPaymentMethod(PaymentMethod paymentMethod) =>
      _dataSource.addPaymentMethod(paymentMethod);

  @override
  Future<List<SavingsVault>> getSavingsVaults() => _dataSource.getSavingsVaults();

  @override
  Future<void> createSavingsVault(SavingsVault vault) => _dataSource.createSavingsVault(vault);

  @override
  Future<void> depositToVault({
    required String vaultId,
    required String memberId,
    required Money amount,
    required String description,
  }) =>
      _dataSource.depositToVault(
        vaultId: vaultId,
        memberId: memberId,
        amount: amount,
        description: description,
      );

  @override
  Future<void> withdrawFromVault({
    required String vaultId,
    required String memberId,
    required Money amount,
    required String description,
  }) =>
      _dataSource.withdrawFromVault(
        vaultId: vaultId,
        memberId: memberId,
        amount: amount,
        description: description,
      );
}
