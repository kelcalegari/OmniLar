import 'package:omni_lar/features/finance/domain/entities/card_invoice.dart';
import 'package:flutter/material.dart';
import 'package:omni_lar/features/finance/domain/entities/house_settings.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/features/projects/data/repositories/mock_projects_repository.dart';
import 'package:omni_lar/features/projects/presentation/cubit/projects_cubit.dart';
import 'package:omni_lar/features/projects/presentation/pages/projects_hub_page.dart';
import 'package:omni_lar/features/finance/domain/repositories/finance_repository.dart';
import 'package:omni_lar/features/finance/domain/entities/financial_cycle_summary.dart';
import 'package:omni_lar/features/finance/domain/entities/opening_inflows.dart';
import 'package:omni_lar/features/finance/domain/entities/house_expense.dart';
import 'package:omni_lar/core/domain/enums/recurrence.dart';
import 'package:omni_lar/core/domain/value_objects/financial_cycle.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/features/finance/domain/entities/contribution.dart';
import 'package:omni_lar/features/finance/domain/entities/category.dart';
import 'package:omni_lar/features/finance/domain/entities/payment_method.dart';
import 'package:omni_lar/features/finance/domain/entities/house_member.dart';
import 'package:omni_lar/features/finance/domain/entities/savings_vault.dart';
import 'package:omni_lar/features/finance/domain/entities/third_party_receipt.dart';
import 'package:omni_lar/features/finance/domain/entities/audit_entry.dart';

class _FakeFinanceRepository implements FinanceRepository {
  @override
  Future<List<ThirdPartyReceipt>> getThirdPartyReceipts() async => [];
  @override
  Future<void> registerThirdPartyReceipt({
    required String payerName,
    required Money amount,
    required DateTime receivedOn,
    required String vaultId,
    String? paymentMethodId,
    String? description,
  }) async {}
  @override
  Future<void> useThirdPartyReceipts({
    required List<String> receiptIds,
    required ThirdPartyReceiptUse use,
    String? paymentMethodId,
    DateTime? invoiceDueDate,
  }) async {}
  @override
  Future<void> reopenThirdPartyReceipts({
    List<String>? receiptIds,
    String? paymentMethodId,
    DateTime? invoiceDueDate,
  }) async {}
  @override
  Future<void> deleteThirdPartyReceipt(String receiptId) async {}
  @override
  Future<List<CardInvoice>> getOpenCardInvoices(String paymentMethodId) async => [];
  @override
  Future<List<CardInvoice>> getPaidCardInvoices(String paymentMethodId) async => [];
  @override
  Future<void> undoCardInvoicePayment({
    required String paymentMethodId,
    required DateTime invoiceDueDate,
  }) async {}
  @override
  Future<void> payCardInvoice({
    required String paymentMethodId,
    required DateTime invoiceDueDate,
    required DateTime paidAt,
    bool paidByHouse = false,
  }) async {}
  @override
  Future<List<HouseExpense>> getExpensesForCycle(FinancialCycle cycle) async => [];
  @override
  Future<List<HouseExpense>> getExpensesForProject(String projectId) async => [];
  @override
  Future<List<Contribution>> getContributionsForCycle(FinancialCycle cycle) async => [];
  @override
  Future<FinancialCycleSummary> getCycleSummary(
    FinancialCycle cycle, {
    List<HouseExpense>? expenses,
    List<Contribution>? contributions,
  }) async =>
      throw UnimplementedError();
  @override
  Future<List<ExpenseCategory>> getCategories() async => [];
  @override
  Future<void> updateCategory(ExpenseCategory category) async {}
  @override
  Stream<void> watchHouseChanges() => const Stream.empty();
  @override
  Future<void> deleteCategory(String categoryId, {String? moveToCategoryId}) async {}
  @override
  Future<List<PaymentMethod>> getPaymentMethods() async => [];
  @override
  Future<List<HouseMember>> getMembers() async => [];
  @override
  Future<List<HouseExpense>> getRecurringExpenses() async => [];
  @override
  Future<void> addExpense(HouseExpense expense) async {}
  @override
  Future<void> updateExpense(HouseExpense expense, {RecurrenceScope scope = RecurrenceScope.thisInstanceOnly}) async {}
  @override
  Future<void> deleteExpense(String expenseId, {RecurrenceScope scope = RecurrenceScope.thisInstanceOnly}) async {}
  @override
  Future<void> addContribution(Contribution contribution) async {}
  @override
  Future<void> addCategory(ExpenseCategory category) async {}
  @override
  Future<void> addPaymentMethod(PaymentMethod paymentMethod) async {}
  @override
  Future<void> updatePaymentMethod(PaymentMethod paymentMethod) async {}
  @override
  Future<void> deletePaymentMethod(String paymentMethodId) async {}
  @override
  Future<String> getHouseSplitModel() async => 'percentage';
  @override
  Future<HouseSettings> getHouseSettings() async => const HouseSettings();
  @override
  Future<HouseSettings> updateHouseSettings(Map<String, dynamic> changes) async =>
      HouseSettings.fromJson(changes);
  @override
  Future<void> updateHouseSplitModel({
    required String splitModel,
    required Map<String, double> percentages,
    required Map<String, int> fixedAmountsCents,
  }) async {}
  @override
  Future<List<SavingsVault>> getSavingsVaults() async => [];
  @override
  Future<List<SavingsTransaction>> getVaultTransactions(String vaultId, {int limit = 50, DateTime? before}) async => [];
  @override
  Future<void> updateSavingsVault(SavingsVault vault) async {}
  @override
  Future<void> deleteSavingsVault(String vaultId) async {}
  @override
  Future<void> transferBetweenVaults({required String fromVaultId, required String toVaultId, required Money amount, required String description}) async {}
  @override
  Future<void> createSavingsVault(SavingsVault vault) async {}
  @override
  Future<void> depositToVault({required String vaultId, required String memberId, required Money amount, required String description, DateTime? fromCycleStart}) async {}
  @override
  Future<Money> getVaultReturnsForCycle(FinancialCycle cycle) async => const Money.zero();
  @override
  Future<OpeningInflows> getOpeningInflows(FinancialCycle cycle) async => const OpeningInflows();
  @override
  Future<DateTime?> getHouseStartDate() async => null;
  @override
  Future<void> withdrawFromVault({required String vaultId, required String memberId, required Money amount, required String description, DateTime? returnToCycleStart}) async {}
  @override
  Future<List<AuditEntry>> getAuditLog({String? entityId, int limit = 50}) async => [];
  @override
  Future<List<CardInvoiceCode>> getCardInvoiceCodes() async => [];
  @override
  Future<void> saveCardInvoiceCode({
    required String paymentMethodId,
    required DateTime invoiceDueDate,
    String? barcode,
  }) async {}
}

void main() {
  testWidgets('ProjectsHubPage renderiza lista inicial de projetos e botão de novo projeto', (tester) async {
    final mockRepo = MockProjectsRepository();
    final fakeFinance = _FakeFinanceRepository();
    final cubit = ProjectsCubit(
      projectsRepository: mockRepo,
      financeRepository: fakeFinance,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<ProjectsCubit>.value(
          value: cubit,
          child: const ProjectsHubPage(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Projetos & Viagens'), findsOneWidget);
    expect(find.text('Rateios Delimitados'), findsOneWidget);
    expect(find.text('Férias em Floripa 🏖️'), findsOneWidget);
    expect(find.text('Reforma da Cozinha & Bancada 🛠️'), findsOneWidget);
    expect(find.byIcon(Icons.add_rounded), findsOneWidget);
  });
}
