import '../entities/card_invoice.dart';
import '../../../../core/domain/enums/recurrence.dart';
import '../entities/house_initial_balance.dart';
import '../entities/house_settings.dart';
import '../entities/house_member.dart';
import '../entities/category.dart';
import '../entities/payment_method.dart';
import '../entities/house_expense.dart';
import '../entities/contribution.dart';
import '../entities/financial_cycle_summary.dart';
import '../entities/opening_inflows.dart';
import '../entities/savings_vault.dart';
import '../entities/third_party_receipt.dart';
import '../entities/house_inflow.dart';
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
  /// Resumo do ciclo. Com [expenses] e [contributions] já lidos do mesmo
  /// ciclo, reaproveita as listas em vez de buscá-las de novo.
  Future<FinancialCycleSummary> getCycleSummary(
    FinancialCycle cycle, {
    List<HouseExpense>? expenses,
    List<Contribution>? contributions,
  });

  /// Início da casa: o mais antigo entre a criação da casa e o lançamento mais
  /// antigo (despesa ou aporte). Null quando não se sabe.
  Future<DateTime?> getHouseStartDate();

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

  /// Renda mensal dos moradores que o usuário pode ler (0102): a própria
  /// sempre; as dos outros só se `houses.income_visibility` permitir. Quem não
  /// pode ver não recebe a renda: o filtro é do banco (RLS), não da tela.
  Future<Map<String, Money>> getMemberIncomes();

  /// Informa a própria renda mensal; nula limpa. Com a divisão "proporcional à
  /// renda", o banco refaz os percentuais.
  Future<void> setMyIncome(Money? income);

  /// Configurações de planejamento e fechamento da casa (0091).
  Future<HouseSettings> getHouseSettings();

  /// Grava só as chaves de [changes] (colunas de `houses`) e devolve o resultado.
  Future<HouseSettings> updateHouseSettings(Map<String, dynamic> changes);

  /// Dinheiro que a casa já tinha ao começar (0093).
  Future<HouseInitialBalance> getHouseInitialBalance();

  /// Grava a reserva guardada e o saldo na conta da casa (sobra do ciclo que
  /// começa em [cycleStart]). Gravar de novo troca os valores, sem somar.
  Future<HouseInitialBalance> setHouseInitialBalance({
    required Money reserve,
    required Money cash,
    required DateTime cycleStart,
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

  /// Dinheiro do início do ciclo por origem (sobra, empréstimos pagos de volta, resgates por caixinha).
  Future<OpeningInflows> getOpeningInflows(FinancialCycle cycle);
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

  // Entradas de terceiros (repasses guardados em caixinha)
  /// Entradas guardadas e as usadas recentemente, da mais nova para a mais antiga.
  Future<List<ThirdPartyReceipt>> getThirdPartyReceipts();

  /// Registra o dinheiro de fora que entrou na conta da Casa e o guarda na
  /// caixinha [vaultId] (sem tirar do Caixa do ciclo nem virar aporte).
  Future<void> registerThirdPartyReceipt({
    required String payerName,
    required Money amount,
    required DateTime receivedOn,
    required String vaultId,
    String? paymentMethodId,
    String? description,
  });

  /// Usa as entradas na fatura do cartão: o valor sai da caixinha.
  Future<void> useThirdPartyReceipts({
    required List<String> receiptIds,
    required ThirdPartyReceiptUse use,
    String? paymentMethodId,
    DateTime? invoiceDueDate,
  });

  /// Desfaz o uso: o valor volta para a caixinha. Sem [receiptIds], desfaz as
  /// entradas usadas na fatura de [paymentMethodId] que vence em [invoiceDueDate].
  Future<void> reopenThirdPartyReceipts({
    List<String>? receiptIds,
    String? paymentMethodId,
    DateTime? invoiceDueDate,
  });

  /// Exclui uma entrada ainda guardada: o valor sai da caixinha.
  Future<void> deleteThirdPartyReceipt(String receiptId);

  // Entradas de fora (dinheiro que entra no Caixa sem ser aporte, 0096)
  /// Entradas de fora que caem em [cycle], da mais nova para a mais antiga.
  Future<List<HouseInflow>> getHouseInflowsForCycle(FinancialCycle cycle);

  /// Lança uma entrada de fora no Caixa do ciclo do dia em que ela caiu.
  Future<void> addHouseInflow(HouseInflow inflow);

  /// Corrige valor, dia, descrição, origem ou despesa reembolsada.
  Future<void> updateHouseInflow(HouseInflow inflow);

  Future<void> deleteHouseInflow(String inflowId);
}
