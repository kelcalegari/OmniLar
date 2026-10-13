import '../entities/card_invoice.dart';
import '../../../../core/domain/enums/recurrence.dart';
import '../entities/house_member.dart';
import '../entities/category.dart';
import '../entities/payment_method.dart';
import '../entities/house_expense.dart';
import '../entities/contribution.dart';
import '../entities/financial_cycle_summary.dart';
import '../entities/savings_vault.dart';
import '../entities/audit_entry.dart';
import '../../../../core/domain/value_objects/money.dart';
import '../../../../core/domain/value_objects/financial_cycle.dart';

abstract class FinanceRepository {
  Future<List<HouseMember>> getMembers();
  Future<List<ExpenseCategory>> getCategories();
  Future<List<PaymentMethod>> getPaymentMethods();

  /// Despesas da Casa no ciclo. NÃO inclui despesas vinculadas a projetos
  /// compartilhados (essas vivem apenas no projeto).
  Future<List<HouseExpense>> getExpensesForCycle(FinancialCycle cycle);

  /// Todas as despesas de um projeto compartilhado, independente do ciclo.
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
  /// Modelo de rateio da casa: 'percentage', 'fixed' ou 'category'
  Future<String> getHouseSplitModel();
  Future<void> updateHouseSplitModel({
    required String splitModel,
    required Map<String, double> percentages,
    required Map<String, int> fixedAmountsCents,
  });

  // Caixinhas & Metas da Casa (Dinheiro Blindado)
  Future<List<SavingsVault>> getSavingsVaults();
  Future<void> createSavingsVault(SavingsVault vault);
  Future<void> depositToVault({required String vaultId, required String memberId, required Money amount, required String description});
  Future<void> withdrawFromVault({required String vaultId, required String memberId, required Money amount, required String description});

  // Auditoria da Casa
  Future<List<AuditEntry>> getAuditLog({String? entityId, int limit = 50});

  // Faturas de cartão
  /// Faturas do cartão cujo pagamento ainda não foi registrado.
  Future<List<CardInvoice>> getOpenCardInvoices(String paymentMethodId);

  /// Registra o dia em que a fatura que vence em [invoiceDueDate] foi paga.
  Future<void> payCardInvoice({
    required String paymentMethodId,
    required DateTime invoiceDueDate,
    required DateTime paidAt,
  });

  /// Faturas do cartão com pagamento registrado (recentes).
  Future<List<CardInvoice>> getPaidCardInvoices(String paymentMethodId);

  /// Desfaz o registro de pagamento da fatura que vence em [invoiceDueDate].
  Future<void> undoCardInvoicePayment({
    required String paymentMethodId,
    required DateTime invoiceDueDate,
  });
}
