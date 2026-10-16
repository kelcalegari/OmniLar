import '../../domain/entities/card_invoice.dart';
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

/// Aviso único (banco e modo demo) para a categoria que não pode ser excluída.
String categoryInUseMessage(int count) => count == 1
    ? 'Esta categoria tem 1 lançamento. Troque a categoria dele ou edite o nome em vez de excluir.'
    : 'Esta categoria tem $count lançamentos. Troque a categoria deles ou edite o nome em vez de excluir.';

abstract class FinanceDataSource {
  Future<List<HouseMember>> getMembers();
  Stream<void> watchHouseChanges();
  Future<List<ExpenseCategory>> getCategories();
  Future<List<PaymentMethod>> getPaymentMethods();

  Future<List<HouseExpense>> getExpensesForCycle(FinancialCycle cycle);
  Future<List<HouseExpense>> getExpensesForProject(String projectId);
  Future<List<Contribution>> getContributionsForCycle(FinancialCycle cycle);

  /// Dinheiro da casa no Caixa no início do ciclo: a sobra que o fechamento
  /// anterior deixou mais os resgates de caixinha devolvidos ao ciclo.
  Future<Money> getOpeningBalance(FinancialCycle cycle);

  /// Resgates de caixinha devolvidos ao Caixa deste ciclo, menos os depósitos
  /// em caixinha tirados dele.
  Future<Money> getVaultReturnsForCycle(FinancialCycle cycle);
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
  Future<void> updateCategory(ExpenseCategory category);
  /// Exclui a categoria. Com [moveToCategoryId], os lançamentos dela passam
  /// antes para essa outra categoria; sem ela, categoria em uso é recusada.
  Future<void> deleteCategory(String categoryId, {String? moveToCategoryId});
  Future<void> addPaymentMethod(PaymentMethod paymentMethod);
  Future<void> updatePaymentMethod(PaymentMethod paymentMethod);
  Future<void> deletePaymentMethod(String paymentMethodId);

  /// Atualiza o modelo de rateio da casa e os percentuais/aportes nominais de cada membro
  /// Modelo de rateio da casa: 'percentage', 'fixed' ou 'category'
  Future<String> getHouseSplitModel();
  Future<void> updateHouseSplitModel({
    required String splitModel, // 'percentage', 'fixed', 'category'
    required Map<String, double> percentages,
    required Map<String, int> fixedAmountsCents,
  });

  // Caixinhas & Metas da Casa
  Future<List<SavingsVault>> getSavingsVaults();

  /// Entradas e saídas da caixinha, da mais recente para a mais antiga.
  Future<List<SavingsTransaction>> getVaultTransactions(String vaultId);
  Future<void> createSavingsVault(SavingsVault vault);
  Future<void> depositToVault({
    required String vaultId,
    required String memberId,
    required Money amount,
    required String description,
    DateTime? fromCycleStart,
  });
  Future<void> withdrawFromVault({
    required String vaultId,
    required String memberId,
    required Money amount,
    required String description,
    DateTime? returnToCycleStart,
  });

  // Auditoria da Casa
  Future<List<AuditEntry>> getAuditLog({String? entityId, int limit = 50});

  // Faturas de cartão
  /// Faturas do cartão cujo pagamento ainda não foi registrado.
  Future<List<CardInvoice>> getOpenCardInvoices(String paymentMethodId);

  /// Registra o dia em que a fatura que vence em [invoiceDueDate] foi paga.
  /// [paidByHouse]: a fatura saiu do Caixa da Casa (sem reembolso ao titular).
  Future<void> payCardInvoice({
    required String paymentMethodId,
    required DateTime invoiceDueDate,
    required DateTime paidAt,
    bool paidByHouse = false,
  });

  /// Faturas do cartão com pagamento registrado (recentes).
  Future<List<CardInvoice>> getPaidCardInvoices(String paymentMethodId);

  /// Desfaz o registro de pagamento da fatura que vence em [invoiceDueDate].
  Future<void> undoCardInvoicePayment({
    required String paymentMethodId,
    required DateTime invoiceDueDate,
  });

  /// Códigos de boleto guardados nas faturas recentes da casa.
  Future<List<CardInvoiceCode>> getCardInvoiceCodes();

  /// Guarda o código do boleto da fatura que vence em [invoiceDueDate];
  /// [barcode] nulo apaga o código.
  Future<void> saveCardInvoiceCode({
    required String paymentMethodId,
    required DateTime invoiceDueDate,
    String? barcode,
  });
}
