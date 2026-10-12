import '../../../../core/domain/enums/recurrence.dart';
import '../../../../core/domain/value_objects/financial_cycle.dart';
import '../../../../core/domain/value_objects/money.dart';
import '../../domain/entities/house_member.dart';
import '../../domain/entities/category.dart';
import '../../domain/entities/payment_method.dart';
import '../../domain/entities/house_expense.dart';
import '../../domain/entities/contribution.dart';
import '../../domain/entities/financial_cycle_summary.dart';
import '../../domain/entities/savings_vault.dart';
import '../../domain/entities/audit_entry.dart';

abstract class FinanceDataSource {
  Future<List<HouseMember>> getMembers();
  Future<List<ExpenseCategory>> getCategories();
  Future<List<PaymentMethod>> getPaymentMethods();

  Future<List<HouseExpense>> getExpensesForCycle(FinancialCycle cycle);
  Future<List<HouseExpense>> getExpensesForProject(String projectId);
  Future<List<Contribution>> getContributionsForCycle(FinancialCycle cycle);
  Future<FinancialCycleSummary> getCycleSummary(FinancialCycle cycle);

  Future<void> addExpense(HouseExpense expense);
  Future<void> updateExpense(
    HouseExpense expense, {
    RecurrenceScope scope = RecurrenceScope.thisInstanceOnly,
  });
  Future<void> deleteExpense(
    String expenseId, {
    RecurrenceScope scope = RecurrenceScope.thisInstanceOnly,
  });
  Future<List<HouseExpense>> getRecurringExpenses();

  Future<void> addContribution(Contribution contribution);
  Future<void> addCategory(ExpenseCategory category);
  Future<void> addPaymentMethod(PaymentMethod paymentMethod);
  Future<void> updatePaymentMethod(PaymentMethod paymentMethod);
  Future<void> deletePaymentMethod(String paymentMethodId);

  /// Atualiza o modelo de rateio da casa e os percentuais/aportes nominais de cada membro
  Future<void> updateHouseSplitModel({
    required String splitModel, // 'percentage', 'fixed', 'category'
    required Map<String, double> percentages,
    required Map<String, int> fixedAmountsCents,
  });

  // Caixinhas & Metas da Casa
  Future<List<SavingsVault>> getSavingsVaults();
  Future<void> createSavingsVault(SavingsVault vault);
  Future<void> depositToVault({
    required String vaultId,
    required String memberId,
    required Money amount,
    required String description,
  });
  Future<void> withdrawFromVault({
    required String vaultId,
    required String memberId,
    required Money amount,
    required String description,
  });

  // Auditoria da Casa
  Future<List<AuditEntry>> getAuditLog({String? entityId, int limit = 50});
}
