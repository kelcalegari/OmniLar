import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/domain/value_objects/financial_cycle.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/features/finance/domain/entities/contribution.dart';
import 'package:omni_lar/features/finance/domain/entities/house_expense.dart';
import 'package:omni_lar/features/finance/domain/entities/house_expense_item.dart';
import 'package:omni_lar/features/finance/domain/entities/house_member.dart';
import 'package:omni_lar/features/finance/domain/entities/split_rule.dart';
import 'package:omni_lar/features/settlement/domain/entities/settlement_options.dart';
import 'package:omni_lar/features/settlement/domain/entities/settlement_summary.dart';
import 'package:omni_lar/features/settlement/domain/services/global_clearing_engine.dart';

void main() {
  group('Excedente do balde (aportes fixos)', () {
    const engine = GlobalClearingEngine();
    final cycle = FinancialCycle.fromDate(
      date: DateTime(2026, 10, 12),
      cycleStartDay: 9,
    );
    const members = [
      HouseMember(id: 'ana', name: 'Ana', defaultFixedAmountCents: 70000),
      HouseMember(id: 'bia', name: 'Bia', defaultFixedAmountCents: 130000),
      HouseMember(id: 'caio', name: 'Caio', defaultFixedAmountCents: 100000),
    ];
    final targets = {
      for (final m in members) m.id: Money(m.defaultFixedAmountCents!),
    };

    // Balde de R$ 3.000,00; Ana adiantou do bolso R$ 3.600,00 em contas.
    SettlementSummary compute({
      int expenseCents = 360000,
      DeficitSplit split = DeficitSplit.proportional,
      Money vaultBalance = const Money.zero(),
    }) {
      return engine.computeSettlement(
        cycle: cycle,
        members: members,
        expenses: [
          HouseExpense(
            id: 'e1',
            title: 'Contas do mês',
            amount: Money(expenseCents),
            date: DateTime(2026, 10, 12),
            categoryId: 'c',
            paidByMemberId: 'ana',
            paymentMethodId: 'pm',
            splitRule: const SplitRule.percentage(null),
            paidOutOfPocket: true,
          ),
        ],
        contributions: const [],
        loans: const [],
        customContributionTargets: targets,
        deficitSplit: split,
        deficitVaultBalance: vaultBalance,
      );
    }

    int due(SettlementSummary s, String id) =>
        s.memberBalances.firstWhere((b) => b.memberId == id).contributionDue.cents;

    test('Gastos dentro do balde não geram excedente', () {
      final summary = compute(expenseCents: 250000);

      expect(summary.bucketDeficit.cents, 0);
      expect(due(summary, 'ana'), 70000);
      expect(due(summary, 'bia'), 130000);
      expect(due(summary, 'caio'), 100000);
    });

    test('Rateio proporcional soma o excedente na proporção do aporte fixo', () {
      final summary = compute();

      expect(summary.bucketDeficit.cents, 60000);
      expect(summary.deficitCoveredByVault.cents, 0);
      expect(due(summary, 'ana'), 70000 + 14000);
      expect(due(summary, 'bia'), 130000 + 26000);
      expect(due(summary, 'caio'), 100000 + 20000);
      // Sem caixinha, o que os moradores devem cobre exatamente as contas
      expect(summary.isNetZeroSum, isTrue);
    });

    test('Rateio em partes iguais divide o excedente igualmente', () {
      final summary = compute(split: DeficitSplit.equal);

      expect(due(summary, 'ana'), 70000 + 20000);
      expect(due(summary, 'bia'), 130000 + 20000);
      expect(due(summary, 'caio'), 100000 + 20000);
    });

    test('Caixinha cobre parte do excedente e só o restante é rateado', () {
      final summary = compute(
        split: DeficitSplit.equal,
        vaultBalance: const Money(45000),
      );

      expect(summary.bucketDeficit.cents, 60000);
      expect(summary.deficitCoveredByVault.cents, 45000);
      expect(due(summary, 'ana'), 70000 + 5000);
      expect(due(summary, 'bia'), 130000 + 5000);
      expect(due(summary, 'caio'), 100000 + 5000);

      // O que a caixinha cobriu chega a quem adiantou as contas pelo Caixa da Casa
      final fromCaixa = summary.transfers
          .where((t) => t.fromMemberId == 'entity_caixa')
          .fold<int>(0, (acc, t) => acc + t.amount.cents);
      expect(fromCaixa, 45000);
    });

    test('Caixinha com saldo de sobra cobre tudo e ninguém paga a mais', () {
      final summary = compute(vaultBalance: const Money(999999));

      expect(summary.deficitCoveredByVault.cents, 60000);
      expect(due(summary, 'ana'), 70000);
      expect(due(summary, 'bia'), 130000);
      expect(due(summary, 'caio'), 100000);
    });
    test('Sub-itens pessoais são cobrados do responsável e não consomem o balde', () {
      // Boleto de R$ 3.100,00 pago pelo Caixa: R$ 200,00 são só da Ana.
      final summary = engine.computeSettlement(
        cycle: cycle,
        members: members,
        expenses: [
          HouseExpense(
            id: 'e1',
            title: 'Condomínio',
            amount: const Money(310000),
            date: DateTime(2026, 10, 12),
            categoryId: 'c',
            paidByMemberId: 'ana',
            paymentMethodId: 'pm',
            splitRule: const SplitRule.percentage(null),
            items: const [
              HouseExpenseItem(
                id: 'i1',
                expenseId: 'e1',
                title: 'Taxa condominial',
                amount: Money(290000),
              ),
              HouseExpenseItem(
                id: 'i2',
                expenseId: 'e1',
                title: 'Fundo Reserva',
                amount: Money(20000),
                responsibleMemberId: 'ana',
                splitRule: SplitRule.singleResponsible('ana'),
              ),
            ],
          ),
        ],
        contributions: const [],
        loans: const [],
        customContributionTargets: targets,
      );

      // R$ 2.900,00 de gastos comuns cabem no balde de R$ 3.000,00
      expect(summary.bucketDeficit.cents, 0);
      expect(due(summary, 'ana'), 70000 + 20000);
      expect(due(summary, 'bia'), 130000);
      expect(due(summary, 'caio'), 100000);
      expect(summary.totalPersonalExpensesInBills.cents, 20000);
      expect(summary.auditTrails['ana']!.personalItemsSharesTotal.cents, 20000);
    });
    test('Sobra do Caixa conta com o aporte de todos, não só com o que já entrou', () {
      // Balde de R$ 3.000,00, gastos de R$ 2.500,00 e só a Ana aportou até agora.
      final summary = engine.computeSettlement(
        cycle: cycle,
        members: members,
        expenses: [
          HouseExpense(
            id: 'e1',
            title: 'Contas do mês',
            amount: const Money(250000),
            date: DateTime(2026, 10, 12),
            categoryId: 'c',
            paidByMemberId: 'ana',
            paymentMethodId: 'pm_caixa',
            splitRule: const SplitRule.percentage(null),
          ),
        ],
        contributions: [
          Contribution(
            id: 'c1',
            memberId: 'ana',
            amount: const Money(70000),
            date: DateTime(2026, 10, 12),
          ),
        ],
        loans: const [],
        customContributionTargets: targets,
      );

      expect(summary.houseTreasuryBalance.cents, 50000);
    });
    group('Destino da sobra', () {
      // Balde de R$ 3.000,00 e gastos de R$ 2.500,00 pagos pelo Caixa: sobra R$ 500,00.
      SettlementSummary computeSurplus({
        int expenseCents = 250000,
        List<Contribution> contributions = const [],
        Money openingBalance = const Money.zero(),
        Money vaultReturns = const Money.zero(),
        Money surplusAlreadyRolled = const Money.zero(),
        Money surplusAlreadyRefunded = const Money.zero(),
        bool refundSurplus = false,
      }) {
        return engine.computeSettlement(
          cycle: cycle,
          members: members,
          expenses: [
            HouseExpense(
              id: 'e1',
              title: 'Contas do mês',
              amount: Money(expenseCents),
              date: DateTime(2026, 10, 12),
              categoryId: 'c',
              paidByMemberId: 'ana',
              paymentMethodId: 'pm_caixa',
              splitRule: const SplitRule.percentage(null),
            ),
          ],
          contributions: contributions,
          loans: const [],
          customContributionTargets: targets,
          openingBalance: openingBalance,
          vaultReturns: vaultReturns,
          surplusAlreadyRolled: surplusAlreadyRolled,
          surplusAlreadyRefunded: surplusAlreadyRefunded,
          refundSurplus: refundSurplus,
        );
      }

      test('Devolver aos membros abate a sobra do aporte, na proporção do aporte fixo', () {
        final summary = computeSurplus(refundSurplus: true);

        expect(summary.surplusRefunded.cents, 50000);
        expect(summary.houseTreasuryBalance.cents, 0);
        // 700 / 1300 / 1000 de um balde de 3000
        expect(due(summary, 'ana'), closeTo(70000 - 11667, 1));
        expect(due(summary, 'bia'), closeTo(130000 - 21667, 1));
        expect(due(summary, 'caio'), closeTo(100000 - 16667, 1));
        expect(
          due(summary, 'ana') + due(summary, 'bia') + due(summary, 'caio'),
          300000 - 50000,
        );
      });

      test('Quem já aportou tudo recebe a devolução de volta do Caixa', () {
        final summary = computeSurplus(
          refundSurplus: true,
          contributions: [
            Contribution(
              id: 'c1',
              memberId: 'ana',
              amount: const Money(70000),
              date: DateTime(2026, 10, 12),
            ),
          ],
        );

        final ana = summary.memberBalances.firstWhere((b) => b.memberId == 'ana');
        expect(ana.contributionRefund.cents, closeTo(11667, 1));
        expect(ana.netBalance.cents, ana.contributionRefund.cents);
        // O Caixa devolve a parte dela e recebe o aporte (já abatido) dos outros dois
        expect(
          summary.transfers.where((t) => t.toMemberId == 'ana').fold<int>(0, (acc, t) => acc + t.amount.cents),
          ana.contributionRefund.cents,
        );
      });

      test('Ciclo reaberto não devolve de novo o que já foi devolvido', () {
        final summary = computeSurplus(surplusAlreadyRefunded: const Money(50000));

        expect(summary.surplusRefunded.cents, 0);
        expect(summary.houseTreasuryBalance.cents, 0);
        expect(due(summary, 'ana'), closeTo(70000 - 11667, 1));
      });

      test('Sobra já deixada para o próximo ciclo não conta de novo ao reabrir', () {
        final summary = computeSurplus(surplusAlreadyRolled: const Money(50000));

        expect(summary.houseTreasuryBalance.cents, 0);
        expect(due(summary, 'ana'), 70000);
      });

      test('Sobra do ciclo anterior é folga: cobre o excedente antes do rateio', () {
        // Gastos de R$ 3.300,00 contra um balde de R$ 3.000,00, com R$ 500,00 herdados
        final summary = computeSurplus(
          expenseCents: 330000,
          openingBalance: const Money(50000),
        );

        expect(summary.bucketDeficit.cents, 0);
        expect(due(summary, 'ana'), 70000);
        expect(due(summary, 'bia'), 130000);
        expect(due(summary, 'caio'), 100000);
        // Sobram R$ 200,00 da folga
        expect(summary.houseTreasuryBalance.cents, 20000);
      });

      test('O que voltou das caixinhas não cobre o excedente: os moradores pagam', () {
        // Gastos de R$ 3.300,00 contra um balde de R$ 3.000,00; os R$ 500,00 no
        // Caixa vieram de um resgate devolvido ao ciclo
        final summary = computeSurplus(
          expenseCents: 330000,
          openingBalance: const Money(50000),
          vaultReturns: const Money(50000),
        );

        expect(summary.bucketDeficit.cents, 30000);
        expect(
          due(summary, 'ana') + due(summary, 'bia') + due(summary, 'caio'),
          300000 + 30000,
        );
        // O dinheiro da caixinha continua no Caixa como sobra
        expect(summary.houseTreasuryBalance.cents, 50000);
        expect(summary.vaultReturns.cents, 50000);
      });

      test('Sobra anterior junto com devolução: só a sobra anterior cobre o excedente', () {
        final summary = computeSurplus(
          expenseCents: 330000,
          openingBalance: const Money(80000),
          vaultReturns: const Money(50000),
        );

        // R$ 300,00 de sobra anterior cobrem os R$ 300,00 de excedente
        expect(summary.bucketDeficit.cents, 0);
        expect(due(summary, 'ana') + due(summary, 'bia') + due(summary, 'caio'), 300000);
        expect(summary.houseTreasuryBalance.cents, 50000);
      });

      test('Folga menor que o excedente: só a diferença é rateada', () {
        final summary = computeSurplus(
          expenseCents: 360000,
          openingBalance: const Money(50000),
        );

        expect(summary.bucketDeficit.cents, 10000);
        expect(
          due(summary, 'ana') + due(summary, 'bia') + due(summary, 'caio'),
          300000 + 10000,
        );
        expect(summary.houseTreasuryBalance.cents, 0);
      });

      test('Sem gastos acima do balde, a folga herdada continua como sobra', () {
        final summary = computeSurplus(openingBalance: const Money(50000));

        expect(due(summary, 'ana'), 70000);
        expect(summary.houseTreasuryBalance.cents, 100000);
      });
    });
  });
}
