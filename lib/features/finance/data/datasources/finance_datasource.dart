import '../../domain/entities/card_invoice.dart';
import '../../../../core/domain/enums/recurrence.dart';
import '../../domain/entities/house_initial_balance.dart';
import '../../domain/entities/house_settings.dart';
import '../../../../core/domain/value_objects/financial_cycle.dart';
import '../../../../core/domain/value_objects/money.dart';
import '../../domain/entities/house_member.dart';
import '../../domain/entities/category.dart';
import '../../domain/entities/payment_method.dart';
import '../../domain/entities/house_expense.dart';
import '../../domain/entities/contribution.dart';
import '../../domain/entities/financial_cycle_summary.dart';
import '../../domain/entities/opening_inflows.dart';
import '../../domain/entities/savings_vault.dart';
import '../../domain/entities/third_party_receipt.dart';
import '../../domain/entities/house_inflow.dart';
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

  /// O mesmo dinheiro de [getOpeningBalance], separado por origem: cada tipo
  /// segue a regra que a casa escolheu para ele no rateio (0092).
  Future<OpeningInflows> getOpeningInflows(FinancialCycle cycle);
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
  Future<void> updateContribution(Contribution contribution);
  Future<void> deleteContribution(String contributionId);
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

  /// Cota de cada morador gravada no fechamento de [cycle] (memberId -> valor).
  /// Nulo se o ciclo não está fechado ou o fechamento não guardou o retrato.
  Future<Map<String, Money>?> getSettledContributionDues(FinancialCycle cycle);

  /// Grava a reserva guardada (na Reserva da Casa) e o saldo na conta da casa
  /// (sobra do ciclo que começa em [cycleStart]). Gravar de novo troca os
  /// valores, sem somar. Só administradores.
  Future<HouseInitialBalance> setHouseInitialBalance({
    required Money reserve,
    required Money cash,
    required DateTime cycleStart,
  });

  // Caixinhas & Metas da Casa
  Future<List<SavingsVault>> getSavingsVaults();

  /// Entradas e saídas da caixinha, da mais recente para a mais antiga.
  /// [before] pagina: traz só os lançamentos anteriores a essa data.
  Future<List<SavingsTransaction>> getVaultTransactions(String vaultId, {int limit = 50, DateTime? before});
  Future<void> createSavingsVault(SavingsVault vault);

  /// Muda nome, meta, prazo, ícone e cor (o saldo só muda por movimentação).
  Future<void> updateSavingsVault(SavingsVault vault);

  /// Exclui a caixinha: só com saldo zerado.
  Future<void> deleteSavingsVault(String vaultId);

  /// Tira de uma caixinha e põe na outra, com o mesmo motivo nos dois lados.
  Future<void> transferBetweenVaults({
    required String fromVaultId,
    required String toVaultId,
    required Money amount,
    required String description,
  });
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
