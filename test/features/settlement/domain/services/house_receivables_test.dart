import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/domain/value_objects/financial_cycle.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/features/finance/domain/entities/house_expense.dart';
import 'package:omni_lar/features/finance/domain/entities/house_member.dart';
import 'package:omni_lar/features/finance/domain/entities/split_rule.dart';
import 'package:omni_lar/features/p2p/domain/entities/p2p_installment.dart';
import 'package:omni_lar/features/p2p/domain/entities/p2p_loan.dart';
import 'package:omni_lar/features/settlement/domain/entities/settlement_summary.dart';
import 'package:omni_lar/features/settlement/domain/services/global_clearing_engine.dart';

void main() {
  group('Acordos com o Lar no Caixa do ciclo', () {
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

    // Pendência de R$ 300,00 da Bia com o Lar, vencida neste ciclo
    P2PLoan pendingFromBia() => P2PLoan(
      id: 'loan_pending',
      title: 'Pendência do ciclo anterior',
      totalAmount: const Money(30000),
      lenderMemberId: P2PLoan.houseLenderId,
      borrowerMemberId: 'bia',
      installmentsCount: 1,
      createdAt: DateTime(2026, 10, 8),
      firstDueDate: DateTime(2026, 10, 9),
      installments: [
        P2PInstallment(
          id: 'inst_1',
          loanId: 'loan_pending',
          number: 1,
          totalCount: 1,
          amount: const Money(30000),
          dueDate: DateTime(2026, 10, 9),
        ),
      ],
    );

    // Balde de R$ 3.000,00 e gastos de R$ 2.500,00 pagos pelo Caixa: sobra R$ 500,00.
    SettlementSummary compute({
      List<P2PLoan> loans = const [],
      Money houseShortfallAlreadySettled = const Money.zero(),
      Money houseLoansAlreadyReceived = const Money.zero(),
      Money surplusAlreadyVaulted = const Money.zero(),
    }) {
      return engine.computeSettlement(
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
        customContributionTargets: targets,
        houseShortfallAlreadySettled: houseShortfallAlreadySettled,
        houseLoansAlreadyReceived: houseLoansAlreadyReceived,
        surplusAlreadyVaulted: surplusAlreadyVaulted,
      );
    }

    test('Reposição de Caixinha é cobrada do morador, mas não entra na sobra do Caixa', () {
      final plain = compute(loans: [pendingFromBia()]);
      final repayment = compute(
        loans: [pendingFromBia().copyWith(repayToVaultId: 'vault-1')],
      );

      // O morador deve o mesmo nos dois casos
      final bia = repayment.memberBalances.firstWhere((b) => b.memberId == 'bia');
      expect(bia.netBalance.cents, -(130000 + 30000));
      // O pagamento volta para a Caixinha: não é entrada do Caixa nem vira sobra
      expect(repayment.houseLoanReceipts.cents, 0);
      expect(
        repayment.houseTreasuryBalance.cents,
        plain.houseTreasuryBalance.cents - 30000,
      );
    });

    test('Pendência com o Lar é cobrada do morador e entra na sobra do ciclo', () {
      final summary = compute(loans: [pendingFromBia()]);

      final bia = summary.memberBalances.firstWhere((b) => b.memberId == 'bia');
      expect(bia.netBalance.cents, -(130000 + 30000));
      expect(summary.houseLoanReceipts.cents, 30000);
      expect(summary.houseTreasuryBalance.cents, 50000 + 30000);
    });

    test('Ciclo reaberto: o que já entrou de acordos com o Lar continua contando', () {
      // A parcela já foi quitada no fechamento anterior e a sobra de R$ 800,00 foi guardada
      final summary = compute(
        houseLoansAlreadyReceived: const Money(30000),
        surplusAlreadyVaulted: const Money(80000),
      );

      expect(summary.houseTreasuryBalance.cents, 0);
    });

    test('Ciclo reaberto: o que ficou a receber ou foi perdoado não volta como sobra', () {
      // No fechamento anterior faltaram R$ 300,00 e só R$ 200,00 foram guardados
      final summary = compute(
        houseShortfallAlreadySettled: const Money(30000),
        surplusAlreadyVaulted: const Money(20000),
      );

      expect(summary.houseTreasuryBalance.cents, 0);
    });
  });
}
