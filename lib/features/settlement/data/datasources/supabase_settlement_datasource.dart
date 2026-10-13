import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../settlement_summary_codec.dart';
import '../../../../core/domain/value_objects/financial_cycle.dart';
import '../../../../core/domain/value_objects/money.dart';
import '../../../../core/errors/failures.dart';
import '../../../finance/data/datasources/finance_datasource.dart';
import '../../../finance/domain/entities/split_rule.dart';
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
    // Ciclo reaberto: o que o fechamento anterior já movimentou nas caixinhas
    var isReopened = false;
    var surplusAlreadyVaulted = const Money.zero();
    var deficitAlreadyCovered = const Money.zero();
    var surplusAlreadyRolled = const Money.zero();
    var surplusAlreadyRefunded = const Money.zero();
    var houseShortfallAlreadySettled = const Money.zero();
    var houseLoansAlreadyReceived = const Money.zero();

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
        final settledAt = existingSettlement['settled_at'] != null
            ? DateTime.tryParse(existingSettlement['settled_at'] as String)?.toLocal()
            : null;
        // Retrato gravado no fechamento: saldos, transferências e memória de cálculo
        final snapshot = settlementSummaryFromJson(
          existingSettlement['summary_snapshot'],
          cycle: cycle,
          settledAt: settledAt,
        );
        if (snapshot != null) return snapshot;

        // Fechamento anterior ao retrato: só o que o banco guarda, com os nomes atuais
        var memberNames = <String, String>{};
        try {
          memberNames = {
            for (final m in await financeDataSource.getMembers()) m.id: m.name,
          };
        } catch (_) {}
        final rawTransfers =
            existingSettlement['settlement_transfers'] as List<dynamic>? ?? [];
        final transfers = rawTransfers.map<SuperPixTransfer>((r) {
          return SuperPixTransfer(
            id: r['id'] as String,
            fromMemberId: r['from_member_id'] as String,
            fromMemberName: memberNames[r['from_member_id']] ?? 'Membro',
            toMemberId: r['to_member_id'] as String,
            toMemberName: memberNames[r['to_member_id']] ?? 'Membro',
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
          settledAt: settledAt,
        );
      }

      if (existingSettlement != null && existingSettlement['status'] == 'draft') {
        isReopened = true;
        surplusAlreadyVaulted = Money(
          (existingSettlement['surplus_vaulted_cents'] as num?)?.toInt() ?? 0,
        );
        deficitAlreadyCovered = Money(
          (existingSettlement['deficit_covered_cents'] as num?)?.toInt() ?? 0,
        );
        surplusAlreadyRolled = Money(
          (existingSettlement['surplus_rolled_cents'] as num?)?.toInt() ?? 0,
        );
        surplusAlreadyRefunded = Money(
          (existingSettlement['surplus_refunded_cents'] as num?)?.toInt() ?? 0,
        );
        houseShortfallAlreadySettled = Money(
          ((existingSettlement['house_receivable_cents'] as num?)?.toInt() ?? 0) +
              ((existingSettlement['house_forgiven_cents'] as num?)?.toInt() ?? 0),
        );
        houseLoansAlreadyReceived = Money(
          (existingSettlement['house_loans_received_cents'] as num?)?.toInt() ?? 0,
        );
      }
    } catch (_) {
      // Continua para apuração dinâmica
    }

    // 2. Apuração dinâmica do ciclo
    // A versão é lida antes dos dados: qualquer mudança depois dela faz o banco
    // recusar o fechamento calculado aqui.
    String? dataVersion;
    try {
      dataVersion = await client.rpc(
        'settlement_data_version',
        params: {'p_house_id': _houseId},
      ) as String?;
    } catch (_) {}

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
      surplusAlreadyVaulted: surplusAlreadyVaulted,
      deficitAlreadyCovered: deficitAlreadyCovered,
      openingBalance: await financeDataSource.getOpeningBalance(cycle),
      surplusAlreadyRolled: surplusAlreadyRolled,
      surplusAlreadyRefunded: surplusAlreadyRefunded,
      refundSurplus: options?.surplusAction == SurplusAction.refund,
      houseShortfallAlreadySettled: houseShortfallAlreadySettled,
      houseLoansAlreadyReceived: houseLoansAlreadyReceived,
    );
    return summary.copyWith(isReopened: isReopened, dataVersion: dataVersion);
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

    // Quem pagou a menos ao Caixa: esse dinheiro não entrou, então não é sobra
    final surplus = availableSurplus(summary, options);
    if (summary.surplusRefunded.cents > 0 && unpaidToHouse(summary, options).cents > 0) {
      throw const ServerFailure(
        'A sobra devolvida aos moradores conta com o aporte de todos. Com pagamento parcial ao Caixa, escolha guardar a sobra na Caixinha ou deixá-la no Caixa.',
      );
    }

    // 1. Sobra do Caixa guardada na Caixinha
    if (options?.surplusAction == SurplusAction.toVault &&
        options?.targetVaultId != null &&
        surplus.cents > 0) {
      vaultOperations.add({
        'vault_id': options!.targetVaultId,
        'member_id': actorId,
        'type': 'deposit',
        'amount_cents': surplus.cents,
        'description': 'Sobra do Fechamento do Ciclo ${cycle.formattedPeriod}',
      });
    }

    // Sobra deixada no Caixa como folga do próximo ciclo
    final surplusRolledCents =
        options?.surplusAction == SurplusAction.rollover ? surplus.cents : 0;

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

    // Sobra devolvida a quem já tinha aportado: sai do Caixa de volta para o morador
    final contributionRefunds = [
      for (final balance in summary.memberBalances)
        if (_isUuid(balance.memberId) && balance.contributionRefund.cents > 0)
          {
            'member_id': balance.memberId,
            'amount_cents': balance.contributionRefund.cents,
          },
    ];

    // 3. Contas pendentes do ciclo
    final expenses = await financeDataSource.getExpensesForCycle(cycle);
    final expenseIds = [
      for (final exp in expenses)
        if (exp.isPending && _isUuid(exp.id)) exp.id,
    ];
    // Tudo o que entra neste acerto: se o ciclo for reaberto, não é reembolsado de novo
    final settledExpenseIds = [
      for (final exp in expenses)
        if (exp.settledAt == null && _isUuid(exp.id)) exp.id,
    ];

    // Congela o rateio: despesas que usaram o padrão da casa passam a carregar os
    // percentuais deste fechamento. Mudar o padrão ou entrar um morador novo
    // depois não altera o que já foi acertado.
    final members = await financeDataSource.getMembers();
    final defaultSplit = SplitRule.percentage({
      for (final m in members)
        if (_isUuid(m.id)) m.id: m.defaultSplitPercent,
    });
    final memberIds = defaultSplit.percentages!.keys.toList();
    final splitSnapshots = [
      for (final exp in expenses)
        if (exp.settledAt == null &&
            _isUuid(exp.id) &&
            exp.splitRule.type == SplitType.percentage &&
            (exp.splitRule.percentages == null || exp.splitRule.percentages!.isEmpty))
          {
            'expense_id': exp.id,
            'rules': [
              for (final entry in defaultSplit
                  .calculateAllocations(totalAmount: exp.amount, memberIds: memberIds)
                  .entries)
                {
                  'member_id': entry.key,
                  'percentage_basis_points':
                      (defaultSplit.percentages![entry.key]! * 100).round().clamp(0, 10000),
                  'calculated_cents': entry.value.cents,
                },
            ],
          },
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
      DateTime? dueDate,
      String? repayToVaultId,
    }) {
      // Sem data definida, vence no dia 10 seguinte ao fim do ciclo (nunca dentro
      // do ciclo que está sendo fechado).
      var defaultDueDate = DateTime(cycle.endDate.year, cycle.endDate.month, 10);
      if (!defaultDueDate.isAfter(cycle.endDate)) {
        defaultDueDate = DateTime(cycle.endDate.year, cycle.endDate.month + 1, 10);
      }
      final firstDueDate = noDueDate
          ? P2PLoan.openEndedPlaceholderDueDate
          : (dueDate ?? defaultDueDate);
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
        'repay_to_vault_id': ?repayToVaultId,
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

      // Credor é o Caixa da Casa: o acordo fica com o Lar como credor
      final toHouse = t.toMemberId == P2PLoan.houseLenderId;
      final lenderId = toHouse ? null : t.toMemberId;

      if (resolution.shortfallAction == ShortfallAction.rolloverPending) {
        if (!toHouse && !_isUuid(t.toMemberId)) continue;
        // Cobrado inteiro no próximo fechamento
        newLoans.add(
          loanPlan(
            lenderId: lenderId,
            borrowerId: t.fromMemberId,
            title: 'Pendência do Ciclo ${cycle.formattedPeriod}',
            description:
                'Saldo que ficou para o próximo fechamento: ${t.fromMemberName} pagou ${resolution.amountPaid.formatted} de ${t.amount.formatted}',
            total: resolution.shortfall,
            noDueDate: false,
            installmentsCount: 1,
            dueDate: cycle.endDate.add(const Duration(days: 1)),
          ),
        );
      } else if (resolution.shortfallAction == ShortfallAction.createP2PLoan) {
        if (!toHouse && !_isUuid(t.toMemberId)) continue;
        final noDueDate = resolution.loanHasNoDueDate;
        newLoans.add(
          loanPlan(
            lenderId: lenderId,
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
              // Os pagamentos deste acordo voltam para a Caixinha que cobriu
              repayToVaultId: resolution.vaultId,
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
          'data_version': summary.dataVersion,
          'total_expenses_cents': summary.totalHouseExpenses.cents,
          'total_contributions_cents': summary.totalContributions.cents,
          'total_cleared_p2p_cents': summary.totalP2PCleared.cents,
          'vault_operations': vaultOperations,
          'contributions': contributions,
          'contribution_refunds': contributionRefunds,
          'surplus_rolled_cents': surplusRolledCents,
          'surplus_refunded_cents': summary.surplusRefunded.cents,
          'house_receivable_cents': houseShortfallFinanced(summary, options).cents,
          'house_forgiven_cents': houseShortfallForgiven(summary, options).cents,
          'expense_ids': expenseIds,
          'settled_expense_ids': settledExpenseIds,
          'split_snapshots': splitSnapshots,
          'surplus_vaulted_cents': [
            for (final op in vaultOperations)
              if (op['type'] == 'deposit') op['amount_cents'] as int,
          ].fold<int>(0, (acc, cents) => acc + cents),
          'deficit_covered_cents':
              options?.deficitVaultId != null ? summary.deficitCoveredByVault.cents : 0,
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

    // Guarda o retrato do fechamento, com o valor efetivamente pago de cada
    // Super Pix. O ciclo já está fechado: se isto falhar, ele só aparece resumido.
    try {
      final snapshot = summary.copyWith(
        transfers: [
          for (final t in summary.transfers)
            if (options?.transferResolutions[t.id]?.isPartialPayment ?? false)
              t.copyWith(
                amount: options!.transferResolutions[t.id]!.amountPaid,
                description: '${t.description} (pagamento parcial de ${t.amount.formatted})',
              )
            else
              t,
        ],
      );
      await client.rpc('save_settlement_snapshot', params: {
        'p_house_id': _houseId,
        'p_cycle_start_date': cycle.startDate.toIso8601String().split('T')[0],
        'p_snapshot': settlementSummaryToJson(snapshot),
      });
    } catch (e) {
      debugPrint('[confirmSettlement] Retrato do fechamento não gravado: $e');
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
