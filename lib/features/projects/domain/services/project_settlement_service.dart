import '../../../../core/domain/value_objects/money.dart';
import '../../../finance/domain/entities/house_expense.dart';
import '../../../finance/domain/entities/split_rule.dart';
import '../../../settlement/domain/entities/super_pix_transfer.dart';
import '../entities/project_participant.dart';
import '../entities/project_settlement_summary.dart';
import '../entities/shared_project.dart';

class ProjectSettlementService {
  const ProjectSettlementService();

  /// Calcula o fechamento e as transferências mínimas de compensação (Super Pix)
  /// de um projeto específico (ex: viagem, churrasco, reforma).
  ProjectSettlementSummary computeProjectSettlement({
    required SharedProject project,
    required List<HouseExpense> expenses,
    required List<ProjectParticipant> participants,
  }) {
    // 1. Total das despesas do projeto
    final totalExpensesCents = expenses.fold<int>(
      0,
      (acc, e) => acc + e.amount.cents,
    );
    final totalExpenses = Money(totalExpensesCents);

    // Lista mutável de participantes caso alguma despesa mencione um pagador avulso
    final activeParticipants = List<ProjectParticipant>.from(participants);

    // Função para resolver o participante a partir de id, userId ou nome
    ProjectParticipant resolveParticipant(String idOrUserId) {
      final found = activeParticipants.where(
        (p) => p.id == idOrUserId ||
               p.userId == idOrUserId ||
               (p.externalName != null && p.externalName!.toLowerCase() == idOrUserId.toLowerCase()),
      );
      if (found.isNotEmpty) {
        return found.first;
      }
      // Se não encontrado, cria um participante com este identificador para não distorcer o rateio
      final newParticipant = ProjectParticipant(
        id: idOrUserId,
        projectId: project.id,
        externalName: idOrUserId,
        createdAt: DateTime.now(),
      );
      activeParticipants.add(newParticipant);
      return newParticipant;
    }

    // Pré-registra pagadores que possam não estar na lista de participantes inicial
    for (final exp in expenses) {
      resolveParticipant(exp.paidByMemberId);
    }

    // Inicialização dos acumuladores por participant.id
    final Map<String, int> paidCentsMap = {for (final p in activeParticipants) p.id: 0};
    final Map<String, int> dueCentsMap = {for (final p in activeParticipants) p.id: 0};

    // 2. Acumula quem pagou o quê
    for (final exp in expenses) {
      final payer = resolveParticipant(exp.paidByMemberId);
      paidCentsMap[payer.id] = (paidCentsMap[payer.id] ?? 0) + exp.amount.cents;

      // 3. Acumula a responsabilidade de quem deve
      if (exp.isItemized) {
        for (final item in exp.items) {
          final SplitRule itemRule = item.splitRule ??
              (item.responsibleMemberId != null
                  ? SplitRule.singleResponsible(item.responsibleMemberId!)
                  : exp.splitRule);
          final allocations = _calculateAllocations(itemRule, item.amount, activeParticipants, sharers: participants);
          for (final entry in allocations.entries) {
            dueCentsMap[entry.key] = (dueCentsMap[entry.key] ?? 0) + entry.value.cents;
          }
        }
      } else {
        final allocations = _calculateAllocations(exp.splitRule, exp.amount, activeParticipants, sharers: participants);
        for (final entry in allocations.entries) {
          dueCentsMap[entry.key] = (dueCentsMap[entry.key] ?? 0) + entry.value.cents;
        }
      }
    }

    // 4. Monta o saldo líquido de cada participante
    final List<ParticipantProjectBalance> balances = [];
    final Map<String, int> netCentsMap = {};
    final Map<String, String> nameMap = {};

    for (final p in activeParticipants) {
      final paid = Money(paidCentsMap[p.id] ?? 0);
      final due = Money(dueCentsMap[p.id] ?? 0);
      final netCents = paid.cents - due.cents;

      balances.add(
        ParticipantProjectBalance(
          participantId: p.id,
          participantName: p.displayName,
          totalPaid: paid,
          totalShareDue: due,
          netBalance: Money(netCents),
        ),
      );

      netCentsMap[p.id] = netCents;
      nameMap[p.id] = p.displayName;
    }

    // 5. Algoritmo Greedy de Redução às Transferências Mínimas
    final Map<String, String> pixKeyMap = {};
    for (final p in activeParticipants) {
      if (p.pixKey != null && p.pixKey!.isNotEmpty) {
        pixKeyMap[p.id] = p.pixKey!;
      }
    }

    final transfers = _computeMinimumTransfers(
      netCentsMap,
      nameMap,
      project.title,
      pixKeyMap: pixKeyMap,
    );

    return ProjectSettlementSummary(
      project: project,
      totalExpenses: totalExpenses,
      participantBalances: balances,
      transfers: transfers,
    );
  }

  /// [participants] é todo mundo que aparece no acerto (inclui quem só pagou);
  /// [sharers] são os participantes do projeto, entre quem a despesa é dividida.
  Map<String, Money> _calculateAllocations(
    SplitRule rule,
    Money totalAmount,
    List<ProjectParticipant> participants, {
    List<ProjectParticipant>? sharers,
  }) {
    if (participants.isEmpty) return {};
    final sharing = (sharers == null || sharers.isEmpty) ? participants : sharers;

    switch (rule.type) {
      case SplitType.categoryOwner:
        final targetId = rule.singleResponsibleMemberId;
        final targetParticipant = participants.firstWhere(
          (p) => p.id == targetId || p.userId == targetId || p.externalName == targetId,
          orElse: () => participants.first,
        );
        return {
          for (final p in participants)
            p.id: p.id == targetParticipant.id ? totalAmount : const Money.zero(),
        };

      case SplitType.fixed:
        if (rule.fixedAmounts != null && rule.fixedAmounts!.isNotEmpty) {
          final res = <String, Money>{};
          for (final p in participants) {
            final fixedMoney = rule.fixedAmounts![p.id] ??
                (p.userId != null ? rule.fixedAmounts![p.userId!] : null) ??
                (p.externalName != null ? rule.fixedAmounts![p.externalName!] : null) ??
                const Money.zero();
            res[p.id] = fixedMoney;
          }
          return res;
        }
        final parts = totalAmount.splitEqually(participants.length);
        return {
          for (int i = 0; i < participants.length; i++) participants[i].id: parts[i],
        };

      case SplitType.percentage:
        // Despesa de projeto não segue o rateio da casa (que vem gravado na
        // despesa): divide entre os participantes do projeto, pelo percentual
        // de cada um. Se algum não tiver percentual, divide igual. Os
        // percentuais são normalizados, então tirar alguém redistribui a parte
        // dele entre os que ficam.
        final res = <String, Money>{for (final p in participants) p.id: const Money.zero()};
        final totalPercent = sharing.fold<double>(0, (acc, p) => acc + (p.defaultSplitPercent ?? 0));
        final allDefined = sharing.every((p) => (p.defaultSplitPercent ?? 0) > 0);
        if (allDefined && totalPercent > 0) {
          int allocatedCents = 0;
          for (int i = 0; i < sharing.length; i++) {
            final p = sharing[i];
            if (i == sharing.length - 1) {
              res[p.id] = Money(totalAmount.cents - allocatedCents);
            } else {
              final share = Money((totalAmount.cents * p.defaultSplitPercent! / totalPercent).round());
              res[p.id] = share;
              allocatedCents += share.cents;
            }
          }
          return res;
        }

        final parts = totalAmount.splitEqually(sharing.length);
        for (int i = 0; i < sharing.length; i++) {
          res[sharing[i].id] = parts[i];
        }
        return res;
    }
  }

  static List<SuperPixTransfer> _computeMinimumTransfers(
    Map<String, int> netMap,
    Map<String, String> nameMap,
    String projectTitle, {
    Map<String, String> pixKeyMap = const {},
  }) {
    final Map<String, int> remainingNet = Map.from(netMap);
    final List<SuperPixTransfer> transfers = [];
    int transferCounter = 1;

    while (true) {
      String? maxDebtorId;
      int minNet = 0;

      String? maxCreditorId;
      int maxNet = 0;

      for (final entry in remainingNet.entries) {
        if (entry.value < minNet) {
          minNet = entry.value;
          maxDebtorId = entry.key;
        }
        if (entry.value > maxNet) {
          maxNet = entry.value;
          maxCreditorId = entry.key;
        }
      }

      if (maxDebtorId == null || maxCreditorId == null || minNet >= 0 || maxNet <= 0) {
        break;
      }

      final debtAmount = -minNet;
      final creditAmount = maxNet;
      final transferCents = debtAmount < creditAmount ? debtAmount : creditAmount;

      if (transferCents <= 0) break;

      final fromName = nameMap[maxDebtorId] ?? 'Participante';
      final toName = nameMap[maxCreditorId] ?? 'Participante';

      transfers.add(
        SuperPixTransfer(
          id: 'proj_transfer_$transferCounter',
          fromMemberId: maxDebtorId,
          fromMemberName: fromName,
          toMemberId: maxCreditorId,
          toMemberName: toName,
          amount: Money(transferCents),
          description: 'Acerto de Contas ($projectTitle): $fromName ➔ $toName',
          status: TransferStatus.pending,
          pixKey: pixKeyMap[maxCreditorId],
        ),
      );

      remainingNet[maxDebtorId] = remainingNet[maxDebtorId]! + transferCents;
      remainingNet[maxCreditorId] = remainingNet[maxCreditorId]! - transferCents;

      transferCounter++;
    }

    return transfers;
  }
}
