import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/domain/value_objects/financial_cycle.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/features/finance/domain/entities/house_expense.dart';
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
  });
}
