import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/domain/value_objects/financial_cycle.dart';
import '../../../../core/domain/value_objects/money.dart';
import '../../../../core/errors/failures.dart';
import '../../../finance/data/datasources/finance_datasource.dart';
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
  Future<SettlementSummary> getSettlementSummary(
    FinancialCycle cycle, {
    SettlementOptions? options,
  }) async {
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
                ? DateTime.tryParse(r['paid_at'] as String)?.toLocal()
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
              ? DateTime.tryParse(existingSettlement['settled_at'] as String)?.toLocal()
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

    // Caixinha escolhida para cobrir o excedente do balde (se houver)
    var deficitVaultBalance = const Money.zero();
    final deficitVaultId = options?.deficitVaultId;
    if (deficitVaultId != null) {
      final vaults = await financeDataSource.getSavingsVaults();
      deficitVaultBalance =
          vaults.where((v) => v.id == deficitVaultId).firstOrNull?.currentBalance ??
          const Money.zero();
    }

    return engine.computeSettlement(
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
  }

  @override
  Future<void> confirmSettlement(
    SettlementSummary summary, {
    SettlementOptions? options,
  }) async {
    final cycle = summary.cycle;
    final actorId = client.auth.currentUser?.id;
    String dateOnly(DateTime d) => d.toIso8601String().split('T')[0];

    final vaultOperations = <Map<String, dynamic>>[];
    final newLoans = <Map<String, dynamic>>[];

    // 1. Sobra do Caixa guardada na Caixinha
    if (options?.surplusAction == SurplusAction.toVault &&
        options?.targetVaultId != null &&
        summary.houseTreasuryBalance.cents > 0) {
      vaultOperations.add({
        'vault_id': options!.targetVaultId,
        'member_id': actorId,
        'type': 'deposit',
        'amount_cents': summary.houseTreasuryBalance.cents,
        'description': 'Sobra do Fechamento do Ciclo ${cycle.formattedPeriod}',
      });
    }

    // Excedente do balde coberto pela Caixinha escolhida
    if (summary.deficitCoveredByVault.cents > 0 && options?.deficitVaultId != null) {
      vaultOperations.add({
        'vault_id': options!.deficitVaultId,
        'member_id': actorId,
        'type': 'withdraw',
        'amount_cents': summary.deficitCoveredByVault.cents,
        'description': 'Cobertura do excedente do Ciclo ${cycle.formattedPeriod}',
      });
    }

    // 2. Aportes compensatórios no Caixa da Casa
    final contributions = [
      for (final balance in summary.memberBalances)
        if (_isUuid(balance.memberId) &&
            balance.contributionDue.cents > balance.contributionPaid.cents)
          {
            'member_id': balance.memberId,
            'amount_cents':
                balance.contributionDue.cents - balance.contributionPaid.cents,
          },
    ];

    // 3. Contas pendentes do ciclo
    final expenses = await financeDataSource.getExpensesForCycle(cycle);
    final expenseIds = [
      for (final exp in expenses)
        if (exp.isPending && _isUuid(exp.id)) exp.id,
    ];

    // 4. Parcelas P2P cobradas neste fechamento (mesma regra do motor)
    final loans = await p2pDataSource.getLoans();
    final installmentPayments = [
      for (final loan in loans)
        for (final inst in loan.installmentsChargedIn(cycle))
          if (_isUuid(inst.id) && inst.remainingAmount.cents > 0)
            {
              'installment_id': inst.id,
              'amount_cents': inst.remainingAmount.cents,
            },
    ];

    // 5. Quem pagou a menos no Super Pix: acordo P2P ou cobertura pela Caixinha
    Map<String, dynamic> loanPlan({
      required String? lenderId,
      required String borrowerId,
      required String title,
      required String description,
      required Money total,
      required bool noDueDate,
      required int installmentsCount,
    }) {
      final firstDueDate = noDueDate
          ? P2PLoan.openEndedPlaceholderDueDate
          : DateTime(cycle.endDate.year, cycle.endDate.month, 10);
      final installments = noDueDate
          ? P2PCalculator.buildOpenEndedInstallment(
              loanId: 'settlement',
              totalAmount: total,
            )
          : P2PCalculator.generateInstallments(
              loanId: 'settlement',
              totalAmount: total,
              installmentsCount: installmentsCount,
              firstDueDate: firstDueDate,
            );
      return {
        'lender_id': lenderId,
        'borrower_id': borrowerId,
        'title': title,
        'description': description,
        'total_amount_cents': total.cents,
        'repayment_mode': noDueDate ? 'open_ended' : 'installments',
        'installments': [
          for (final inst in installments)
            {
              'number': inst.number,
              'amount_cents': inst.amount.cents,
              'due_date': dateOnly(inst.dueDate),
            },
        ],
      };
    }

    for (final t in summary.transfers) {
      final resolution = options?.transferResolutions[t.id];
      if (resolution == null || !resolution.isPartialPayment) continue;
      if (!_isUuid(t.fromMemberId)) continue;

      if (resolution.shortfallAction == ShortfallAction.createP2PLoan) {
        if (!_isUuid(t.toMemberId)) continue;
        final noDueDate = resolution.loanHasNoDueDate;
        newLoans.add(
          loanPlan(
            lenderId: t.toMemberId,
            borrowerId: t.fromMemberId,
            title: noDueDate
                ? 'Acordo Livre: Saldo do Ciclo ${cycle.formattedPeriod}'
                : 'Saldo restante do Ciclo ${cycle.formattedPeriod}',
            description: noDueDate
                ? 'Financiamento sem prazo fixo: ${t.fromMemberName} pagou ${resolution.amountPaid.formatted} de ${t.amount.formatted}'
                : 'Financiamento do fechamento: ${t.fromMemberName} pagou ${resolution.amountPaid.formatted} de ${t.amount.formatted}',
            total: resolution.shortfall,
            noDueDate: noDueDate,
            installmentsCount: resolution.loanInstallmentsCount,
          ),
        );
      } else if (resolution.shortfallAction == ShortfallAction.deductFromVault &&
          resolution.vaultId != null) {
        vaultOperations.add({
          'vault_id': resolution.vaultId,
          'member_id': t.fromMemberId,
          'type': 'withdraw',
          'amount_cents': resolution.shortfall.cents,
          'description':
              'Cobertura temporária do Fechamento do Ciclo ${cycle.formattedPeriod}',
        });

        // Reposição para a Caixinha: empréstimo em que o credor é a Casa
        if (resolution.vaultRepaymentMode != VaultRepaymentMode.grant) {
          final noDueDate =
              resolution.vaultRepaymentMode == VaultRepaymentMode.openEnded;
          final count = noDueDate ? 1 : resolution.loanInstallmentsCount;
          newLoans.add(
            loanPlan(
              lenderId: null,
              borrowerId: t.fromMemberId,
              title: noDueDate
                  ? 'Reposição da Caixinha (Livre / Sem Prazo)'
                  : 'Reposição da Caixinha (${count}x)',
              description:
                  'Empréstimo do Lar: reposição para a Caixinha da Casa pela cobertura do Ciclo ${cycle.formattedPeriod}',
              total: resolution.shortfall,
              noDueDate: noDueDate,
              installmentsCount: count,
            ),
          );
        }
      }
    }

    // 6. Super Pix entre moradores, com o valor efetivamente pago
    final transfers = <Map<String, dynamic>>[];
    for (final t in summary.transfers) {
      if (!_isUuid(t.fromMemberId) || !_isUuid(t.toMemberId)) continue;
      final resolution = options?.transferResolutions[t.id];
      final effectiveCents = (resolution != null && resolution.isPartialPayment)
          ? resolution.amountPaid.cents
          : t.amount.cents;
      if (effectiveCents <= 0) continue;
      transfers.add({
        'from_member_id': t.fromMemberId,
        'to_member_id': t.toMemberId,
        'amount_cents': effectiveCents,
      });
    }

    // O banco grava tudo em uma única transação: ou o ciclo fecha por inteiro,
    // ou nada é alterado. Só administradores da casa podem fechar.
    try {
      await client.rpc('confirm_cycle_settlement', params: {
        'p_plan': {
          'house_id': _houseId,
          'cycle_start_date': dateOnly(cycle.startDate),
          'total_expenses_cents': summary.totalHouseExpenses.cents,
          'total_contributions_cents': summary.totalContributions.cents,
          'total_cleared_p2p_cents': summary.totalP2PCleared.cents,
          'vault_operations': vaultOperations,
          'contributions': contributions,
          'expense_ids': expenseIds,
          // A baixa pertence ao ciclo fechado, mesmo que o fechamento seja feito depois
          'expenses_paid_at': _paidAtWithin(cycle).toUtc().toIso8601String(),
          'installment_payments': installmentPayments,
          'new_loans': newLoans,
          'transfers': transfers,
        },
      });
    } on PostgrestException catch (e) {
      throw ServerFailure(e.message);
    }
  }

  /// Agora, ou o fim do ciclo quando ele já terminou.
  DateTime _paidAtWithin(FinancialCycle cycle) {
    final now = DateTime.now();
    return now.isAfter(cycle.endDate) ? cycle.endDate : now;
  }

  @override
  Future<void> reopenSettlement(FinancialCycle cycle) async {
    try {
      await client.rpc('reopen_cycle_settlement', params: {
        'p_house_id': _houseId,
        'p_cycle_start_date': cycle.startDate.toIso8601String().split('T')[0],
      });
    } on PostgrestException catch (e) {
      throw ServerFailure(e.message);
    }
  }
}
