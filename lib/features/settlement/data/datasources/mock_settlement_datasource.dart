import '../../domain/services/open_invoice_choices.dart';
import '../../../finance/domain/entities/split_rule.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import '../../../../core/domain/value_objects/financial_cycle.dart';
import '../../../../core/domain/value_objects/money.dart';
import '../../../finance/data/datasources/finance_datasource.dart';
import '../../../finance/domain/entities/contribution.dart';
import '../../../finance/domain/entities/house_expense.dart';
import '../../../p2p/data/datasources/p2p_datasource.dart';
import '../../../p2p/domain/entities/p2p_loan.dart';
import '../../../p2p/domain/services/p2p_calculator.dart';
import '../../domain/entities/settlement_options.dart';
import '../../domain/entities/settlement_summary.dart';
import '../../domain/entities/super_pix_transfer.dart';
import '../../domain/entities/transfer_settlement_resolution.dart';
import '../../../auth/domain/entities/house.dart';
import '../../domain/services/global_clearing_engine.dart';
import '../../domain/services/settlement_shortfall.dart';
import 'settlement_datasource.dart';

class MockSettlementDataSource implements SettlementDataSource {
  final FinanceDataSource financeDataSource;
  final P2PDataSource p2pDataSource;
  final House? Function()? getCurrentHouse;
  final GlobalClearingEngine engine;

  SettlementSummary? _cachedSettlement;

  // Ciclos reabertos: o que o fechamento anterior já registrou
  final _reopenedTransfers = <FinancialCycle, List<SuperPixTransfer>>{};
  final _surplusVaulted = <FinancialCycle, int>{};
  final _deficitCovered = <FinancialCycle, int>{};
  final _surplusRolled = <FinancialCycle, int>{};
  final _surplusRefunded = <FinancialCycle, int>{};
  final _houseShortfallSettled = <FinancialCycle, int>{};
  final _houseLoansReceived = <FinancialCycle, int>{};

  /// Sobra que o fechamento do ciclo imediatamente anterior deixou no Caixa.
  Money _openingBalance(FinancialCycle cycle) {
    for (final entry in _surplusRolled.entries) {
      final gap = cycle.startDate.difference(entry.key.endDate).inDays;
      if (gap >= 0 && gap <= 2) return Money(entry.value);
    }
    return const Money.zero();
  }

  MockSettlementDataSource({
    required this.financeDataSource,
    required this.p2pDataSource,
    this.getCurrentHouse,
    this.engine = const GlobalClearingEngine(),
  });

  @override
  Future<SettlementSummary> getSettlementSummary(
    FinancialCycle cycle, {
    SettlementOptions? options,
  }) async {
    // Se já estiver explicitamente liquidado neste ciclo, mantém o veredito arquivado
    if (_cachedSettlement != null &&
        _cachedSettlement!.cycle == cycle &&
        _cachedSettlement!.status == SettlementStatus.settled) {
      return _cachedSettlement!;
    }

    final members = await financeDataSource.getMembers();
    // Faturas em aberto: levadas adiante saem; as demais entram como pagas por quem foi escolhido
    final expenses = applyOpenInvoiceChoices(
      await financeDataSource.getExpensesForCycle(cycle),
      await financeDataSource.getPaymentMethods(),
      options?.openInvoiceChoices ?? const {},
      billChoices: options?.openBillChoices ?? const {},
    );
    final contributions = await financeDataSource.getContributionsForCycle(
      cycle,
    );
    final loans = await p2pDataSource.getLoans();

    // Se os membros possuem aportes fixos nominais definidos (ex: Balde Comum), usa como meta direta
    Map<String, Money>? customTargets;
    final hasFixedAmounts = members.any(
      (m) => (m.defaultFixedAmountCents ?? 0) > 0,
    );
    if (hasFixedAmounts) {
      customTargets = {
        for (final m in members)
          if ((m.defaultFixedAmountCents ?? 0) > 0)
            m.id: Money(m.defaultFixedAmountCents!),
      };
    }

    final house = getCurrentHouse?.call();

    // Caixinha escolhida para cobrir o excedente do balde (se houver)
    var deficitVaultBalance = const Money.zero();
    final deficitVaultId = options?.deficitVaultId;
    if (deficitVaultId != null) {
      final vaults = await financeDataSource.getSavingsVaults();
      deficitVaultBalance =
          vaults.where((v) => v.id == deficitVaultId).firstOrNull?.currentBalance ??
          const Money.zero();
    }

    final summary = engine.computeSettlement(
      cycle: cycle,
      members: members,
      expenses: expenses,
      contributions: contributions,
      loans: loans,
      customContributionTargets: customTargets,
      housePixKey: house?.pixKey,
      housePixKeyHolderName: house?.pixKeyHolderName,
      deficitSplit: options?.deficitSplit ?? DeficitSplit.proportional,
      deficitVaultBalance: deficitVaultBalance,
      surplusAlreadyVaulted: Money(_surplusVaulted[cycle] ?? 0),
      deficitAlreadyCovered: Money(_deficitCovered[cycle] ?? 0),
      openingBalance: _openingBalance(cycle),
      surplusAlreadyRolled: Money(_surplusRolled[cycle] ?? 0),
      surplusAlreadyRefunded: Money(_surplusRefunded[cycle] ?? 0),
      refundSurplus: options?.surplusAction == SurplusAction.refund,
      houseShortfallAlreadySettled: Money(_houseShortfallSettled[cycle] ?? 0),
      houseLoansAlreadyReceived: Money(_houseLoansReceived[cycle] ?? 0),
    ).copyWith(isReopened: _reopenedTransfers.containsKey(cycle));

    // Consultar outro ciclo não pode apagar um fechamento já arquivado
    if (_cachedSettlement?.status != SettlementStatus.settled) {
      _cachedSettlement = summary;
    }
    return summary;
  }

  @override
  Future<void> confirmSettlement(
    SettlementSummary summary, {
    SettlementOptions? options,
  }) async {
    // 0. Excedente do balde coberto pela Caixinha escolhida
    if (summary.deficitCoveredByVault.cents > 0 && options?.deficitVaultId != null) {
      _deficitCovered[summary.cycle] =
          (_deficitCovered[summary.cycle] ?? 0) + summary.deficitCoveredByVault.cents;
      await financeDataSource.withdrawFromVault(
        vaultId: options!.deficitVaultId!,
        memberId: summary.memberBalances.firstOrNull?.memberId ?? 'user',
        amount: summary.deficitCoveredByVault,
        description:
            'Cobertura do excedente do Ciclo ${summary.cycle.formattedPeriod}',
      );
    }

    // 1. Processa as transferências (integrais ou parciais)
    final confirmedTransfers = <SuperPixTransfer>[];
    for (final t in summary.transfers) {
      final resolution = options?.transferResolutions[t.id];

      if (resolution != null && resolution.isPartialPayment) {
        // Trata o shortfall (a diferença restante não coberta)
        if (resolution.shortfallAction == ShortfallAction.rolloverPending) {
          // Cobrado inteiro no próximo fechamento
          final newLoanId =
              'loan_pending_${summary.cycle.startDate.millisecondsSinceEpoch}_${t.fromMemberId}';
          final newDueDate = summary.cycle.endDate.add(const Duration(days: 1));
          await p2pDataSource.createLoan(
            P2PLoan(
              id: newLoanId,
              title: 'Pendência do Ciclo ${summary.cycle.formattedPeriod}',
              description:
                  'Saldo que ficou para o próximo fechamento: ${t.fromMemberName} pagou ${resolution.amountPaid.formatted} de ${t.amount.formatted}',
              totalAmount: resolution.shortfall,
              lenderMemberId: t.toMemberId,
              borrowerMemberId: t.fromMemberId,
              installmentsCount: 1,
              createdAt: DateTime.now(),
              firstDueDate: newDueDate,
              installments: P2PCalculator.generateInstallments(
                loanId: newLoanId,
                totalAmount: resolution.shortfall,
                installmentsCount: 1,
                firstDueDate: newDueDate,
              ),
            ),
          );
        } else if (resolution.shortfallAction == ShortfallAction.createP2PLoan) {
          final newLoanId =
              'loan_settle_${summary.cycle.startDate.millisecondsSinceEpoch}_${t.fromMemberId}';
          final isNoDueDate = resolution.loanHasNoDueDate;
          final newDueDate = isNoDueDate
              ? P2PLoan.openEndedPlaceholderDueDate
              : DateTime(
                  summary.cycle.endDate.year,
                  summary.cycle.endDate.month,
                  10,
                );
          final installments = isNoDueDate
              ? P2PCalculator.buildOpenEndedInstallment(
                loanId: newLoanId,
                totalAmount: resolution.shortfall,
              )
              : P2PCalculator.generateInstallments(
                loanId: newLoanId,
                totalAmount: resolution.shortfall,
                installmentsCount: resolution.loanInstallmentsCount,
                firstDueDate: newDueDate,
              );
          final newLoan = P2PLoan(
            id: newLoanId,
            title: isNoDueDate
                ? 'Acordo Livre: Saldo do Ciclo ${summary.cycle.formattedPeriod}'
                : 'Saldo restante do Ciclo ${summary.cycle.formattedPeriod}',
            description: isNoDueDate
                ? 'Financiamento sem prazo fixo: ${t.fromMemberName} pagou ${resolution.amountPaid.formatted} de ${t.amount.formatted}'
                : 'Financiamento do fechamento: ${t.fromMemberName} pagou ${resolution.amountPaid.formatted} de ${t.amount.formatted}',
            totalAmount: resolution.shortfall,
            lenderMemberId: t.toMemberId,
            borrowerMemberId: t.fromMemberId,
            installmentsCount: isNoDueDate ? 1 : resolution.loanInstallmentsCount,
            createdAt: DateTime.now(),
            firstDueDate: newDueDate,
            installments: installments,
            repaymentMode: isNoDueDate
                ? LoanRepaymentMode.openEnded
                : LoanRepaymentMode.installments,
          );
          await p2pDataSource.createLoan(newLoan);
        } else if (resolution.shortfallAction ==
                ShortfallAction.deductFromVault &&
            resolution.vaultId != null) {
          try {
            await financeDataSource.withdrawFromVault(
              vaultId: resolution.vaultId!,
              memberId: t.fromMemberId,
              amount: resolution.shortfall,
              description:
                  'Cobertura temporária do Fechamento do Ciclo ${summary.cycle.formattedPeriod}',
            );

            // Se o morador escolheu gerar Acordo de Reposição para a Caixinha
            if (resolution.vaultRepaymentMode != VaultRepaymentMode.grant) {
              final isNoDueDate = resolution.vaultRepaymentMode == VaultRepaymentMode.openEnded;
              final newLoanId =
                  'loan_vault_${summary.cycle.startDate.millisecondsSinceEpoch}_${t.fromMemberId}';
              final newDueDate = isNoDueDate
                  ? P2PLoan.openEndedPlaceholderDueDate
                  : DateTime(
                      summary.cycle.endDate.year,
                      summary.cycle.endDate.month,
                      10,
                    );
              final installmentsCount = isNoDueDate ? 1 : resolution.loanInstallmentsCount;
              final installments = isNoDueDate
                  ? P2PCalculator.buildOpenEndedInstallment(
                    loanId: newLoanId,
                    totalAmount: resolution.shortfall,
                  )
                  : P2PCalculator.generateInstallments(
                    loanId: newLoanId,
                    totalAmount: resolution.shortfall,
                    installmentsCount: installmentsCount,
                    firstDueDate: newDueDate,
                  );
              final vaultLoan = P2PLoan(
                id: newLoanId,
                title: isNoDueDate
                    ? 'Reposição da Caixinha (Livre / Sem Prazo)'
                    : 'Reposição da Caixinha (${installmentsCount}x)',
                description:
                    'Empréstimo do Lar: reposição para a Caixinha da Casa pela cobertura do Ciclo ${summary.cycle.formattedPeriod}',
                totalAmount: resolution.shortfall,
                lenderMemberId: P2PLoan.houseLenderId,
                borrowerMemberId: t.fromMemberId,
                installmentsCount: installmentsCount,
                createdAt: DateTime.now(),
                firstDueDate: newDueDate,
                installments: installments,
                repaymentMode: isNoDueDate
                    ? LoanRepaymentMode.openEnded
                    : LoanRepaymentMode.installments,
                repayToVaultId: resolution.vaultId,
              );
              await p2pDataSource.createLoan(vaultLoan);
            }
          } catch (e) {
            debugPrint('[Fechamento] Falha ao registrar acordo do saldo restante: $e');
          }
        }

        confirmedTransfers.add(
          t.copyWith(
            status: TransferStatus.confirmed,
            paidAt: DateTime.now(),
            amount: resolution.amountPaid,
            explanation:
                '${t.explanation ?? ""} (Parcial: ${resolution.amountPaid.formatted} pago, ${resolution.shortfall.formatted} financiado)',
          ),
        );
      } else {
        // Pagamento 100% integral
        confirmedTransfers.add(
          t.copyWith(status: TransferStatus.confirmed, paidAt: DateTime.now()),
        );
      }
    }

    // 2. Se houver sobra no Caixa e a opção for guardar na Caixinha, efetua o depósito
    // Quem pagou a menos ao Caixa: esse dinheiro não entrou, então não é sobra
    final surplus = availableSurplus(summary, options);
    _houseShortfallSettled[summary.cycle] =
        (_houseShortfallSettled[summary.cycle] ?? 0) + unpaidToHouse(summary, options).cents;
    // As parcelas de acordos com o Lar cobradas agora entram no Caixa deste ciclo
    _houseLoansReceived[summary.cycle] = summary.houseLoanReceipts.cents;
    if (options?.surplusAction == SurplusAction.toVault &&
        options?.targetVaultId != null &&
        surplus.cents > 0) {
      final actorId =
          summary.memberBalances.firstOrNull?.memberId ?? 'member_carlos';
      _surplusVaulted[summary.cycle] =
          (_surplusVaulted[summary.cycle] ?? 0) + surplus.cents;
      await financeDataSource.depositToVault(
        vaultId: options!.targetVaultId!,
        memberId: actorId,
        amount: surplus,
        description:
            'Sobra do Fechamento do Ciclo ${summary.cycle.formattedPeriod}',
      );
    }

    // Sobra deixada no Caixa como folga do próximo ciclo ou devolvida aos moradores
    if (options?.surplusAction == SurplusAction.rollover && surplus.cents > 0) {
      _surplusRolled[summary.cycle] =
          (_surplusRolled[summary.cycle] ?? 0) + surplus.cents;
    }
    if (summary.surplusRefunded.cents > 0) {
      _surplusRefunded[summary.cycle] =
          (_surplusRefunded[summary.cycle] ?? 0) + summary.surplusRefunded.cents;
    }

    // 3. Registra os aportes compensatórios no Caixa da Casa para equilibrar o saldo/fôlego
    for (final balance in summary.memberBalances) {
      final missingAporteCents =
          balance.contributionDue.cents - balance.contributionPaid.cents;
      // Sobra devolvida a quem já tinha aportado: sai do Caixa de volta para o morador
      if (balance.contributionRefund.cents > 0) {
        await financeDataSource.addContribution(
          Contribution(
            id: 'contrib_refund_${DateTime.now().microsecondsSinceEpoch}_${balance.memberId}',
            memberId: balance.memberId,
            amount: Money(-balance.contributionRefund.cents),
            date: summary.cycle.startDate,
            paymentMethodId: 'pm_pix',
          ),
        );
      }
      if (missingAporteCents > 0) {
        await financeDataSource.addContribution(
          Contribution(
            id: 'contrib_settle_${summary.cycle.startDate.millisecondsSinceEpoch}_${balance.memberId}',
            memberId: balance.memberId,
            amount: Money(missingAporteCents),
            date: summary.cycle.startDate,
            paymentMethodId: 'pm_pix',
          ),
        );
      }
    }

    // 4. Baixa as despesas do ciclo que estavam pendentes
    final expenses = applyOpenInvoiceChoices(
      await financeDataSource.getExpensesForCycle(summary.cycle),
      await financeDataSource.getPaymentMethods(),
      options?.openInvoiceChoices ?? const {},
      billChoices: options?.openBillChoices ?? const {},
    );
    // Congela o rateio: despesas que usaram o padrão da casa passam a carregar os
    // percentuais deste fechamento.
    final members = await financeDataSource.getMembers();
    final defaultSplit = SplitRule.percentage({
      for (final m in members) m.id: m.defaultSplitPercent,
    });
    HouseExpense frozen(HouseExpense exp) =>
        exp.settledAt == null &&
            exp.splitRule.type == SplitType.percentage &&
            (exp.splitRule.percentages == null || exp.splitRule.percentages!.isEmpty)
        ? exp.copyWith(splitRule: defaultSplit)
        : exp;

    for (final original in expenses) {
      final exp = frozen(original);
      // Tudo o que entra neste acerto: se o ciclo for reaberto, não é reembolsado de novo
      if (exp.isPaid && exp.settledAt == null) {
        await financeDataSource.updateExpense(exp.copyWith(settledAt: DateTime.now()));
      }
      if (exp.isPending) {
        await financeDataSource.updateExpense(
          exp.copyWith(
            status: ExpenseStatus.paid,
            settledAt: DateTime.now(),
            // A baixa pertence ao ciclo fechado, mesmo que o fechamento seja feito depois
            paidAt: DateTime.now().isAfter(summary.cycle.endDate)
                ? summary.cycle.endDate
                : DateTime.now(),
          ),
        );
      }
    }

    // 5. Quita as parcelas P2P que venciam neste ciclo
    final loans = await p2pDataSource.getLoans();
    for (final loan in loans) {
      // Mesma regra do motor: só parcelas em aberto de empréstimos cobrados no ciclo.
      for (final inst in loan.installmentsChargedIn(summary.cycle)) {
        await p2pDataSource.payInstallment(inst.id, inst.remainingAmount);
      }
    }

    // 6. Atualiza estado de liquidação arquivado
    _cachedSettlement = summary.copyWith(
      status: SettlementStatus.settled,
      // Ciclo reaberto: o histórico do fechamento anterior continua visível
      transfers: [...?_reopenedTransfers.remove(summary.cycle), ...confirmedTransfers],
      settledAt: DateTime.now(),
    );
  }

  @override
  Future<void> reopenSettlement(FinancialCycle cycle) async {
    if (_cachedSettlement != null && _cachedSettlement!.cycle == cycle) {
      // O que já foi acertado fica registrado; o novo fechamento cobra só a diferença
      _reopenedTransfers[cycle] = _cachedSettlement!.transfers;
      _cachedSettlement = null;
    }
  }

  @override
  Future<bool> isCycleSettled(FinancialCycle cycle) async =>
      _cachedSettlement?.cycle == cycle &&
      _cachedSettlement!.status == SettlementStatus.settled;
}
