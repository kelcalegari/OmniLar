import 'dart:math' as math;

import '../../../../core/domain/value_objects/financial_cycle.dart';
import '../../../../core/domain/value_objects/money.dart';
import '../../../finance/domain/entities/contribution.dart';
import '../../../finance/domain/entities/house_expense.dart';
import '../../../finance/domain/entities/house_member.dart';
import '../../../finance/domain/entities/house_settings.dart';
import '../../../finance/domain/entities/opening_inflows.dart';
import '../../../finance/domain/entities/category.dart';
import '../../../finance/domain/entities/payment_method.dart';
import '../../../finance/domain/entities/split_rule.dart';
import '../../../p2p/domain/entities/p2p_loan.dart';
import '../entities/member_audit_trail.dart';
import '../entities/member_net_balance.dart';
import '../entities/settlement_options.dart';
import '../entities/settlement_summary.dart';
import '../entities/super_pix_transfer.dart';
import '../../../finance/domain/services/exclusive_charges.dart';

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
    String? housePixKey,
    String? housePixKeyHolderName,
    DeficitSplit deficitSplit = DeficitSplit.proportional,
    Money deficitVaultBalance = const Money.zero(),
    Money surplusAlreadyVaulted = const Money.zero(),
    Money deficitAlreadyCovered = const Money.zero(),
    Money openingBalance = const Money.zero(),
    Money vaultReturns = const Money.zero(),
    Money surplusAlreadyRolled = const Money.zero(),
    Money surplusAlreadyRefunded = const Money.zero(),
    bool refundSurplus = false,
    Money houseShortfallAlreadySettled = const Money.zero(),
    Money houseLoansAlreadyReceived = const Money.zero(),
    OpeningBalanceRule? openingBalanceRule,
    OpeningInflows? openingInflows,
    OpeningInflowRules openingInflowRules = const OpeningInflowRules(),
    List<ExpenseCategory>? categories,
    List<PaymentMethod>? paymentMethods,
  }) {
    // 0. Despesas de projetos compartilhados são liquidadas apenas no próprio projeto
    // (ProjectSettlementService). Filtramos aqui por defesa em profundidade para
    // impedir contagem dupla mesmo que o chamador as envie.
    final houseExpenses = expenses.where((e) => !e.isProjectExpense).toList();
    expenses = houseExpenses;

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

    final categoryMap = {for (final c in categories ?? const <ExpenseCategory>[]) c.id: c};
    final memberMap = {for (final m in members) m.id: m};
    final methodMap = {for (final p in paymentMethods ?? const <PaymentMethod>[]) p.id: p};

    // 3. Calcular meta de aporte por membro e auditar a partição de cada despesa:
    // Se não for fornecida meta customizada, reparte as despesas da casa considerando
    // as regras de rateio de cada despesa e seus sub-itens (se for despesa composta).
    final Map<String, Money> contributionTargets = {};
    final Map<String, List<ExpenseShareAudit>> memberExpenseShares = {
      for (final m in members) m.id: [],
    };
    int bucketDeficitCents = 0;
    int deficitCoveredCents = 0;
    int deficitAlreadyCoveredCents = 0;

    // Sobra do Caixa abatida dos aportes devidos (regra "abater os aportes"):
    // reparte [cents] pelos [weights], sem passar do que cada um deve.
    void applyOpeningBalanceToTargets(
      int cents,
      Map<String, int> weights,
      String ruleDescription, {
      String title = 'Sobra do Caixa abatida',
    }) {
      if (cents <= 0 || members.isEmpty) return;
      final totalWeight = weights.values.fold<int>(0, (acc, w) => acc + w);
      if (totalWeight <= 0) return;
      final allocations = SplitRule.percentage({
        for (final e in weights.entries) e.key: e.value * 100 / totalWeight,
      }).calculateAllocations(
        totalAmount: Money(cents),
        memberIds: members.map((m) => m.id).toList(),
      );
      for (final entry in allocations.entries) {
        final due = contributionTargets[entry.key]?.cents ?? 0;
        final applied = entry.value.cents.clamp(0, due).toInt();
        if (applied <= 0) continue;
        contributionTargets[entry.key] = Money(due - applied);
        memberExpenseShares[entry.key]?.add(
          ExpenseShareAudit(
            expenseId: 'opening_balance',
            expenseTitle: title,
            totalExpenseAmount: Money(-cents),
            allocatedAmount: Money(-applied),
            ruleDescription: ruleDescription,
            date: cycle.startDate,
          ),
        );
      }
    }

    // O dinheiro do início do ciclo em partes, cada uma com a sua regra. Sem a
    // separação por origem, ou sem regra por tipo escolhida, vale a regra
    // única: a sobra, sem o que voltou das caixinhas, segue [openingBalanceRule].
    // A entrada de fora (0096) segue a mesma regra única, mas fica em parte
    // própria para a memória de cálculo mostrar de onde veio o abatimento.
    final byKind = openingInflows != null && !openingInflowRules.isEmpty;
    final legacyCents = math.max(0, openingBalance.cents - vaultReturns.cents);
    final legacyThirdPartyCents =
        (openingInflows?.thirdParty.cents ?? 0).clamp(0, legacyCents).toInt();
    final openingParts = byKind
        ? OpeningInflowPart.split(openingInflows, openingInflowRules, openingBalanceRule)
        : [
            OpeningInflowPart(
              kind: OpeningInflowKind.rolledSurplus,
              amount: Money(legacyCents - legacyThirdPartyCents),
              rule: openingBalanceRule,
            ),
            if (legacyThirdPartyCents > 0)
              OpeningInflowPart(
                kind: OpeningInflowKind.thirdParty,
                amount: Money(legacyThirdPartyCents),
                rule: openingBalanceRule,
              ),
          ];
    String abatementTitle(OpeningInflowPart part) =>
        byKind || part.kind == OpeningInflowKind.thirdParty ? part.abatementTitle : 'Sobra do Caixa abatida';

    if (customContributionTargets != null) {
      contributionTargets.addAll(customContributionTargets);
      for (final entry in customContributionTargets.entries) {
        memberExpenseShares[entry.key]?.add(
          ExpenseShareAudit(
            expenseId: 'custom_target',
            expenseTitle: 'Meta Fixa / Personalizada',
            totalExpenseAmount: entry.value,
            allocatedAmount: entry.value,
            ruleDescription: 'Valor fixo definido no perfil do membro',
            date: cycle.startDate,
          ),
        );
      }

      // Sub-itens pessoais de despesas compostas não saem do balde: são cobrados
      // do responsável por cima do aporte fixo.
      final memberIds = members.map((m) => m.id).toList();
      int personalItemsCents = 0;
      for (final expense in expenses) {
        for (final item in expense.items) {
          // Inclui o sub-item sem responsável de uma despesa de categoria com dono
          final itemRule = exclusiveItemRule(expense, item);
          if (itemRule == null) continue;
          final inheritedFromExpense = item.responsibleMemberId == null &&
              item.splitRule?.type != SplitType.categoryOwner;
          final allocations = itemRule.calculateAllocations(
            totalAmount: item.amount,
            memberIds: memberIds,
          );
          for (final entry in allocations.entries) {
            if (entry.value.cents <= 0) continue;
            personalItemsCents += entry.value.cents;
            contributionTargets[entry.key] = Money(
              (contributionTargets[entry.key]?.cents ?? 0) + entry.value.cents,
            );
            memberExpenseShares[entry.key]?.add(
              ExpenseShareAudit(
                expenseId: expense.id,
                expenseTitle: '${expense.title} • ${item.title}',
                totalExpenseAmount: item.amount,
                allocatedAmount: entry.value,
                ruleDescription: inheritedFromExpense
                    ? 'Responsável exclusivo pela despesa'
                    : 'Item pessoal exclusivo',
                date: expense.date,
                isPersonal: true,
                categoryName: categoryMap[expense.categoryId]?.name,
                paidByMemberId: expense.paidByMemberId,
                paidByMemberName: memberMap[expense.paidByMemberId]?.name,
                paymentMethodName: methodMap[expense.paymentMethodId]?.name,
              ),
            );
          }
        }
      }

      // Despesa inteira de um responsável único (categoria com dono): também
      // não sai do balde, é cobrada do responsável por cima do aporte fixo.
      for (final expense in expenses) {
        final ownerId = expense.splitRule.singleResponsibleMemberId;
        if (expense.items.isNotEmpty ||
            expense.splitRule.type != SplitType.categoryOwner ||
            ownerId == null ||
            !memberIds.contains(ownerId) ||
            expense.amount.cents <= 0) {
          continue;
        }
        personalItemsCents += expense.amount.cents;
        contributionTargets[ownerId] = Money(
          (contributionTargets[ownerId]?.cents ?? 0) + expense.amount.cents,
        );
        memberExpenseShares[ownerId]?.add(
          ExpenseShareAudit(
            expenseId: expense.id,
            expenseTitle: expense.title,
            totalExpenseAmount: expense.amount,
            allocatedAmount: expense.amount,
            ruleDescription: 'Responsável exclusivo pela despesa',
            date: expense.date,
            isPersonal: true,
            categoryName: categoryMap[expense.categoryId]?.name,
            paidByMemberId: expense.paidByMemberId,
            paidByMemberName: memberMap[expense.paidByMemberId]?.name,
            paymentMethodName: methodMap[expense.paymentMethodId]?.name,
          ),
        );
      }

      // Gastos acima do balde: a Caixinha escolhida cobre o que puder e o
      // restante é rateado entre os moradores conforme a opção do fechamento.
      final bucketCents = customContributionTargets.values.fold<int>(
        0,
        (acc, t) => acc + t.cents,
      );
      final sharedExpensesCents = totalExpensesCents - personalItemsCents;
      if (sharedExpensesCents > bucketCents) {
        bucketDeficitCents = sharedExpensesCents - bucketCents;
      }
      // Ciclo reaberto: o que a Caixinha já cobriu no fechamento anterior não volta a ser cobrado
      deficitAlreadyCoveredCents = deficitAlreadyCovered.cents.clamp(0, bucketDeficitCents).toInt();
      bucketDeficitCents -= deficitAlreadyCoveredCents;
      // A sobra deixada no Caixa pelo ciclo anterior é folga: cobre o excedente
      // antes da Caixinha e do rateio entre os moradores. O que voltou das
      // caixinhas só entra se a casa escolheu (por caixinha): sem escolha, só
      // cobriu falta de caixa, e o excedente continua sendo dos moradores.
      // Guardada como folga (regra da casa), a parte não cobre o excedente.
      // Primeiro o que só cobre o excedente, depois o que também abate os aportes.
      final covering = [
        ...openingParts.where(
          (p) => p.rule != OpeningBalanceRule.keep && p.rule != OpeningBalanceRule.reduceQuotas,
        ),
        ...openingParts.where((p) => p.rule == OpeningBalanceRule.reduceQuotas),
      ];
      for (final part in covering) {
        final onExcessCents = part.amount.cents.clamp(0, bucketDeficitCents).toInt();
        bucketDeficitCents -= onExcessCents;
        // Abater os aportes: o que a parte não usou no excedente reduz o valor
        // fixo de cada um, na proporção dele
        if (part.rule == OpeningBalanceRule.reduceQuotas) {
          applyOpeningBalanceToTargets(
            part.amount.cents - onExcessCents,
            {for (final m in members) m.id: customContributionTargets[m.id]?.cents ?? 0},
            'Rateio proporcional ao aporte fixo',
            title: abatementTitle(part),
          );
        }
      }

      final vaultCents = deficitVaultBalance.cents > 0 ? deficitVaultBalance.cents : 0;
      deficitCoveredCents = vaultCents < bucketDeficitCents ? vaultCents : bucketDeficitCents;

      final deficitToSplit = Money(bucketDeficitCents - deficitCoveredCents);
      if (deficitToSplit.cents > 0 && members.isNotEmpty) {
        final proportional = deficitSplit == DeficitSplit.proportional && bucketCents > 0;
        final rule = proportional
            ? SplitRule.percentage({
                for (final m in members)
                  m.id: (customContributionTargets[m.id]?.cents ?? 0) * 100 / bucketCents,
              })
            : const SplitRule.percentage(null);
        final allocations = rule.calculateAllocations(
          totalAmount: deficitToSplit,
          memberIds: members.map((m) => m.id).toList(),
        );
        for (final entry in allocations.entries) {
          if (entry.value.cents <= 0) continue;
          contributionTargets[entry.key] = Money(
            (contributionTargets[entry.key]?.cents ?? 0) + entry.value.cents,
          );
          memberExpenseShares[entry.key]?.add(
            ExpenseShareAudit(
              expenseId: 'bucket_deficit',
              expenseTitle: 'Excedente do balde',
              totalExpenseAmount: deficitToSplit,
              allocatedAmount: entry.value,
              ruleDescription: proportional
                  ? 'Rateio proporcional ao aporte fixo'
                  : 'Rateio em partes iguais',
              date: cycle.endDate,
            ),
          );
        }
      }
    } else {
      final memberIds = members.map((m) => m.id).toList();
      final defaultPercentages = <String, double>{
        for (final m in members) m.id: m.defaultSplitPercent,
      };

      final Map<String, int> targetCentsMap = {
        for (final m in members) m.id: 0,
      };

      for (final expense in expenses) {
        if (expense.isItemized) {
          // Despesa composta: reparte cada sub-item individualmente
          for (final item in expense.items) {
            final SplitRule itemRule =
                item.splitRule ??
                (item.responsibleMemberId != null
                    ? SplitRule.singleResponsible(item.responsibleMemberId!)
                    : (expense.splitRule.type == SplitType.percentage &&
                              (expense.splitRule.percentages == null ||
                                  expense.splitRule.percentages!.isEmpty)
                          ? SplitRule.percentage(defaultPercentages)
                          : expense.splitRule));

            final allocations = itemRule.calculateAllocations(
              totalAmount: item.amount,
              memberIds: memberIds,
            );
            for (final entry in allocations.entries) {
              if (entry.value.cents > 0) {
                targetCentsMap[entry.key] =
                    (targetCentsMap[entry.key] ?? 0) + entry.value.cents;
                final isPersonalItem = item.responsibleMemberId != null ||
                    item.splitRule?.type == SplitType.categoryOwner;
                final ruleDesc = isPersonalItem
                    ? 'Item pessoal exclusivo'
                    : 'Sub-item rateado (${itemRule.type.name})';
                memberExpenseShares[entry.key]?.add(
                  ExpenseShareAudit(
                    expenseId: expense.id,
                    expenseTitle: '${expense.title} • ${item.title}',
                    totalExpenseAmount: item.amount,
                    allocatedAmount: entry.value,
                    ruleDescription: ruleDesc,
                    date: expense.date,
                    isPersonal: isPersonalItem,
                    categoryName: categoryMap[expense.categoryId]?.name,
                    paidByMemberId: expense.paidByMemberId,
                    paidByMemberName: memberMap[expense.paidByMemberId]?.name,
                    paymentMethodName: methodMap[expense.paymentMethodId]?.name,
                  ),
                );
              }
            }
          }
        } else {
          // Despesa simples: usa a regra da despesa ou os percentuais padrão dos membros
          final SplitRule effectiveRule =
              (expense.splitRule.type == SplitType.percentage &&
                  (expense.splitRule.percentages == null ||
                      expense.splitRule.percentages!.isEmpty))
              ? SplitRule.percentage(defaultPercentages)
              : expense.splitRule;

          final allocations = effectiveRule.calculateAllocations(
            totalAmount: expense.amount,
            memberIds: memberIds,
          );
          for (final entry in allocations.entries) {
            if (entry.value.cents > 0) {
              targetCentsMap[entry.key] =
                  (targetCentsMap[entry.key] ?? 0) + entry.value.cents;
              String ruleDesc;
              if (effectiveRule.type == SplitType.percentage) {
                final pct =
                    (effectiveRule.percentages?[entry.key] ??
                    defaultPercentages[entry.key] ??
                    0);
                ruleDesc =
                    '${pct.toStringAsFixed(pct.truncateToDouble() == pct ? 0 : 1)}% da despesa';
              } else if (effectiveRule.type == SplitType.categoryOwner) {
                ruleDesc = 'Responsável exclusivo pela despesa';
              } else if (effectiveRule.type == SplitType.fixed) {
                ruleDesc = 'Valor fixo definido';
              } else {
                ruleDesc = 'Regra ${effectiveRule.type.name}';
              }
              final isExclusiveExpense = effectiveRule.type == SplitType.categoryOwner;
              memberExpenseShares[entry.key]?.add(
                ExpenseShareAudit(
                  expenseId: expense.id,
                  expenseTitle: expense.title,
                  totalExpenseAmount: expense.amount,
                  allocatedAmount: entry.value,
                  ruleDescription: ruleDesc,
                  date: expense.date,
                  isPersonal: isExclusiveExpense,
                  categoryName: categoryMap[expense.categoryId]?.name,
                  paidByMemberId: expense.paidByMemberId,
                  paidByMemberName: memberMap[expense.paidByMemberId]?.name,
                  paymentMethodName: methodMap[expense.paymentMethodId]?.name,
                ),
              );
            }
          }
        }
      }

      for (final entry in targetCentsMap.entries) {
        contributionTargets[entry.key] = Money(entry.value);
      }

      // Abater os aportes: a parte reduz o que cada um deve pelo percentual
      // padrão. Nas outras regras ela fica no Caixa.
      for (final part in openingParts) {
        if (part.rule != OpeningBalanceRule.reduceQuotas) continue;
        applyOpeningBalanceToTargets(
          part.amount.cents,
          {for (final m in members) m.id: (m.defaultSplitPercent * 100).round()},
          'Rateio pelo percentual padrão',
          title: abatementTitle(part),
        );
      }
    }

    // 3.1 Devolução da sobra aos moradores: abate do aporte devido, na proporção
    // do aporte de cada um. O que um fechamento anterior deste ciclo já devolveu
    // continua abatido; a sobra nova só é devolvida se essa for a opção escolhida.
    final refundWeights = <String, int>{
      for (final m in members)
        m.id: customContributionTargets != null
            ? (customContributionTargets[m.id]?.cents ?? 0)
            : (m.defaultSplitPercent * 100).round(),
    };
    // Aporte devido antes de qualquer devolução de sobra
    final dueBeforeRefund = Map<String, Money>.of(contributionTargets);
    void refundToMembers(int cents, String title) {
      if (cents <= 0 || members.isEmpty) return;
      final totalWeight = refundWeights.values.fold<int>(0, (acc, w) => acc + w);
      final rule = totalWeight > 0
          ? SplitRule.percentage({
              for (final e in refundWeights.entries) e.key: e.value * 100 / totalWeight,
            })
          : const SplitRule.percentage(null);
      final allocations = rule.calculateAllocations(
        totalAmount: Money(cents),
        memberIds: members.map((m) => m.id).toList(),
      );
      for (final entry in allocations.entries) {
        if (entry.value.cents <= 0) continue;
        contributionTargets[entry.key] = Money(
          (contributionTargets[entry.key]?.cents ?? 0) - entry.value.cents,
        );
        memberExpenseShares[entry.key]?.add(
          ExpenseShareAudit(
            expenseId: 'surplus_refund',
            expenseTitle: title,
            totalExpenseAmount: Money(-cents),
            allocatedAmount: Money(-entry.value.cents),
            ruleDescription: 'Rateio proporcional ao aporte',
            date: cycle.endDate,
          ),
        );
      }
    }

    // Acordos em que o Lar é o credor: o que os moradores pagam neste
    // fechamento entra no Caixa. Num ciclo reaberto, soma o que já entrou antes.
    int houseLoanReceiptsCents = houseLoansAlreadyReceived.cents;
    final memberIdSet = members.map((m) => m.id).toSet();
    for (final loan in loans) {
      if (!loan.isHouseLender || !memberIdSet.contains(loan.borrowerMemberId)) continue;
      // Reposição de Caixinha volta para a Caixinha, não para o Caixa
      if (loan.repayToVaultId != null) continue;
      for (final installment in loan.installmentsChargedIn(cycle)) {
        houseLoanReceiptsCents += installment.remainingAmount.cents;
      }
    }

    // Empréstimos que o Caixa liberou neste ciclo (0086): o dinheiro saiu dele
    final houseLoansFundedCents = loans
        .where((loan) => loan.fundedFromCycle(cycle))
        .fold<int>(0, (acc, loan) => acc + loan.totalAmount.cents);

    int treasuryAfterClosing() =>
        openingBalance.cents +
        houseLoanReceiptsCents -
        houseLoansFundedCents -
        // O que um fechamento anterior deste ciclo deixou a receber ou perdoou
        houseShortfallAlreadySettled.cents +
        members.fold<int>(0, (acc, m) => acc + (contributionTargets[m.id]?.cents ?? 0)) -
        totalExpensesCents +
        deficitCoveredCents +
        deficitAlreadyCoveredCents -
        surplusAlreadyVaulted.cents -
        surplusAlreadyRolled.cents;

    refundToMembers(surplusAlreadyRefunded.cents, 'Sobra já devolvida');
    int surplusRefundedCents = 0;
    if (refundSurplus && treasuryAfterClosing() > 0) {
      surplusRefundedCents = treasuryAfterClosing();
      refundToMembers(surplusRefundedCents, 'Devolução da sobra');
    }

    // 4. Calcular créditos e débitos por membro e gerar a memória de cálculo (Audit Trail)
    final List<MemberNetBalance> memberBalances = [];
    final Map<String, MemberAuditTrail> auditTrails = {};
    final memberIdsSet = members.map((m) => m.id).toSet();

    // Total de parcelas P2P que vencem neste ciclo
    int totalP2PClearedCents = 0;
    for (final loan in loans) {
      if (!memberIdsSet.contains(loan.lenderMemberId) &&
          !memberIdsSet.contains(loan.borrowerMemberId)) {
        continue;
      }
      // Sem prazo ou fora do ciclo nunca entram no fechamento (RN01);
      // parcelas atrasadas de ciclos anteriores entram junto com as do ciclo.
      for (final installment in loan.installmentsChargedIn(cycle)) {
        totalP2PClearedCents += installment.remainingAmount.cents;
      }
    }

    for (final member in members) {
      // Aporte devido
      final due = contributionTargets[member.id] ?? const Money.zero();

      // Aportes pagos pelo membro
      final memberContributions = contributions
          .where((c) => c.memberId == member.id)
          .toList();
      final paidCents = memberContributions.fold<int>(
        0,
        (acc, c) => acc + c.amount.cents,
      );
      final paid = Money(paidCents);
      final contributionAudits = memberContributions
          .map(
            (c) => ContributionAudit(
              contributionId: c.id,
              amount: c.amount,
              date: c.date,
              paymentMethodId: c.paymentMethodId,
            ),
          )
          .toList();

      // Despesas da casa pagas do próprio bolso por este membro
      // (Apenas despesas explicitamente pagas do próprio bolso geram crédito de reembolso)
      final memberOutOfPocketExpenses = expenses
          .where(
            (e) =>
                e.paidByMemberId == member.id &&
                e.paidOutOfPocket &&
                // Já reembolsada em um fechamento anterior deste ciclo
                e.settledAt == null &&
                e.paymentMethodId != 'pm_caixa',
          )
          .toList();
      final outOfPocketCents = memberOutOfPocketExpenses.fold<int>(
        0,
        (acc, e) => acc + e.amount.cents,
      );
      final outOfPocket = Money(outOfPocketCents);
      final outOfPocketAudits = memberOutOfPocketExpenses
          .map(
            (e) => OutOfPocketAudit(
              expenseId: e.id,
              title: e.title,
              amount: e.amount,
              date: e.date,
              paymentMethod: methodMap[e.paymentMethodId]?.name ?? e.paymentMethodId,
            ),
          )
          .toList();

      // Parcelas P2P que vencem neste ciclo para este membro
      final p2pReceivables = <P2PInstallmentAudit>[];
      final p2pPayables = <P2PInstallmentAudit>[];
      int p2pLentCents = 0;
      int p2pBorrowedCents = 0;

      for (final loan in loans) {
        // Parcelas em aberto cobradas neste fechamento (do ciclo ou atrasadas)
        for (final installment in loan.installmentsChargedIn(cycle)) {
          final remainingCents = installment.remainingAmount.cents;

          if (loan.lenderMemberId == member.id) {
            p2pLentCents += remainingCents;
            final borrower = members
                .where((m) => m.id == loan.borrowerMemberId)
                .firstOrNull;
            p2pReceivables.add(
              P2PInstallmentAudit(
                loanId: loan.id,
                description: loan.title,
                otherMemberId: loan.borrowerMemberId,
                otherMemberName: borrower?.name ?? 'Membro',
                installmentNumber: installment.number,
                totalInstallments: loan.installments.length,
                amount: installment.remainingAmount,
                dueDate: installment.dueDate,
                isReceivable: true,
              ),
            );
          } else if (loan.borrowerMemberId == member.id) {
            p2pBorrowedCents += remainingCents;
            final lender = members
                .where((m) => m.id == loan.lenderMemberId)
                .firstOrNull;
            p2pPayables.add(
              P2PInstallmentAudit(
                loanId: loan.id,
                description: loan.title,
                otherMemberId: loan.lenderMemberId,
                otherMemberName: loan.isHouseLender ? 'Caixa da Casa' : (lender?.name ?? 'Membro'),
                installmentNumber: installment.number,
                totalInstallments: loan.installments.length,
                amount: installment.remainingAmount,
                dueDate: installment.dueDate,
                isReceivable: false,
              ),
            );
          }
        }
      }

      // Parcelas de empréstimos já quitadas/pagas neste ciclo
      final p2pPaidInCycle = <P2PInstallmentAudit>[];
      final p2pReceivedInCycle = <P2PInstallmentAudit>[];
      int p2pPaidInCycleCents = 0;
      int p2pReceivedInCycleCents = 0;

      for (final loan in loans) {
        for (final installment in loan.installments) {
          final paidAt = installment.paidAt;
          final wasPaidInCycle = (paidAt != null && cycle.contains(paidAt)) ||
              (paidAt == null && installment.isFullyPaid && cycle.contains(installment.dueDate));
          if (!wasPaidInCycle) continue;

          final lender = members.where((m) => m.id == loan.lenderMemberId).firstOrNull;
          final borrower = members.where((m) => m.id == loan.borrowerMemberId).firstOrNull;
          final lenderName = loan.isHouseLender ? 'Caixa da Casa' : (lender?.name ?? 'Membro');
          final borrowerName = borrower?.name ?? 'Membro';

          if (loan.borrowerMemberId == member.id) {
            p2pPaidInCycleCents += installment.paidAmount.cents;
            p2pPaidInCycle.add(
              P2PInstallmentAudit(
                loanId: loan.id,
                description: loan.title,
                otherMemberId: loan.lenderMemberId,
                otherMemberName: lenderName,
                installmentNumber: installment.number,
                totalInstallments: loan.installments.length,
                amount: installment.paidAmount,
                dueDate: installment.dueDate,
                isReceivable: false,
              ),
            );
          } else if (loan.lenderMemberId == member.id) {
            p2pReceivedInCycleCents += installment.paidAmount.cents;
            p2pReceivedInCycle.add(
              P2PInstallmentAudit(
                loanId: loan.id,
                description: loan.title,
                otherMemberId: loan.borrowerMemberId,
                otherMemberName: borrowerName,
                installmentNumber: installment.number,
                totalInstallments: loan.installments.length,
                amount: installment.paidAmount,
                dueDate: installment.dueDate,
                isReceivable: true,
              ),
            );
          }
        }
      }

      // Parte da devolução da sobra que o morador já tinha aportado: o Caixa
      // devolve. Aporte acima do devido original não entra aqui.
      final originalDueCents = dueBeforeRefund[member.id]?.cents ?? 0;
      final paidTowardsDue = paidCents < originalDueCents ? paidCents : originalDueCents;
      final contributionRefund = Money(
        paidTowardsDue > due.cents ? paidTowardsDue - due.cents : 0,
      );

      final balance = MemberNetBalance(
        memberId: member.id,
        memberName: member.name,
        contributionDue: due,
        contributionPaid: paid,
        outOfPocketExpenses: outOfPocket,
        p2pLentDue: Money(p2pLentCents),
        p2pBorrowedDue: Money(p2pBorrowedCents),
        contributionRefund: contributionRefund,
      );
      memberBalances.add(balance);

      auditTrails[member.id] = MemberAuditTrail(
        memberId: member.id,
        memberName: member.name,
        expenseShares: memberExpenseShares[member.id] ?? [],
        contributionsMade: contributionAudits,
        outOfPocketExpenses: outOfPocketAudits,
        p2pReceivables: p2pReceivables,
        p2pPayables: p2pPayables,
        contributionDue: due,
        contributionPaid: paid,
        outOfPocketTotal: outOfPocket,
        p2pLentTotal: Money(p2pLentCents),
        p2pBorrowedTotal: Money(p2pBorrowedCents),
        netBalance: balance.netBalance,
        contributionRefund: contributionRefund,
        p2pPaidInCycle: p2pPaidInCycle,
        p2pReceivedInCycle: p2pReceivedInCycle,
        p2pPaidInCycleTotal: Money(p2pPaidInCycleCents),
        p2pReceivedInCycleTotal: Money(p2pReceivedInCycleCents),
      );
    }

    // 5. Motor de Transferências Mínimas (Super Pix)
    // Agrupa em devedores (saldo líquido < 0) e credores (saldo líquido > 0)
    final pixKeys = {
      for (final m in members) m.id: m.pixKey,
      if (housePixKey != null && housePixKey.isNotEmpty)
        'entity_caixa': housePixKey,
    };
    final transfers = _computeMinimumTransfers(
      memberBalances,
      pixKeys: pixKeys,
      housePixKeyHolderName: housePixKeyHolderName,
    );

    // 6. Saldo do Caixa da Casa depois do fechamento: conta com o aporte devido
    // de todos os moradores, não só com o que já entrou até agora.
    final houseTreasuryCents = treasuryAfterClosing();

    return SettlementSummary(
      cycle: cycle,
      memberBalances: memberBalances,
      transfers: transfers,
      totalHouseExpenses: totalHouseExpenses,
      totalContributions: totalContributions,
      totalP2PCleared: Money(totalP2PClearedCents),
      houseTreasuryBalance: Money(houseTreasuryCents),
      status: SettlementStatus.readyToSettle,
      auditTrails: auditTrails,
      bucketDeficit: Money(bucketDeficitCents),
      deficitCoveredByVault: Money(deficitCoveredCents),
      openingBalance: openingBalance,
      vaultReturns: vaultReturns,
      thirdPartyInflows: Money(math.max(0, openingInflows?.thirdParty.cents ?? 0)),
      surplusRefunded: Money(surplusRefundedCents),
      houseLoanReceipts: Money(houseLoanReceiptsCents),
    );
  }

  /// Algoritmo Greedy de Redução de Dívidas às Transferências Mínimas
  static List<SuperPixTransfer> _computeMinimumTransfers(
    List<MemberNetBalance> balances, {
    Map<String, String?> pixKeys = const {},
    String? housePixKeyHolderName,
  }) {
    // Copia os saldos líquidos em centavos
    final Map<String, int> netMap = {};
    final Map<String, String> nameMap = {};

    for (final b in balances) {
      netMap[b.memberId] = b.netBalance.cents;
      nameMap[b.memberId] = b.memberName;
    }

    // Se houver saldo de aportes/reembolsos com o Caixa, a Casa entra como contraparte virtual
    final houseNetDiff = balances.fold<int>(
      0,
      (acc, b) => acc + b.netBalance.cents,
    );
    if (houseNetDiff != 0) {
      netMap['entity_caixa'] = -houseNetDiff;
      final holderSuffix =
          (housePixKeyHolderName != null && housePixKeyHolderName.isNotEmpty)
          ? ' ($housePixKeyHolderName)'
          : '';
      nameMap['entity_caixa'] = 'Caixa da Casa$holderSuffix';
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
      if (maxDebtorId == null ||
          maxCreditorId == null ||
          minNet >= 0 ||
          maxNet <= 0) {
        break;
      }

      // O valor da transferência é o menor entre a dívida e o crédito
      final debtAmount = -minNet;
      final creditAmount = maxNet;
      final transferCents = debtAmount < creditAmount
          ? debtAmount
          : creditAmount;

      if (transferCents <= 0) break;

      final fromName = nameMap[maxDebtorId] ?? 'Membro';
      final toName = nameMap[maxCreditorId] ?? 'Membro';

      final memberPixKey = pixKeys[maxCreditorId];
      // Sem chave cadastrada não há Pix para copiar: nunca inventar uma chave.
      final effectivePixKey = (memberPixKey != null && memberPixKey.isNotEmpty)
          ? memberPixKey
          : null;

      String explanation;
      if (maxDebtorId == 'entity_caixa') {
        explanation =
            'O Caixa da Casa possui sobra acumulada e reembolsa $toName por despesas adiantadas.';
      } else if (maxCreditorId == 'entity_caixa') {
        explanation =
            '$fromName repassa aporte ao Caixa da Casa para cobrir despesas comuns do ciclo.';
      } else {
        explanation =
            'Compensação direta entre $fromName e $toName para quitar saldo cruzado de despesas e empréstimos.';
      }

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
          pixKey: effectivePixKey,
          explanation: explanation,
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
