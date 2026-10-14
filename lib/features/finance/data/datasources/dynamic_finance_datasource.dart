import '../../domain/entities/card_invoice.dart';
import '../../../../core/domain/enums/recurrence.dart';
import '../../../../core/domain/value_objects/financial_cycle.dart';
import '../../../../core/domain/value_objects/money.dart';
import '../../domain/entities/category.dart';
import '../../domain/entities/contribution.dart';
import '../../domain/entities/financial_cycle_summary.dart';
import '../../domain/entities/house_expense.dart';
import '../../domain/entities/house_member.dart';
import '../../domain/entities/payment_method.dart';
import '../../domain/entities/savings_vault.dart';
import '../../domain/entities/audit_entry.dart';
import 'finance_datasource.dart';

class DynamicFinanceDataSource implements FinanceDataSource {
  final FinanceDataSource remote;
  final FinanceDataSource mock;
  final bool Function() isDemoMode;

  DynamicFinanceDataSource({
    required this.remote,
    required this.mock,
    required this.isDemoMode,
  });

  FinanceDataSource get _active => isDemoMode() ? mock : remote;

  @override
  Stream<void> watchHouseChanges() => _active.watchHouseChanges();

  @override
  Future<List<HouseMember>> getMembers() => _active.getMembers();

  @override
  Future<List<ExpenseCategory>> getCategories() => _active.getCategories();

  @override
  Future<List<PaymentMethod>> getPaymentMethods() => _active.getPaymentMethods();

  @override
  Future<List<HouseExpense>> getExpensesForCycle(FinancialCycle cycle) =>
      _active.getExpensesForCycle(cycle);

  @override
  Future<List<HouseExpense>> getExpensesForProject(String projectId) =>
      _active.getExpensesForProject(projectId);

  @override
  Future<List<Contribution>> getContributionsForCycle(FinancialCycle cycle) =>
      _active.getContributionsForCycle(cycle);

  @override
  Future<Money> getOpeningBalance(FinancialCycle cycle) => _active.getOpeningBalance(cycle);

  @override
  Future<FinancialCycleSummary> getCycleSummary(FinancialCycle cycle) =>
      _active.getCycleSummary(cycle);

  @override
  Future<void> addExpense(HouseExpense expense) => _active.addExpense(expense);

  @override
  Future<void> updateExpense(
    HouseExpense expense, {
    RecurrenceScope scope = RecurrenceScope.thisInstanceOnly,
  }) =>
      _active.updateExpense(expense, scope: scope);

  @override
  Future<void> deleteExpense(
    String expenseId, {
    RecurrenceScope scope = RecurrenceScope.thisInstanceOnly,
  }) =>
      _active.deleteExpense(expenseId, scope: scope);

  @override
  Future<List<HouseExpense>> getRecurringExpenses() => _active.getRecurringExpenses();

  @override
  Future<void> addContribution(Contribution contribution) =>
      _active.addContribution(contribution);

  @override
  Future<void> addCategory(ExpenseCategory category) =>
      _active.addCategory(category);

  @override
  Future<void> updateCategory(ExpenseCategory category) =>
      _active.updateCategory(category);

  @override
  Future<void> deleteCategory(String categoryId) =>
      _active.deleteCategory(categoryId);

  @override
  Future<void> addPaymentMethod(PaymentMethod paymentMethod) =>
      _active.addPaymentMethod(paymentMethod);

  @override
  Future<void> updatePaymentMethod(PaymentMethod paymentMethod) =>
      _active.updatePaymentMethod(paymentMethod);

  @override
  Future<void> deletePaymentMethod(String paymentMethodId) =>
      _active.deletePaymentMethod(paymentMethodId);

  @override
  Future<String> getHouseSplitModel() => _active.getHouseSplitModel();

  @override
  Future<void> updateHouseSplitModel({
    required String splitModel,
    required Map<String, double> percentages,
    required Map<String, int> fixedAmountsCents,
  }) =>
      _active.updateHouseSplitModel(
        splitModel: splitModel,
        percentages: percentages,
        fixedAmountsCents: fixedAmountsCents,
      );

  @override
  Future<List<SavingsVault>> getSavingsVaults() => _active.getSavingsVaults();

  @override
  Future<List<SavingsTransaction>> getVaultTransactions(String vaultId) =>
      _active.getVaultTransactions(vaultId);

  @override
  Future<void> createSavingsVault(SavingsVault vault) =>
      _active.createSavingsVault(vault);

  @override
  Future<void> depositToVault({
    required String vaultId,
    required String memberId,
    required Money amount,
    required String description,
  }) =>
      _active.depositToVault(
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
      _active.withdrawFromVault(
        vaultId: vaultId,
        memberId: memberId,
        amount: amount,
        description: description,
      );

  @override
  Future<List<AuditEntry>> getAuditLog({String? entityId, int limit = 50}) =>
      _active.getAuditLog(entityId: entityId, limit: limit);

  @override
  Future<List<CardInvoice>> getOpenCardInvoices(String paymentMethodId) =>
      _active.getOpenCardInvoices(paymentMethodId);

  @override
  Future<void> payCardInvoice({
    required String paymentMethodId,
    required DateTime invoiceDueDate,
    required DateTime paidAt,
    bool paidByHouse = false,
  }) =>
      _active.payCardInvoice(
        paymentMethodId: paymentMethodId,
        invoiceDueDate: invoiceDueDate,
        paidAt: paidAt,
        paidByHouse: paidByHouse,
      );

  @override
  Future<List<CardInvoice>> getPaidCardInvoices(String paymentMethodId) =>
      _active.getPaidCardInvoices(paymentMethodId);

  @override
  Future<void> undoCardInvoicePayment({
    required String paymentMethodId,
    required DateTime invoiceDueDate,
  }) =>
      _active.undoCardInvoicePayment(
        paymentMethodId: paymentMethodId,
        invoiceDueDate: invoiceDueDate,
      );

  @override
  Future<List<CardInvoiceCode>> getCardInvoiceCodes() => _active.getCardInvoiceCodes();

  @override
  Future<void> saveCardInvoiceCode({
    required String paymentMethodId,
    required DateTime invoiceDueDate,
    String? barcode,
  }) =>
      _active.saveCardInvoiceCode(
        paymentMethodId: paymentMethodId,
        invoiceDueDate: invoiceDueDate,
        barcode: barcode,
      );
}
