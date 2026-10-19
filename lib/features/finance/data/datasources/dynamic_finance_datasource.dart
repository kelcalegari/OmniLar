import '../../domain/entities/card_invoice.dart';
import '../../../../core/domain/enums/recurrence.dart';
import '../../domain/entities/house_initial_balance.dart';
import '../../domain/entities/house_settings.dart';
import '../../../../core/domain/value_objects/financial_cycle.dart';
import '../../../../core/domain/value_objects/money.dart';
import '../../domain/entities/category.dart';
import '../../domain/entities/contribution.dart';
import '../../domain/entities/financial_cycle_summary.dart';
import '../../domain/entities/opening_inflows.dart';
import '../../domain/entities/house_expense.dart';
import '../../domain/entities/house_member.dart';
import '../../domain/entities/payment_method.dart';
import '../../domain/entities/savings_vault.dart';
import '../../domain/entities/third_party_receipt.dart';
import '../../domain/entities/house_inflow.dart';
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
  Future<Money> getVaultReturnsForCycle(FinancialCycle cycle) =>
      _active.getVaultReturnsForCycle(cycle);

  @override
  Future<OpeningInflows> getOpeningInflows(FinancialCycle cycle) => _active.getOpeningInflows(cycle);

  @override
  Future<DateTime?> getHouseStartDate() => _active.getHouseStartDate();

  @override
  Future<FinancialCycleSummary> getCycleSummary(
    FinancialCycle cycle, {
    List<HouseExpense>? expenses,
    List<Contribution>? contributions,
  }) =>
      _active.getCycleSummary(cycle, expenses: expenses, contributions: contributions);

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
  Future<void> deleteCategory(String categoryId, {String? moveToCategoryId}) =>
      _active.deleteCategory(categoryId, moveToCategoryId: moveToCategoryId);

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
  Future<Map<String, Money>> getMemberIncomes() => _active.getMemberIncomes();

  @override
  Future<void> setMyIncome(Money? income) => _active.setMyIncome(income);

  @override
  Future<HouseSettings> getHouseSettings() => _active.getHouseSettings();

  @override
  Future<HouseSettings> updateHouseSettings(Map<String, dynamic> changes) =>
      _active.updateHouseSettings(changes);

  @override
  Future<HouseInitialBalance> getHouseInitialBalance() => _active.getHouseInitialBalance();

  @override
  Future<HouseInitialBalance> setHouseInitialBalance({
    required Money reserve,
    required Money cash,
    required DateTime cycleStart,
  }) =>
      _active.setHouseInitialBalance(reserve: reserve, cash: cash, cycleStart: cycleStart);

  @override
  Future<List<SavingsVault>> getSavingsVaults() => _active.getSavingsVaults();

  @override
  Future<List<SavingsTransaction>> getVaultTransactions(String vaultId, {int limit = 50, DateTime? before}) =>
      _active.getVaultTransactions(vaultId, limit: limit, before: before);

  @override
  Future<void> createSavingsVault(SavingsVault vault) =>
      _active.createSavingsVault(vault);

  @override
  Future<void> updateSavingsVault(SavingsVault vault) => _active.updateSavingsVault(vault);

  @override
  Future<void> deleteSavingsVault(String vaultId) => _active.deleteSavingsVault(vaultId);

  @override
  Future<void> transferBetweenVaults({
    required String fromVaultId,
    required String toVaultId,
    required Money amount,
    required String description,
  }) =>
      _active.transferBetweenVaults(
        fromVaultId: fromVaultId,
        toVaultId: toVaultId,
        amount: amount,
        description: description,
      );

  @override
  Future<void> depositToVault({
    required String vaultId,
    required String memberId,
    required Money amount,
    required String description,
    DateTime? fromCycleStart,
  }) =>
      _active.depositToVault(
        vaultId: vaultId,
        memberId: memberId,
        amount: amount,
        description: description,
        fromCycleStart: fromCycleStart,
      );

  @override
  Future<void> withdrawFromVault({
    required String vaultId,
    required String memberId,
    required Money amount,
    required String description,
    DateTime? returnToCycleStart,
  }) =>
      _active.withdrawFromVault(
        vaultId: vaultId,
        memberId: memberId,
        amount: amount,
        description: description,
        returnToCycleStart: returnToCycleStart,
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

  @override
  Future<List<ThirdPartyReceipt>> getThirdPartyReceipts() => _active.getThirdPartyReceipts();

  @override
  Future<void> registerThirdPartyReceipt({
    required String payerName,
    required Money amount,
    required DateTime receivedOn,
    required String vaultId,
    String? paymentMethodId,
    String? description,
  }) =>
      _active.registerThirdPartyReceipt(
        payerName: payerName,
        amount: amount,
        receivedOn: receivedOn,
        vaultId: vaultId,
        paymentMethodId: paymentMethodId,
        description: description,
      );

  @override
  Future<void> useThirdPartyReceipts({
    required List<String> receiptIds,
    required ThirdPartyReceiptUse use,
    String? paymentMethodId,
    DateTime? invoiceDueDate,
  }) =>
      _active.useThirdPartyReceipts(
        receiptIds: receiptIds,
        use: use,
        paymentMethodId: paymentMethodId,
        invoiceDueDate: invoiceDueDate,
      );

  @override
  Future<void> reopenThirdPartyReceipts({
    List<String>? receiptIds,
    String? paymentMethodId,
    DateTime? invoiceDueDate,
  }) =>
      _active.reopenThirdPartyReceipts(
        receiptIds: receiptIds,
        paymentMethodId: paymentMethodId,
        invoiceDueDate: invoiceDueDate,
      );

  @override
  Future<void> deleteThirdPartyReceipt(String receiptId) => _active.deleteThirdPartyReceipt(receiptId);

  @override
  Future<List<HouseInflow>> getHouseInflowsForCycle(FinancialCycle cycle) =>
      _active.getHouseInflowsForCycle(cycle);

  @override
  Future<void> addHouseInflow(HouseInflow inflow) => _active.addHouseInflow(inflow);

  @override
  Future<void> updateHouseInflow(HouseInflow inflow) => _active.updateHouseInflow(inflow);

  @override
  Future<void> deleteHouseInflow(String inflowId) => _active.deleteHouseInflow(inflowId);
}
