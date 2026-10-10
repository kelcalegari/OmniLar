import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/domain/value_objects/financial_cycle.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/features/finance/domain/entities/contribution.dart';
import 'package:omni_lar/features/finance/domain/entities/house_expense.dart';
import 'package:omni_lar/features/finance/domain/entities/house_member.dart';
import 'package:omni_lar/features/finance/domain/entities/split_rule.dart';
import 'package:omni_lar/features/p2p/domain/entities/p2p_installment.dart';
import 'package:omni_lar/features/p2p/domain/entities/p2p_loan.dart';
import 'package:omni_lar/features/settlement/domain/services/global_clearing_engine.dart';

void main() {
  group('GlobalClearingEngine (Motor de Compensação / Super Pix)', () {
    const engine = GlobalClearingEngine();
    final cycle = FinancialCycle(
      start: DateTime(2026, 10, 5),
      end: DateTime(2026, 11, 4),
    );

    test('Caso Obrigatório RN-INT-02 da especificação: Kelvynn, Cris e Casa', () {
      final members = [
        const HouseMember(id: 'member_kelvynn', name: 'Kelvynn', role: 'owner'),
        const HouseMember(id: 'member_cris', name: 'Cris', role: 'member'),
      ];

      // Kelvynn pagou a luz de R$ 200 do próprio bolso (crédito contra a Casa)
      final expenses = [
        HouseExpense(
          id: 'exp_luz',
          title: 'Conta de Luz',
          amount: const Money(20000), // R$ 200,00
          date: DateTime(2026, 10, 15),
          paidByMemberId: 'member_kelvynn',
          paidOutOfPocket: true,
          dueDate: DateTime(2026, 10, 15),
          categoryId: 'cat_contas',
          paymentMethodId: 'pm_personal',
          splitRule: const SplitRule.percentage({'member_kelvynn': 60, 'member_cris': 40}),
        ),
      ];

      // Kelvynn deve R$ 100 para o Cris (P2P de um jogo)
      final loans = [
        P2PLoan(
          id: 'loan_jogo',
          title: 'Jogo de Videogame',
          totalAmount: const Money(10000), // R$ 100,00
          lenderMemberId: 'member_cris',
          borrowerMemberId: 'member_kelvynn',
          installmentsCount: 1,
          createdAt: DateTime(2026, 10, 10),
          firstDueDate: DateTime(2026, 10, 20),
          installments: [
            P2PInstallment(
              id: 'inst_jogo_1',
              loanId: 'loan_jogo',
              number: 1,
              totalCount: 1,
              amount: const Money(10000), // R$ 100,00
              dueDate: DateTime(2026, 10, 20),
            ),
          ],
        ),
      ];

      // Metas de aporte: Kelvynn deve 500, Cris deve 100
      final customTargets = {
        'member_kelvynn': const Money(50000), // R$ 500,00
        'member_cris': const Money(10000), // R$ 100,00
      };

      // Cris já pagou seu aporte de 100
      final contributions = [
        Contribution(
          id: 'contrib_cris',
          memberId: 'member_cris',
          amount: const Money(10000),
          date: DateTime(2026, 10, 6),
        ),
      ];

      final summary = engine.computeSettlement(
        cycle: cycle,
        members: members,
        expenses: expenses,
        contributions: contributions,
        loans: loans,
        customContributionTargets: customTargets,
      );

      // Verificando Saldo Líquido do Kelvynn:
      // Aporte pago (0) - devido (500) = -500
      // Reembolso luz = +200
      // P2P para Cris = -100
      // Total Líquido Kelvynn = -500 + 200 - 100 = -400 (R$ -400,00)
      final kelvynnBalance = summary.memberBalances.firstWhere(
        (m) => m.memberId == 'member_kelvynn',
      );
      expect(kelvynnBalance.netBalance.cents, equals(-40000));
      expect(kelvynnBalance.isDebtor, isTrue);

      // Saldo Líquido do Cris:
      // Aporte pago (100) - devido (100) = 0
      // Reembolso luz = 0
      // P2P a receber = +100
      // Total Líquido Cris = +100 (R$ +100,00 a receber)
      final crisBalance = summary.memberBalances.firstWhere(
        (m) => m.memberId == 'member_cris',
      );
      expect(crisBalance.netBalance.cents, equals(10000));
      expect(crisBalance.isCreditor, isTrue);

      // Super Pix gerado:
      // O motor casa a dívida com o credor!
      expect(summary.transfers.isNotEmpty, isTrue);
      final transferToCris = summary.transfers.firstWhere(
        (t) => t.toMemberId == 'member_cris',
      );
      expect(transferToCris.fromMemberId, equals('member_kelvynn'));
      expect(transferToCris.amount.cents, equals(10000)); // R$ 100,00 para o Cris
    });

    test('Consistência Matemática: soma de saldos com divisões em centavos', () {
      final members = [
        const HouseMember(id: 'm1', name: 'Alice', defaultSplitPercent: 50),
        const HouseMember(id: 'm2', name: 'Bob', defaultSplitPercent: 50),
      ];

      final expenses = [
        HouseExpense(
          id: 'exp_1',
          title: 'Mercado',
          amount: const Money(15000), // 150,00
          date: DateTime(2026, 10, 10),
          paidByMemberId: 'm1',
          paidOutOfPocket: true,
          dueDate: DateTime(2026, 10, 10),
          categoryId: 'cat_mercado',
          paymentMethodId: 'pm_1',
          splitRule: const SplitRule.percentage({'m1': 50, 'm2': 50}),
        ),
      ];

      final summary = engine.computeSettlement(
        cycle: cycle,
        members: members,
        expenses: expenses,
        contributions: [],
        loans: [],
      );

      // M1 pagou 150 do bolso, mas deve 75 de aporte -> saldo líquido: +75
      // M2 não pagou nada, deve 75 de aporte -> saldo líquido: -75
      final m1 = summary.memberBalances.firstWhere((m) => m.memberId == 'm1');
      final m2 = summary.memberBalances.firstWhere((m) => m.memberId == 'm2');

      expect(m1.netBalance.cents, equals(7500));
      expect(m2.netBalance.cents, equals(-7500));
      expect(summary.isNetZeroSum, isTrue);

      // Super Pix: M2 transfere 75 para M1
      expect(summary.transfers.length, equals(1));
      expect(summary.transfers[0].fromMemberId, equals('m2'));
      expect(summary.transfers[0].toMemberId, equals('m1'));
      expect(summary.transfers[0].amount.cents, equals(7500));
    });
  });
}
