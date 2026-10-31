import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/domain/value_objects/financial_cycle.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/features/finance/domain/entities/contribution.dart';
import 'package:omni_lar/features/finance/domain/entities/house_expense.dart';
import 'package:omni_lar/features/finance/domain/entities/house_member.dart';
import 'package:omni_lar/features/finance/domain/entities/house_settings.dart';
import 'package:omni_lar/features/finance/domain/entities/opening_inflows.dart';
import 'package:omni_lar/features/finance/domain/entities/split_rule.dart';
import 'package:omni_lar/features/p2p/domain/entities/p2p_installment.dart';
import 'package:omni_lar/features/p2p/domain/entities/p2p_loan.dart';
import 'package:omni_lar/features/settlement/domain/entities/settlement_summary.dart';
import 'package:omni_lar/features/settlement/domain/services/global_clearing_engine.dart';

// Ciclo 07/10 a 06/11/2026 da Nossa Casa: o Caixa pagou R$ 1.734,09 de faturas
// dos moradores, eles devolveram pela Reserva e a Reserva voltou ao ciclo.
void main() {
  const engine = GlobalClearingEngine();
  final cycle = FinancialCycle.fromDate(date: DateTime(2026, 10, 12), cycleStartDay: 7);
  const members = [
    HouseMember(id: 'kel', name: 'Kelvynn', defaultFixedAmountCents: 243500),
    HouseMember(id: 'cri', name: 'Cristiano', defaultFixedAmountCents: 71500),
  ];
  const vault = 'vault_reserva';

  final loan = P2PLoan(
    id: 'loan_fatura',
    title: 'Inter Credito (venc. 12/10) — Cristiano',
    totalAmount: const Money(173409),
    lenderMemberId: P2PLoan.houseLenderId,
    borrowerMemberId: 'cri',
    installmentsCount: 1,
    createdAt: DateTime(2026, 10, 18),
    firstDueDate: DateTime(2026, 10, 12),
    houseFunding: HouseLoanFunding.cycle,
    fundedOn: DateTime(2026, 10, 12),
    installments: [
      P2PInstallment(
        id: 'inst_1',
        loanId: 'loan_fatura',
        number: 1,
        totalCount: 1,
        amount: const Money(173409),
        paidAmount: const Money(173409),
        dueDate: DateTime(2026, 10, 12),
      ),
    ],
  );

  SettlementSummary compute({List<P2PLoan>? loans, int vaultCents = 179958}) => engine.computeSettlement(
        cycle: cycle,
        members: members,
        expenses: [
          HouseExpense(
            id: 'e1',
            title: 'Contas do ciclo',
            amount: const Money(379911),
            date: DateTime(2026, 10, 12),
            categoryId: 'c',
            paidByMemberId: 'kel',
            paymentMethodId: 'pm_caixa',
            splitRule: const SplitRule.percentage(null),
          ),
        ],
        contributions: [
          Contribution(id: 'a1', memberId: 'kel', amount: const Money(281163), date: DateTime(2026, 10, 17)),
          Contribution(id: 'a2', memberId: 'cri', amount: const Money(100916), date: DateTime(2026, 10, 17)),
        ],
        loans: loans ?? [loan],
        customContributionTargets: {for (final m in members) m.id: Money(m.defaultFixedAmountCents!)},
        openingBalance: Money(vaultCents + 18700),
        vaultReturns: Money(vaultCents),
        openingBalanceRule: OpeningBalanceRule.coverExcess,
        openingInflows: OpeningInflows(
          vaultWithdrawalsByVault: {vault: Money(vaultCents)},
          thirdParty: const Money(18700),
        ),
        openingInflowRules: const OpeningInflowRules(
          vaultWithdrawals: OpeningBalanceRule.coverExcess,
          thirdParty: OpeningBalanceRule.reduceQuotas,
        ),
      );

  int totalDue(SettlementSummary s) => s.memberBalances.fold<int>(0, (acc, b) => acc + b.contributionDue.cents);

  test('a devolução do empréstimo pela Reserva não cobre o excedente do balde', () {
    final s = compute();
    // Excedente 649,11; só 65,49 da Reserva é dinheiro livre: 583,62 ficam com os moradores
    expect(totalDue(s), 315000 - 18700 + 58362);
    expect(s.houseTreasuryBalance.cents, 0);
    expect(s.houseLoansFunded.cents, 173409);
  });

  test('sem empréstimo no ciclo, a Reserva cobre o excedente como antes', () {
    final s = compute(loans: const [], vaultCents: 6549);
    expect(totalDue(s), 315000 - 18700 + 58362);
    final full = compute(loans: const []);
    expect(totalDue(full), 315000 - 18700);
    expect(full.houseLoansFunded.cents, 0);
  });
}
