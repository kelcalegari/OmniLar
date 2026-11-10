import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/domain/value_objects/financial_cycle.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/features/finance/domain/entities/contribution.dart';
import 'package:omni_lar/features/finance/domain/entities/house_expense.dart';
import 'package:omni_lar/features/finance/domain/entities/house_member.dart';
import 'package:omni_lar/features/finance/domain/entities/split_rule.dart';
import 'package:omni_lar/features/p2p/domain/entities/p2p_installment.dart';
import 'package:omni_lar/features/p2p/domain/entities/p2p_loan.dart';
import 'package:omni_lar/features/settlement/data/settlement_summary_codec.dart';
import 'package:omni_lar/features/settlement/domain/entities/settlement_summary.dart';
import 'package:omni_lar/features/settlement/domain/services/global_clearing_engine.dart';

void main() {
  group('Aporte acima da meta abate empréstimos com o Caixa da Casa', () {
    const engine = GlobalClearingEngine();
    final cycle = FinancialCycle.fromDate(
      date: DateTime(2026, 10, 12),
      cycleStartDay: 9,
    );
    const members = [
      HouseMember(id: 'ana', name: 'Ana', defaultFixedAmountCents: 100000),
      HouseMember(id: 'bia', name: 'Bia', defaultFixedAmountCents: 100000),
    ];
    final targets = {
      for (final m in members) m.id: Money(m.defaultFixedAmountCents!),
    };

    P2PLoan houseLoanToBia(int cents, {String? repayToVaultId}) => P2PLoan(
      id: 'loan_bia',
      title: 'Compra no cartão da Casa',
      totalAmount: Money(cents),
      lenderMemberId: P2PLoan.houseLenderId,
      borrowerMemberId: 'bia',
      installmentsCount: 1,
      createdAt: DateTime(2026, 10, 9),
      firstDueDate: DateTime(2026, 10, 15),
      repayToVaultId: repayToVaultId,
      installments: [
        P2PInstallment(
          id: 'inst_1',
          loanId: 'loan_bia',
          number: 1,
          totalCount: 1,
          amount: Money(cents),
          dueDate: DateTime(2026, 10, 15),
        ),
      ],
    );

    SettlementSummary compute({
      required int biaPaidCents,
      List<P2PLoan> loans = const [],
    }) {
      return engine.computeSettlement(
        cycle: cycle,
        members: members,
        expenses: [
          HouseExpense(
            id: 'e1',
            title: 'Contas do mês',
            amount: const Money(200000),
            date: DateTime(2026, 10, 12),
            categoryId: 'c',
            paidByMemberId: 'ana',
            paymentMethodId: 'pm_caixa',
            splitRule: const SplitRule.percentage(null),
          ),
        ],
        contributions: [
          Contribution(
            id: 'c_ana',
            memberId: 'ana',
            amount: const Money(100000),
            date: DateTime(2026, 10, 10),
          ),
          Contribution(
            id: 'c_bia',
            memberId: 'bia',
            amount: Money(biaPaidCents),
            date: DateTime(2026, 10, 10),
          ),
        ],
        loans: loans,
        customContributionTargets: targets,
      );
    }

    test('O excedente abate o empréstimo e só a diferença fica a pagar', () {
      // Meta R$ 1.000,00, pagou R$ 1.800,00; deve R$ 830,00 ao Caixa
      final summary = compute(biaPaidCents: 180000, loans: [houseLoanToBia(83000)]);
      final bia = summary.memberBalances.firstWhere((b) => b.memberId == 'bia');

      expect(bia.contributionExcessApplied.cents, 80000);
      expect(bia.netBalance.cents, -3000);
      expect(summary.auditTrails['bia']!.netBalance.cents, -3000);
      // O Caixa recebe o empréstimo inteiro: R$ 800,00 já entraram como aporte
      expect(summary.houseLoanReceipts.cents, 83000);
      expect(summary.transfers.single.amount.cents, 3000);
    });

    test('O abatimento nunca passa do que o morador deve ao Caixa', () {
      final summary = compute(biaPaidCents: 180000, loans: [houseLoanToBia(20000)]);
      final bia = summary.memberBalances.firstWhere((b) => b.memberId == 'bia');

      expect(bia.contributionExcessApplied.cents, 20000);
      expect(bia.netBalance.cents, 0);
    });

    test('Sem empréstimo com o Caixa, o excedente continua fora do saldo', () {
      final summary = compute(biaPaidCents: 180000);
      final bia = summary.memberBalances.firstWhere((b) => b.memberId == 'bia');

      expect(bia.contributionExcessApplied.cents, 0);
      expect(bia.netBalance.cents, 0);
    });

    test('Reposição de Caixinha não é abatida pelo aporte', () {
      final summary = compute(
        biaPaidCents: 180000,
        loans: [houseLoanToBia(83000, repayToVaultId: 'vault-1')],
      );
      final bia = summary.memberBalances.firstWhere((b) => b.memberId == 'bia');

      expect(bia.contributionExcessApplied.cents, 0);
      expect(bia.netBalance.cents, -83000);
    });

    test('O abatimento sobrevive ao retrato gravado do fechamento', () {
      final summary = compute(biaPaidCents: 180000, loans: [houseLoanToBia(83000)]);
      final restored = settlementSummaryFromJson(
        settlementSummaryToJson(summary),
        cycle: cycle,
      )!;
      final bia = restored.memberBalances.firstWhere((b) => b.memberId == 'bia');

      expect(bia.contributionExcessApplied.cents, 80000);
      expect(bia.netBalance.cents, -3000);
      expect(restored.auditTrails['bia']!.contributionExcessApplied.cents, 80000);
    });
  });
}
