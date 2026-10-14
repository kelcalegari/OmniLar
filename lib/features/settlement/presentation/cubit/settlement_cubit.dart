import '../../../../core/domain/value_objects/cycle_schedule.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/domain/value_objects/financial_cycle.dart';
import '../../../finance/domain/repositories/finance_repository.dart';
import '../../domain/entities/settlement_options.dart';
import '../../domain/entities/settlement_summary.dart';
import '../../domain/entities/transfer_settlement_resolution.dart';
import '../../domain/repositories/settlement_repository.dart';
import '../../domain/services/open_invoice_choices.dart';
import '../../../finance/domain/entities/house_expense.dart';
import '../../../finance/domain/services/cycle_expense_grouping.dart';
import '../../../finance/domain/services/pending_payment.dart';
import 'settlement_state.dart';

class SettlementCubit extends BlocBase<SettlementState> {
  final SettlementRepository _repository;
  final FinanceRepository? _financeRepository;

  SettlementCubit(this._repository, [this._financeRepository])
    : super(const SettlementState());

  Future<void> loadSettlement(FinancialCycle cycle) async {
    emit(
      state.copyWith(
        status: SettlementCubitStatus.loading,
        currentCycle: cycle,
      ),
    );
    try {
      final summary = await _repository.getSettlementSummary(
        cycle,
        options: state.options,
      );

      // Carrega as Caixinhas da Casa para permitir seleção no fechamento
      var vaults = state.vaults;
      if (_financeRepository != null && vaults.isEmpty) {
        try {
          vaults = await _financeRepository.getSavingsVaults();
        } catch (_) {}
      }

      final defaultVaultId =
          state.options.targetVaultId ?? vaults.firstOrNull?.id;
      final options = state.options.copyWith(targetVaultId: defaultVaultId);
      final openInvoices = await _loadOpenInvoices(cycle);
      final openBills = await _loadOpenBills(cycle);

      emit(
        state.copyWith(
          status: SettlementCubitStatus.loaded,
          currentCycle: cycle,
          summary: summary,
          vaults: vaults,
          options: options,
          openInvoices: openInvoices,
          openBills: openBills,
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(
          status: SettlementCubitStatus.error,
          errorMessage: 'Erro ao carregar o fechamento do ciclo: $e',
        ),
      );
    }
  }

  /// Faturas de cartão em aberto que pesam no ciclo (sem a fonte das despesas,
  /// nenhuma).
  Future<List<CardInvoiceEntry>> _loadOpenInvoices(FinancialCycle cycle) async {
    final finance = _financeRepository;
    if (finance == null) return const [];
    try {
      return openInvoicesOf(
        await finance.getExpensesForCycle(cycle),
        await finance.getPaymentMethods(),
      );
    } catch (_) {
      return const [];
    }
  }

  Future<List<HouseExpense>> _loadOpenBills(FinancialCycle cycle) async {
    final finance = _financeRepository;
    if (finance == null) return const [];
    try {
      return openBillsOf(
        await finance.getExpensesForCycle(cycle),
        await finance.getPaymentMethods(),
      );
    } catch (_) {
      return const [];
    }
  }

  /// Meio de pagamento (ou levar adiante) de uma conta pendente: recalcula o
  /// fechamento na hora.
  Future<void> updateOpenBillChoice(String expenseId, String choice) => _applyDeficitOptions(
        state.options.copyWith(
          openBillChoices: {...state.options.openBillChoices, expenseId: choice},
        ),
      );

  /// O que fazer com uma fatura em aberto: recalcula o fechamento na hora.
  Future<void> updateOpenInvoiceChoice(String invoiceKey, OpenInvoiceChoice choice) =>
      _applyDeficitOptions(
        state.options.copyWith(
          openInvoiceChoices: {...state.options.openInvoiceChoices, invoiceKey: choice},
        ),
      );

  /// Registra o pagamento das faturas em aberto que vão receber baixa neste
  /// fechamento, dentro do ciclo, por quem foi escolhido.
  Future<void> _payOpenInvoices(FinancialCycle cycle) async {
    final finance = _financeRepository;
    if (finance == null) return;
    final now = DateTime.now();
    final paidAt = now.isAfter(cycle.endDate) ? cycle.endDate : now;
    for (final invoice in state.openInvoices) {
      final choice = state.options.openInvoiceChoices[invoice.key] ??
          defaultOpenInvoiceChoice(invoice.card);
      if (choice == OpenInvoiceChoice.carryOver) continue;
      await finance.payCardInvoice(
        paymentMethodId: invoice.card.id,
        invoiceDueDate: invoice.dueDate,
        paidAt: paidAt,
        paidByHouse: choice == OpenInvoiceChoice.paidByHouse,
      );
    }

    // Contas pendentes que recebem baixa: pagas com o meio escolhido
    if (state.openBills.isEmpty) return;
    final methods = await finance.getPaymentMethods();
    for (final bill in state.openBills) {
      final choice = state.options.openBillChoices[bill.id] ?? defaultBillMethodId(bill, methods);
      if (choice == carryOverBill) continue;
      final method = methods.where((m) => m.id == choice).firstOrNull;
      if (method == null) continue;
      await finance.updateExpense(paidWith(bill, paidOn: paidAt, method: method));
    }
  }

  void previousCycle(CycleSchedule schedule) {
    final cycle = state.currentCycle ?? state.summary?.cycle;
    if (cycle != null) {
      loadSettlement(schedule.previous(cycle));
    }
  }

  void nextCycle(CycleSchedule schedule) {
    final cycle = state.currentCycle ?? state.summary?.cycle;
    if (cycle != null) {
      loadSettlement(schedule.next(cycle));
    }
  }

  void updateSurplusAction(SurplusAction action) {
    final previous = state.options.surplusAction;
    final options = state.options.copyWith(surplusAction: action);
    // Devolver a sobra muda o aporte devido de cada morador: recalcula o Super Pix
    if (action != previous &&
        (action == SurplusAction.refund || previous == SurplusAction.refund)) {
      _applyDeficitOptions(options);
      return;
    }
    emit(state.copyWith(options: options));
  }

  void updateTargetVaultId(String vaultId) {
    emit(
      state.copyWith(options: state.options.copyWith(targetVaultId: vaultId)),
    );
  }

  void updateCreditAction(MemberCreditAction action) {
    emit(state.copyWith(options: state.options.copyWith(creditAction: action)));
  }

  /// Como ratear o que passou do balde: recalcula o Super Pix na hora.
  Future<void> updateDeficitSplit(DeficitSplit split) =>
      _applyDeficitOptions(state.options.copyWith(deficitSplit: split));

  /// Caixinha que cobre o excedente antes do rateio (null = não usar caixinha).
  Future<void> updateDeficitVault(String? vaultId) => _applyDeficitOptions(
    vaultId == null
        ? state.options.copyWith(clearDeficitVault: true)
        : state.options.copyWith(deficitVaultId: vaultId),
  );

  Future<void> _applyDeficitOptions(SettlementOptions options) async {
    final cycle = state.currentCycle ?? state.summary?.cycle;
    // As transferências mudam: resoluções decididas antes deixam de valer.
    final nextOptions = options.copyWith(transferResolutions: const {});
    emit(state.copyWith(options: nextOptions));
    if (cycle == null) return;

    try {
      final summary = await _repository.getSettlementSummary(
        cycle,
        options: nextOptions,
      );
      emit(
        state.copyWith(status: SettlementCubitStatus.loaded, summary: summary),
      );
    } catch (e) {
      emit(
        state.copyWith(
          status: SettlementCubitStatus.error,
          errorMessage: 'Erro ao recalcular o fechamento do ciclo: $e',
        ),
      );
    }
  }

  void updateTransferResolution(TransferSettlementResolution resolution) {
    final updatedMap = Map<String, TransferSettlementResolution>.from(
      state.options.transferResolutions,
    );
    updatedMap[resolution.transferId] = resolution;
    emit(
      state.copyWith(
        options: state.options.copyWith(transferResolutions: updatedMap),
      ),
    );
  }

  void removeTransferResolution(String transferId) {
    final updatedMap = Map<String, TransferSettlementResolution>.from(
      state.options.transferResolutions,
    );
    updatedMap.remove(transferId);
    emit(
      state.copyWith(
        options: state.options.copyWith(transferResolutions: updatedMap),
      ),
    );
  }

  Future<void> confirmSettlement() async {
    final currentSummary = state.summary;
    if (currentSummary == null) return;

    emit(state.copyWith(status: SettlementCubitStatus.confirming));
    try {
      // Faturas em aberto que recebem baixa: o pagamento é registrado antes, e
      // o fechamento já as calculou como pagas por quem foi escolhido
      await _payOpenInvoices(currentSummary.cycle);

      // Recalcula antes de gravar: se alguém pagou ou lançou algo com a tela
      // aberta (ex: antecipou uma parcela P2P), o Super Pix exibido está defasado.
      final freshSummary = await _repository.getSettlementSummary(
        currentSummary.cycle,
        options: state.options,
      );
      if (_fingerprint(freshSummary) != _fingerprint(currentSummary)) {
        emit(
          state.copyWith(
            status: SettlementCubitStatus.error,
            errorMessage:
                'Os valores mudaram desde que você abriu o fechamento. Revise as transferências e confirme de novo.',
          ),
        );
        emit(
          state.copyWith(
            status: SettlementCubitStatus.loaded,
            summary: freshSummary,
            // As resoluções foram decididas sobre transferências que não valem mais.
            options: state.options.copyWith(transferResolutions: const {}),
          ),
        );
        return;
      }

      // Os valores são os que o admin revisou; a versão dos dados é a da
      // releitura de agora, que o banco confere ao gravar.
      await _repository.confirmSettlement(
        currentSummary.copyWith(dataVersion: freshSummary.dataVersion),
        options: state.options,
      );
      final updatedSummary = await _repository.getSettlementSummary(
        currentSummary.cycle,
      );
      emit(
        state.copyWith(
          status: SettlementCubitStatus.settled,
          summary: updatedSummary,
          openInvoices: await _loadOpenInvoices(currentSummary.cycle),
          openBills: await _loadOpenBills(currentSummary.cycle),
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(
          status: SettlementCubitStatus.error,
          errorMessage: 'Erro ao confirmar liquidação: $e',
        ),
      );
    }
  }

  /// Resumo dos valores que o usuário revisou: totais e transferências do Super Pix.
  String _fingerprint(SettlementSummary summary) {
    final transfers = summary.transfers
        .map((t) => '${t.fromMemberId}>${t.toMemberId}:${t.amount.cents}')
        .toList()
      ..sort();
    return [
      summary.status.name,
      summary.totalHouseExpenses.cents,
      summary.totalContributions.cents,
      summary.totalP2PCleared.cents,
      ...transfers,
    ].join('|');
  }

  Future<void> reopenSettlement() async {
    final cycle = state.currentCycle ?? state.summary?.cycle;
    if (cycle == null) return;

    emit(state.copyWith(status: SettlementCubitStatus.loading));
    try {
      await _repository.reopenSettlement(cycle);
      final refreshed = await _repository.getSettlementSummary(
        cycle,
        options: state.options,
      );
      emit(
        state.copyWith(
          status: SettlementCubitStatus.loaded,
          summary: refreshed,
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(
          status: SettlementCubitStatus.error,
          errorMessage: 'Erro ao reabrir ciclo: $e',
        ),
      );
    }
  }
}
