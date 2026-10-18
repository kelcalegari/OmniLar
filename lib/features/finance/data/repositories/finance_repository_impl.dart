import '../../domain/entities/card_invoice.dart';
import '../../../../core/network/offline_queue.dart';
import '../../domain/entities/house_initial_balance.dart';
import '../../domain/entities/house_settings.dart';
import '../../../../core/network/offline_sync_service.dart';
import '../../../../core/utils/uuid.dart';
import '../offline/house_expense_offline_codec.dart';
import '../../domain/entities/house_member.dart';
import '../../domain/entities/category.dart';
import '../../domain/entities/payment_method.dart';
import '../../domain/entities/house_expense.dart';
import '../../domain/entities/contribution.dart';
import '../../domain/entities/financial_cycle_summary.dart';
import '../../domain/entities/opening_inflows.dart';
import '../../domain/repositories/finance_repository.dart';
import '../datasources/finance_datasource.dart';
import '../../domain/entities/savings_vault.dart';
import '../../domain/entities/third_party_receipt.dart';
import '../../domain/entities/house_inflow.dart';
import '../../domain/entities/audit_entry.dart';
import '../../../../core/domain/enums/recurrence.dart';
import '../../../../core/domain/value_objects/money.dart';
import '../../../../core/domain/value_objects/financial_cycle.dart';

class FinanceRepositoryImpl implements FinanceRepository {
  final FinanceDataSource _dataSource;
  final OfflineSyncService? _offlineSync;

  FinanceRepositoryImpl(this._dataSource, [this._offlineSync]);

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
  Future<List<HouseExpense>> getExpensesForProject(String projectId) =>
      _dataSource.getExpensesForProject(projectId);

  @override
  Future<List<Contribution>> getContributionsForCycle(FinancialCycle cycle) =>
      _dataSource.getContributionsForCycle(cycle);

  @override
  Future<FinancialCycleSummary> getCycleSummary(
    FinancialCycle cycle, {
    List<HouseExpense>? expenses,
    List<Contribution>? contributions,
  }) =>
      _dataSource.getCycleSummary(cycle, expenses: expenses, contributions: contributions);

  @override
  Future<void> addExpense(HouseExpense expense) async {
    final sync = _offlineSync;
    if (sync == null || !sync.isActive) return _dataSource.addExpense(expense);

    // O id definitivo nasce no aparelho: reenviar depois não duplica a despesa
    final withId = isUuid(expense.id) ? expense : expense.copyWith(id: generateUuidV4());
    await sync.runOrQueue(
      OfflineActionType.addExpense,
      () => houseExpenseToJson(withId),
      () => _dataSource.addExpense(withId),
    );
  }

  @override
  Future<void> updateExpense(
    HouseExpense expense, {
    RecurrenceScope scope = RecurrenceScope.thisInstanceOnly,
  }) =>
      _dataSource.updateExpense(expense, scope: scope);

  @override
  Future<void> deleteExpense(
    String expenseId, {
    RecurrenceScope scope = RecurrenceScope.thisInstanceOnly,
  }) =>
      _dataSource.deleteExpense(expenseId, scope: scope);

  @override
  Future<List<HouseExpense>> getRecurringExpenses() => _dataSource.getRecurringExpenses();

  @override
  Future<void> addContribution(Contribution contribution) =>
      _dataSource.addContribution(contribution);

  @override
  Future<void> addCategory(ExpenseCategory category) =>
      _dataSource.addCategory(category);

  @override
  Stream<void> watchHouseChanges() => _dataSource.watchHouseChanges();

  @override
  Future<void> updateCategory(ExpenseCategory category) =>
      _dataSource.updateCategory(category);

  @override
  Future<void> deleteCategory(String categoryId, {String? moveToCategoryId}) =>
      _dataSource.deleteCategory(categoryId, moveToCategoryId: moveToCategoryId);

  @override
  Future<void> addPaymentMethod(PaymentMethod paymentMethod) =>
      _dataSource.addPaymentMethod(paymentMethod);

  @override
  Future<void> updatePaymentMethod(PaymentMethod paymentMethod) =>
      _dataSource.updatePaymentMethod(paymentMethod);

  @override
  Future<void> deletePaymentMethod(String paymentMethodId) =>
      _dataSource.deletePaymentMethod(paymentMethodId);

  @override
  Future<String> getHouseSplitModel() => _dataSource.getHouseSplitModel();

  @override
  Future<void> updateHouseSplitModel({
    required String splitModel,
    required Map<String, double> percentages,
    required Map<String, int> fixedAmountsCents,
  }) =>
      _dataSource.updateHouseSplitModel(
        splitModel: splitModel,
        percentages: percentages,
        fixedAmountsCents: fixedAmountsCents,
      );

  @override
  Future<HouseSettings> getHouseSettings() => _dataSource.getHouseSettings();

  @override
  Future<HouseSettings> updateHouseSettings(Map<String, dynamic> changes) =>
      _dataSource.updateHouseSettings(changes);

  @override
  Future<HouseInitialBalance> getHouseInitialBalance() => _dataSource.getHouseInitialBalance();

  @override
  Future<HouseInitialBalance> setHouseInitialBalance({
    required Money reserve,
    required Money cash,
    required DateTime cycleStart,
  }) =>
      _dataSource.setHouseInitialBalance(reserve: reserve, cash: cash, cycleStart: cycleStart);

  @override
  Future<List<SavingsVault>> getSavingsVaults() => _dataSource.getSavingsVaults();

  @override
  Future<List<SavingsTransaction>> getVaultTransactions(String vaultId, {int limit = 50, DateTime? before}) =>
      _dataSource.getVaultTransactions(vaultId, limit: limit, before: before);

  @override
  Future<void> updateSavingsVault(SavingsVault vault) => _dataSource.updateSavingsVault(vault);

  @override
  Future<void> deleteSavingsVault(String vaultId) => _dataSource.deleteSavingsVault(vaultId);

  @override
  Future<void> transferBetweenVaults({
    required String fromVaultId,
    required String toVaultId,
    required Money amount,
    required String description,
  }) =>
      _dataSource.transferBetweenVaults(
        fromVaultId: fromVaultId,
        toVaultId: toVaultId,
        amount: amount,
        description: description,
      );

  @override
  Future<DateTime?> getHouseStartDate() => _dataSource.getHouseStartDate();

  @override
  Future<Money> getVaultReturnsForCycle(FinancialCycle cycle) =>
      _dataSource.getVaultReturnsForCycle(cycle);

  @override
  Future<OpeningInflows> getOpeningInflows(FinancialCycle cycle) => _dataSource.getOpeningInflows(cycle);

  @override
  Future<void> createSavingsVault(SavingsVault vault) => _dataSource.createSavingsVault(vault);

  @override
  Future<void> depositToVault({
    required String vaultId,
    required String memberId,
    required Money amount,
    required String description,
    DateTime? fromCycleStart,
  }) =>
      _dataSource.depositToVault(
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
      _dataSource.withdrawFromVault(
        vaultId: vaultId,
        memberId: memberId,
        amount: amount,
        description: description,
        returnToCycleStart: returnToCycleStart,
      );

  @override
  Future<List<AuditEntry>> getAuditLog({String? entityId, int limit = 50}) =>
      _dataSource.getAuditLog(entityId: entityId, limit: limit);

  @override
  Future<List<CardInvoice>> getOpenCardInvoices(String paymentMethodId) =>
      _dataSource.getOpenCardInvoices(paymentMethodId);

  @override
  Future<void> payCardInvoice({
    required String paymentMethodId,
    required DateTime invoiceDueDate,
    required DateTime paidAt,
    bool paidByHouse = false,
  }) =>
      _dataSource.payCardInvoice(
        paymentMethodId: paymentMethodId,
        invoiceDueDate: invoiceDueDate,
        paidAt: paidAt,
        paidByHouse: paidByHouse,
      );

  @override
  Future<List<CardInvoice>> getPaidCardInvoices(String paymentMethodId) =>
      _dataSource.getPaidCardInvoices(paymentMethodId);

  @override
  Future<void> undoCardInvoicePayment({
    required String paymentMethodId,
    required DateTime invoiceDueDate,
  }) =>
      _dataSource.undoCardInvoicePayment(
        paymentMethodId: paymentMethodId,
        invoiceDueDate: invoiceDueDate,
      );

  @override
  Future<List<CardInvoiceCode>> getCardInvoiceCodes() => _dataSource.getCardInvoiceCodes();

  @override
  Future<void> saveCardInvoiceCode({
    required String paymentMethodId,
    required DateTime invoiceDueDate,
    String? barcode,
  }) =>
      _dataSource.saveCardInvoiceCode(
        paymentMethodId: paymentMethodId,
        invoiceDueDate: invoiceDueDate,
        barcode: barcode,
      );

  @override
  Future<List<ThirdPartyReceipt>> getThirdPartyReceipts() => _dataSource.getThirdPartyReceipts();

  @override
  Future<void> registerThirdPartyReceipt({
    required String payerName,
    required Money amount,
    required DateTime receivedOn,
    required String vaultId,
    String? paymentMethodId,
    String? description,
  }) =>
      _dataSource.registerThirdPartyReceipt(
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
      _dataSource.useThirdPartyReceipts(
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
      _dataSource.reopenThirdPartyReceipts(
        receiptIds: receiptIds,
        paymentMethodId: paymentMethodId,
        invoiceDueDate: invoiceDueDate,
      );

  @override
  Future<void> deleteThirdPartyReceipt(String receiptId) => _dataSource.deleteThirdPartyReceipt(receiptId);

  @override
  Future<List<HouseInflow>> getHouseInflowsForCycle(FinancialCycle cycle) =>
      _dataSource.getHouseInflowsForCycle(cycle);

  @override
  Future<void> addHouseInflow(HouseInflow inflow) => _dataSource.addHouseInflow(inflow);

  @override
  Future<void> updateHouseInflow(HouseInflow inflow) => _dataSource.updateHouseInflow(inflow);

  @override
  Future<void> deleteHouseInflow(String inflowId) => _dataSource.deleteHouseInflow(inflowId);
}
