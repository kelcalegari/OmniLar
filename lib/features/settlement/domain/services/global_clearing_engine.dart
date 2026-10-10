import '../../../../core/domain/value_objects/financial_cycle.dart';
import '../../../../core/domain/value_objects/money.dart';
import '../../../finance/domain/entities/contribution.dart';
import '../../../finance/domain/entities/house_expense.dart';
import '../../../finance/domain/entities/house_member.dart';
import '../../../p2p/domain/entities/p2p_loan.dart';
import '../entities/member_net_balance.dart';
import '../entities/settlement_summary.dart';
import '../entities/super_pix_transfer.dart';

class GlobalClearingEngine {
  const GlobalClearingEngine();

  /// Computa a compensação completa de um ciclo financeiro.
  ///
  /// Cruza:
  /// 1. Aportes devidos vs realizados para a Casa.
  /// 2. Reembolsos por despesas pagas do próprio bolso (crédito contra a Casa).
  /// 3. Parcelas de empréstimos P2P que vencem dentro do ciclo.
  /// 4. Otimiza as transferências mínimas ("Super Pix").
  SettlementSummary computeSettlement({
    required FinancialCycle cycle,
    required List<HouseMember> members,
    required List<HouseExpense> expenses,
    required List<Contribution> contributions,
    required List<P2PLoan> loans,
    Map<String, Money>? customContributionTargets,
  }) {
    // 1. Total de despesas da casa no ciclo
    final totalExpensesCents = expenses.fold<int>(
      0,
      (acc, e) => acc + e.amount.cents,
    );
    final totalHouseExpenses = Money(totalExpensesCents);

    // 2. Total de aportes realizados no ciclo
    final totalContributionsCents = contributions.fold<int>(
      0,
      (acc, c) => acc + c.amount.cents,
    );
    final totalContributions = Money(totalContributionsCents);

    // 3. Calcular meta de aporte por membro:
    // Se não for fornecida meta customizada, reparte as despesas da casa pelos percentuais padrão
    final Map<String, Money> contributionTargets = {};
    if (customContributionTargets != null) {
      contributionTargets.addAll(customContributionTargets);
    } else {
      for (final member in members) {
        final percent = member.defaultSplitPercent ?? (100.0 / members.length);
        final targetCents = (totalExpensesCents * (percent / 100.0)).round();
        contributionTargets[member.id] = Money(targetCents);
      }
    }

    // 4. Calcular créditos e débitos por membro
    final List<MemberNetBalance> memberBalances = [];
    int totalP2PClearedCents = 0;

    for (final member in members) {
      // Aporte devido
      final due = contributionTargets[member.id] ?? const Money.zero();

      // Aportes pagos pelo membro
      final paidCents = contributions
          .where((c) => c.memberId == member.id)
          .fold<int>(0, (acc, c) => acc + c.amount.cents);
      final paid = Money(paidCents);

      // Despesas da casa pagas do próprio bolso por este membro
      final outOfPocketCents = expenses
          .where((e) => e.paidByMemberId == member.id && e.paidOutOfPocket)
          .fold<int>(0, (acc, e) => acc + e.amount.cents);
      final outOfPocket = Money(outOfPocketCents);

      // Parcelas P2P que vencem neste ciclo
      int p2pLentCents = 0;
      int p2pBorrowedCents = 0;

      for (final loan in loans) {
        for (final installment in loan.installments) {
          // Verifica se a parcela vence dentro do ciclo e está pendente/parcial
          final isDueInCycle = cycle.contains(installment.dueDate);
          if (isDueInCycle && !installment.isFullyPaid && !installment.isForgiven) {
            final remainingCents = installment.remainingAmount.cents;

            if (loan.lenderMemberId == member.id) {
              p2pLentCents += remainingCents;
              totalP2PClearedCents += remainingCents;
            } else if (loan.borrowerMemberId == member.id) {
              p2pBorrowedCents += remainingCents;
            }
          }
        }
      }

      memberBalances.add(
        MemberNetBalance(
          memberId: member.id,
          memberName: member.name,
          contributionDue: due,
          contributionPaid: paid,
          outOfPocketExpenses: outOfPocket,
          p2pLentDue: Money(p2pLentCents),
          p2pBorrowedDue: Money(p2pBorrowedCents),
        ),
      );
    }

    // 5. Motor de Transferências Mínimas (Super Pix)
    // Agrupa em devedores (saldo líquido < 0) e credores (saldo líquido > 0)
    final transfers = _computeMinimumTransfers(memberBalances);

    // 6. Saldo do Caixa da Casa
    final houseTreasuryCents = totalContributionsCents - totalExpensesCents;

    return SettlementSummary(
      cycle: cycle,
      memberBalances: memberBalances,
      transfers: transfers,
      totalHouseExpenses: totalHouseExpenses,
      totalContributions: totalContributions,
      totalP2PCleared: Money(totalP2PClearedCents ~/ 2), // Cada parcela tem credor e devedor
      houseTreasuryBalance: Money(houseTreasuryCents),
      status: SettlementStatus.readyToSettle,
    );
  }

  /// Algoritmo Greedy de Redução de Dívidas às Transferências Mínimas
  static List<SuperPixTransfer> _computeMinimumTransfers(
    List<MemberNetBalance> balances,
  ) {
    // Copia os saldos líquidos em centavos
    final Map<String, int> netMap = {};
    final Map<String, String> nameMap = {};

    for (final b in balances) {
      netMap[b.memberId] = b.netBalance.cents;
      nameMap[b.memberId] = b.memberName;
    }

    // Se houver saldo de aportes/reembolsos com o Caixa, a Casa entra como contraparte virtual
    final houseNetDiff = balances.fold<int>(0, (acc, b) => acc + b.netBalance.cents);
    if (houseNetDiff != 0) {
      netMap['entity_caixa'] = -houseNetDiff;
      nameMap['entity_caixa'] = 'Caixa da Casa (Conta Conjunta)';
    }

    final List<SuperPixTransfer> transfers = [];
    int transferCounter = 1;

    while (true) {
      // Procura o maior devedor (valor mais negativo) e maior credor (valor mais positivo)
      String? maxDebtorId;
      int minNet = 0;

      String? maxCreditorId;
      int maxNet = 0;

      for (final entry in netMap.entries) {
        if (entry.value < minNet) {
          minNet = entry.value;
          maxDebtorId = entry.key;
        }
        if (entry.value > maxNet) {
          maxNet = entry.value;
          maxCreditorId = entry.key;
        }
      }

      // Se não há mais devedores ou credores com diferença significativa, terminamos
      if (maxDebtorId == null || maxCreditorId == null || minNet >= 0 || maxNet <= 0) {
        break;
      }

      // O valor da transferência é o menor entre a dívida e o crédito
      final debtAmount = -minNet;
      final creditAmount = maxNet;
      final transferCents = debtAmount < creditAmount ? debtAmount : creditAmount;

      if (transferCents <= 0) break;

      final fromName = nameMap[maxDebtorId] ?? 'Membro';
      final toName = nameMap[maxCreditorId] ?? 'Membro';

      transfers.add(
        SuperPixTransfer(
          id: 'transfer_$transferCounter',
          fromMemberId: maxDebtorId,
          fromMemberName: fromName,
          toMemberId: maxCreditorId,
          toMemberName: toName,
          amount: Money(transferCents),
          description: 'Super Pix de Fechamento do Ciclo ($fromName ➔ $toName)',
          status: TransferStatus.pending,
          pixKey: 'pix_${maxCreditorId.replaceAll('member_', '')}@banco.com',
        ),
      );

      // Atualiza os saldos restantes
      netMap[maxDebtorId] = netMap[maxDebtorId]! + transferCents;
      netMap[maxCreditorId] = netMap[maxCreditorId]! - transferCents;

      transferCounter++;
    }

    return transfers;
  }
}
