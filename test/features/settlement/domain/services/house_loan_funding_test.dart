import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/domain/value_objects/financial_cycle.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/features/finance/domain/entities/financial_cycle_summary.dart';
import 'package:omni_lar/features/finance/domain/entities/house_expense.dart';
import 'package:omni_lar/features/finance/domain/entities/house_member.dart';
import 'package:omni_lar/features/finance/domain/entities/split_rule.dart';
import 'package:omni_lar/features/p2p/data/datasources/p2p_loan_payload.dart';
import 'package:omni_lar/features/p2p/data/offline/p2p_loan_offline_codec.dart';
import 'package:omni_lar/features/p2p/domain/entities/p2p_installment.dart';
import 'package:omni_lar/features/p2p/domain/entities/p2p_loan.dart';
import 'package:omni_lar/features/settlement/domain/services/global_clearing_engine.dart';

void main() {
  const engine = GlobalClearingEngine();
  final cycle = FinancialCycle.fromDate(date: DateTime(2026, 10, 12), cycleStartDay: 9);
  const members = [
    HouseMember(id: 'ana', name: 'Ana', defaultFixedAmountCents: 150000),
    HouseMember(id: 'bia', name: 'Bia', defaultFixedAmountCents: 150000),
  ];

  // Empréstimo de R$ 200,00 do Caixa para a Bia, com parcela no ciclo seguinte
  P2PLoan loan({HouseLoanFunding? funding, DateTime? fundedOn, String? vaultId}) => P2PLoan(
        id: 'loan_caixa',
        title: 'Conserto do carro',
        totalAmount: const Money(20000),
        lenderMemberId: P2PLoan.houseLenderId,
        borrowerMemberId: 'bia',
        installmentsCount: 1,
        createdAt: DateTime(2026, 10, 12),
        firstDueDate: DateTime(2026, 11, 12),
        houseFunding: funding,
        fundedOn: fundedOn,
        repayToVaultId: vaultId,
        installments: [
          P2PInstallment(
            id: 'inst_1',
            loanId: 'loan_caixa',
            number: 1,
            totalCount: 1,
            amount: const Money(20000),
            dueDate: DateTime(2026, 11, 12),
          ),
        ],
      );

  // Balde de R$ 3.000,00 e contas de R$ 2.500,00: sobra R$ 500,00
  int treasuryWith(List<P2PLoan> loans) => engine
      .computeSettlement(
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
        contributions: const [],
        loans: loans,
        customContributionTargets: {for (final m in members) m.id: Money(m.defaultFixedAmountCents!)},
      )
      .houseTreasuryBalance
      .cents;

  group('Empréstimo do Caixa da Casa no fechamento', () {
    test('liberado do Caixa neste ciclo: sai da sobra', () {
      expect(treasuryWith(const []), 50000);
      expect(
        treasuryWith([loan(funding: HouseLoanFunding.cycle, fundedOn: DateTime(2026, 10, 12))]),
        30000,
      );
    });

    test('liberado num ciclo anterior não mexe na sobra deste', () {
      expect(
        treasuryWith([loan(funding: HouseLoanFunding.cycle, fundedOn: DateTime(2026, 9, 20))]),
        50000,
      );
    });

    test('da caixinha não sai do Caixa do ciclo', () {
      expect(
        treasuryWith([
          loan(funding: HouseLoanFunding.vault, fundedOn: DateTime(2026, 10, 12), vaultId: 'v1'),
        ]),
        50000,
      );
    });

    test('acordo antigo, sem origem, continua igual', () {
      expect(treasuryWith([loan()]), 50000);
    });
  });

  test('a sobra de abertura não muda com o empréstimo descontado do fôlego', () {
    final summary = FinancialCycleSummary(
      cycle: cycle,
      totalContributions: const Money(300000),
      totalExpensesPaid: const Money(250000),
      committedFutureExpenses: const Money.zero(),
      // 100 de sobra anterior + 3000 - 2500 - 200 emprestados
      folego: const Money(40000),
      memberContributions: const {},
      memberExpensesPaid: const {},
      houseLoansFunded: const Money(20000),
    );
    expect(summary.openingBalance.cents, 10000);
  });

  group('payload e fila offline', () {
    test('do ciclo vai com a origem; da caixinha, só pelo create_house_loan', () {
      final cyclePayload = p2pLoanPayload(
        loan(funding: HouseLoanFunding.cycle, fundedOn: DateTime(2026, 10, 12)),
        houseId: 'h',
      );
      expect(cyclePayload['house_funding'], 'cycle');
      expect(cyclePayload['funded_on'], '2026-10-12');
      expect(cyclePayload['lender_is_house'], isTrue);

      final vaultPayload = p2pLoanPayload(
        loan(funding: HouseLoanFunding.vault, fundedOn: DateTime(2026, 10, 12), vaultId: 'v1'),
        houseId: 'h',
      );
      expect(vaultPayload.containsKey('house_funding'), isFalse);
    });

    test('a origem sobrevive à fila offline', () {
      final original = loan(funding: HouseLoanFunding.vault, fundedOn: DateTime(2026, 10, 12), vaultId: 'v1');
      final restored = p2pLoanFromJson(p2pLoanToJson(original));
      expect(restored.houseFunding, HouseLoanFunding.vault);
      expect(restored.fundedOn, DateTime(2026, 10, 12));
      expect(restored.repayToVaultId, 'v1');
    });
  });
}
