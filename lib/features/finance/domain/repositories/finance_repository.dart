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
  /// Avisa quando outro aparelho muda as despesas ou os moradores da casa.
  Stream<void> watchHouseChanges();
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
  Future<void> updateCategory(ExpenseCategory category);
  /// Recusa (com a mensagem pronta para a tela) a categoria que já tem lançamentos.
  /// Exclui a categoria. Com [moveToCategoryId], os lançamentos dela passam
  /// antes para essa outra categoria; sem ela, categoria em uso é recusada.
  Future<void> deleteCategory(String categoryId, {String? moveToCategoryId});
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

  /// Entradas e saídas da caixinha, da mais recente para a mais antiga.
  Future<List<SavingsTransaction>> getVaultTransactions(String vaultId, {int limit = 50, DateTime? before});
  Future<void> createSavingsVault(SavingsVault vault);
  Future<void> updateSavingsVault(SavingsVault vault);
  Future<void> deleteSavingsVault(String vaultId);
  Future<void> transferBetweenVaults({required String fromVaultId, required String toVaultId, required Money amount, required String description});
  /// Com [fromCycleStart], o valor sai do Caixa daquele ciclo (até o que as caixinhas devolveram a ele).
  Future<void> depositToVault({required String vaultId, required String memberId, required Money amount, required String description, DateTime? fromCycleStart});

  /// Saldo do que as caixinhas devolveram ao Caixa do ciclo (devoluções menos depósitos tirados dele).
  Future<Money> getVaultReturnsForCycle(FinancialCycle cycle);
  /// Com [returnToCycleStart], o valor resgatado volta para o Caixa daquele ciclo.
  Future<void> withdrawFromVault({required String vaultId, required String memberId, required Money amount, required String description, DateTime? returnToCycleStart});

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
