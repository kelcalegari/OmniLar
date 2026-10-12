import 'package:flutter/foundation.dart' show debugPrint;
import 'package:supabase_flutter/supabase_flutter.dart';
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

class SupabaseSettlementDataSource implements SettlementDataSource {
  final SupabaseClient client;
  final FinanceDataSource financeDataSource;
  final P2PDataSource p2pDataSource;
  final String Function() getCurrentHouseId;
  final House? Function()? getCurrentHouse;
  final GlobalClearingEngine engine;

  SupabaseSettlementDataSource({
    required this.client,
    required this.financeDataSource,
    required this.p2pDataSource,
    required this.getCurrentHouseId,
    this.getCurrentHouse,
    this.engine = const GlobalClearingEngine(),
  });

  String get _houseId => getCurrentHouseId();

  bool _isUuid(String? str) {
    if (str == null) return false;
    final uuidRegex = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    );
    return uuidRegex.hasMatch(str);
  }

  @override
  Future<SettlementSummary> getSettlementSummary(FinancialCycle cycle) async {
    final cycleStartStr = cycle.startDate.toIso8601String().split('T')[0];

    // 1. Verifica se já existe um fechamento gravado no Supabase para este ciclo
    try {
      final existingSettlement = await client
          .from('settlements')
          .select('*, settlement_transfers(*)')
          .eq('house_id', _houseId)
          .eq('cycle_start_date', cycleStartStr)
          .maybeSingle();

      if (existingSettlement != null &&
          (existingSettlement['status'] == 'confirmed' ||
              existingSettlement['status'] == 'completed')) {
        final rawTransfers =
            existingSettlement['settlement_transfers'] as List<dynamic>? ?? [];
        final transfers = rawTransfers.map<SuperPixTransfer>((r) {
          return SuperPixTransfer(
            id: r['id'] as String,
            fromMemberId: r['from_member_id'] as String,
            fromMemberName: 'Membro',
            toMemberId: r['to_member_id'] as String,
            toMemberName: 'Membro',
            amount: Money((r['amount_cents'] as num).toInt()),
            description: 'Compensação do Ciclo',
            status: r['status'] == 'confirmed'
                ? TransferStatus.confirmed
                : TransferStatus.pending,
            paidAt: r['paid_at'] != null
                ? DateTime.tryParse(r['paid_at'] as String)
                : null,
          );
        }).toList();

        return SettlementSummary(
          cycle: cycle,
          memberBalances: const [],
          transfers: transfers,
          totalHouseExpenses: Money(
            (existingSettlement['total_expenses_cents'] as num?)?.toInt() ?? 0,
          ),
          totalContributions: Money(
            (existingSettlement['total_contributions_cents'] as num?)
                    ?.toInt() ??
                0,
          ),
          totalP2PCleared: Money(
            (existingSettlement['total_cleared_p2p_cents'] as num?)?.toInt() ??
                0,
          ),
          houseTreasuryBalance: const Money.zero(),
          status: SettlementStatus.settled,
          settledAt: existingSettlement['settled_at'] != null
              ? DateTime.tryParse(existingSettlement['settled_at'] as String)
              : null,
        );
      }
    } catch (_) {
      // Continua para apuração dinâmica
    }

    // 2. Apuração dinâmica do ciclo
    final members = await financeDataSource.getMembers();
    final expenses = await financeDataSource.getExpensesForCycle(cycle);
    final contributions = await financeDataSource.getContributionsForCycle(
      cycle,
    );
    final loans = await p2pDataSource.getLoans();

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

    return engine.computeSettlement(
      cycle: cycle,
      members: members,
      expenses: expenses,
      contributions: contributions,
      loans: loans,
      customContributionTargets: customTargets,
      housePixKey: house?.pixKey,
      housePixKeyHolderName: house?.pixKeyHolderName,
    );
  }

  @override
  Future<void> confirmSettlement(
    SettlementSummary summary, {
    SettlementOptions? options,
  }) async {
    final now = DateTime.now();
    final cycleStartStr = summary.cycle.startDate.toIso8601String().split(
      'T',
    )[0];

    // 1. Se houver sobra no Caixa e a opção for guardar na Caixinha, efetua o depósito
    if (options?.surplusAction == SurplusAction.toVault &&
        options?.targetVaultId != null &&
        summary.houseTreasuryBalance.cents > 0) {
      final actorId =
          client.auth.currentUser?.id ??
          summary.memberBalances.firstOrNull?.memberId ??
          'user';
      try {
        await financeDataSource.depositToVault(
          vaultId: options!.targetVaultId!,
          memberId: actorId,
          amount: summary.houseTreasuryBalance,
          description:
              'Sobra do Fechamento do Ciclo ${summary.cycle.formattedPeriod}',
        );
      } catch (_) {}
    }

    // 2. Registra aportes compensatórios no Caixa da Casa
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

    // 2. Baixa contas pendentes do ciclo
    final expenses = await financeDataSource.getExpensesForCycle(summary.cycle);
    for (final exp in expenses) {
      if (exp.isPending) {
        await financeDataSource.updateExpense(
          exp.copyWith(status: ExpenseStatus.paid),
        );
      }
    }

    // 3. Processa resoluções parciais do Super Pix (criação de P2P ou saques em caixinha)
    if (options?.transferResolutions != null) {
      for (final t in summary.transfers) {
        final resolution = options!.transferResolutions[t.id];
        if (resolution != null && resolution.isPartialPayment) {
          if (resolution.shortfallAction == ShortfallAction.createP2PLoan) {
            try {
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
                createdAt: now,
                firstDueDate: newDueDate,
                installments: installments,
                repaymentMode: isNoDueDate
                    ? LoanRepaymentMode.openEnded
                    : LoanRepaymentMode.installments,
              );
              await p2pDataSource.createLoan(newLoan);
            } catch (e) {
              debugPrint('[Fechamento] Falha ao registrar acordo do saldo restante: $e');
            }
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
                  createdAt: now,
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
        }
      }
    }

    // 4. Quita parcelas P2P que venciam no ciclo
    final loans = await p2pDataSource.getLoans();
    for (final loan in loans) {
      // Mesma regra do motor: só parcelas em aberto de empréstimos cobrados no ciclo.
      for (final inst in loan.installmentsChargedIn(summary.cycle)) {
        await p2pDataSource.payInstallment(inst.id, inst.remainingAmount);
      }
    }

    // 5. Grava na tabela de liquidações do Supabase
    try {
      final currentUserId = client.auth.currentUser?.id;
      final settlementRow = {
        'house_id': _houseId,
        'cycle_start_date': cycleStartStr,
        'status': 'confirmed',
        'total_expenses_cents': summary.totalHouseExpenses.cents,
        'total_contributions_cents': summary.totalContributions.cents,
        'total_cleared_p2p_cents': summary.totalP2PCleared.cents,
        'settled_at': now.toIso8601String(),
        if (_isUuid(currentUserId)) 'settled_by': currentUserId,
      };

      final insertedSettlement = await client
          .from('settlements')
          .upsert(settlementRow, onConflict: 'house_id,cycle_start_date')
          .select()
          .single();

      final settlementId = insertedSettlement['id'] as String;

      // 6. Grava transferências P2P entre membros reais (registrando o valor efetivamente pago)
      final transfersToInsert = summary.transfers
          .where((t) => _isUuid(t.fromMemberId) && _isUuid(t.toMemberId))
          .map((t) {
            final resolution = options?.transferResolutions[t.id];
            final effectiveCents =
                (resolution != null && resolution.isPartialPayment)
                ? resolution.amountPaid.cents
                : t.amount.cents;

            return {
              'settlement_id': settlementId,
              'from_member_id': t.fromMemberId,
              'to_member_id': t.toMemberId,
              'amount_cents': effectiveCents,
              'status': 'confirmed',
              'paid_at': now.toIso8601String(),
            };
          })
          .toList();

      if (transfersToInsert.isNotEmpty) {
        await client.from('settlement_transfers').insert(transfersToInsert);
      }
    } catch (_) {
      // Ignora falhas de persistência de metadados se schema remoto não estiver acessível
    }
  }

  @override
  Future<void> reopenSettlement(FinancialCycle cycle) async {
    final cycleStartStr = cycle.startDate.toIso8601String().split('T')[0];
    try {
      await client
          .from('settlements')
          .delete()
          .eq('house_id', _houseId)
          .eq('cycle_start_date', cycleStartStr);
    } catch (_) {}
  }
}
