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
import 'settlement_datasource.dart';

class MockSettlementDataSource implements SettlementDataSource {
  final FinanceDataSource financeDataSource;
  final P2PDataSource p2pDataSource;
  final House? Function()? getCurrentHouse;
  final GlobalClearingEngine engine;

  SettlementSummary? _cachedSettlement;

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
    final expenses = await financeDataSource.getExpensesForCycle(cycle);
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
    );

    _cachedSettlement = summary;
    return summary;
  }

  @override
  Future<void> confirmSettlement(
    SettlementSummary summary, {
    SettlementOptions? options,
  }) async {
    // 0. Excedente do balde coberto pela Caixinha escolhida
    if (summary.deficitCoveredByVault.cents > 0 && options?.deficitVaultId != null) {
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
        if (resolution.shortfallAction == ShortfallAction.createP2PLoan) {
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
    if (options?.surplusAction == SurplusAction.toVault &&
        options?.targetVaultId != null &&
        summary.houseTreasuryBalance.cents > 0) {
      final actorId =
          summary.memberBalances.firstOrNull?.memberId ?? 'member_carlos';
      await financeDataSource.depositToVault(
        vaultId: options!.targetVaultId!,
        memberId: actorId,
        amount: summary.houseTreasuryBalance,
        description:
            'Sobra do Fechamento do Ciclo ${summary.cycle.formattedPeriod}',
      );
    }

    // 3. Registra os aportes compensatórios no Caixa da Casa para equilibrar o saldo/fôlego
    for (final balance in summary.memberBalances) {
      final missingAporteCents =
          balance.contributionDue.cents - balance.contributionPaid.cents;
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
    final expenses = await financeDataSource.getExpensesForCycle(summary.cycle);
    for (final exp in expenses) {
      if (exp.isPending) {
        await financeDataSource.updateExpense(
          exp.copyWith(status: ExpenseStatus.paid),
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
      transfers: confirmedTransfers,
      settledAt: DateTime.now(),
    );
  }

  @override
  Future<void> reopenSettlement(FinancialCycle cycle) async {
    if (_cachedSettlement != null && _cachedSettlement!.cycle == cycle) {
      _cachedSettlement = null;
    }
  }
}
