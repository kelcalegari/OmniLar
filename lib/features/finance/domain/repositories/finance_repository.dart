import '../entities/house_member.dart';
import '../entities/category.dart';
import '../entities/payment_method.dart';
import '../entities/house_expense.dart';
import '../entities/contribution.dart';
import '../entities/financial_cycle_summary.dart';
import '../../../../core/domain/value_objects/financial_cycle.dart';

abstract class FinanceRepository {
  Future<List<HouseMember>> getMembers();
  Future<List<ExpenseCategory>> getCategories();
  Future<List<PaymentMethod>> getPaymentMethods();

  Future<List<HouseExpense>> getExpensesForCycle(FinancialCycle cycle);
  Future<List<Contribution>> getContributionsForCycle(FinancialCycle cycle);
  Future<FinancialCycleSummary> getCycleSummary(FinancialCycle cycle);

  Future<void> addExpense(HouseExpense expense);
  Future<void> addContribution(Contribution contribution);
  Future<void> addCategory(ExpenseCategory category);
  Future<void> addPaymentMethod(PaymentMethod paymentMethod);
}
