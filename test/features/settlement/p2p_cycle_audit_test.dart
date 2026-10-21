import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/domain/value_objects/financial_cycle.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/features/finance/domain/entities/contribution.dart';
import 'package:omni_lar/features/finance/domain/entities/house_member.dart';
import 'package:omni_lar/features/p2p/domain/entities/p2p_installment.dart';
import 'package:omni_lar/features/p2p/domain/entities/p2p_loan.dart';
import 'package:omni_lar/features/settlement/data/settlement_summary_codec.dart';
import 'package:omni_lar/features/settlement/domain/services/global_clearing_engine.dart';

void main() {
  group('P2P Payments In Cycle Audit ("Transferi 2.000 mas mostra 1.000")', () {
    const engine = GlobalClearingEngine();
    final cycle = FinancialCycle(
      start: DateTime(2026, 10, 5),
      end: DateTime(2026, 11, 4),
    );

    const kelvyn = HouseMember(id: 'member_kelvyn', name: 'Kelvyn', role: 'owner');
    const cris = HouseMember(id: 'member_cris', name: 'Cris', role: 'member');

    test('audit trail tracks loan payments made in the cycle alongside contributions', () {
      // Kelvyn fez aporte regular de R$ 1.000 no ciclo
      final contributions = [
        Contribution(
          id: 'cb_1',
          memberId: 'member_kelvyn',
          amount: const Money(100000), // R$ 1.000,00
          date: DateTime(2026, 10, 10),
        ),
      ];

      // Kelvyn também pagou uma parcela de R$ 1.000 de um empréstimo com a Casa no ciclo
      final loanWithHouse = P2PLoan(
        id: 'loan_house_1',
        title: 'Empréstimo Caixa da Casa',
        totalAmount: const Money(100000),
        lenderMemberId: P2PLoan.houseLenderId,
        borrowerMemberId: 'member_kelvyn',
        installmentsCount: 1,
        createdAt: DateTime(2026, 10, 1),
        firstDueDate: DateTime(2026, 10, 15),
        status: LoanStatus.active,
        installments: [
          P2PInstallment(
            id: 'inst_h_1',
            loanId: 'loan_house_1',
            number: 1,
            totalCount: 1,
            dueDate: DateTime(2026, 10, 15),
            amount: const Money(100000),
            paidAmount: const Money(100000), // R$ 1.000,00 pago
            paidAt: DateTime(2026, 10, 12),
          ),
        ],
      );

      final summary = engine.computeSettlement(
        cycle: cycle,
        members: [kelvyn, cris],
        expenses: const [],
        contributions: contributions,
        loans: [loanWithHouse],
      );

      final kelvynAudit = summary.auditTrails['member_kelvyn']!;

      // Aporte do ciclo: R$ 1.000
      expect(kelvynAudit.contributionPaid.cents, 100000);

      // Empréstimo amortizado/pago no ciclo: R$ 1.000
      expect(kelvynAudit.p2pPaidInCycle.length, 1);
      expect(kelvynAudit.p2pPaidInCycle.first.description, 'Empréstimo Caixa da Casa');
      expect(kelvynAudit.p2pPaidInCycle.first.otherMemberName, 'Caixa da Casa');
      expect(kelvynAudit.p2pPaidInCycle.first.amount.cents, 100000);
      expect(kelvynAudit.p2pPaidInCycleTotal.cents, 100000);

      // Total desembolsado no ciclo (Aporte + Empréstimos): R$ 2.000
      expect(kelvynAudit.totalDisbursedInCycle.cents, 200000);
    });

    test('audit trail tracks P2P payment received in cycle for lender member', () {
      // Cris emprestou para Kelvyn, e Kelvyn pagou Cris durante o ciclo
      final loanBetweenMembers = P2PLoan(
        id: 'loan_p2p_1',
        title: 'Notebook',
        totalAmount: const Money(50000),
        lenderMemberId: 'member_cris',
        borrowerMemberId: 'member_kelvyn',
        installmentsCount: 1,
        createdAt: DateTime(2026, 10, 1),
        firstDueDate: DateTime(2026, 10, 20),
        status: LoanStatus.active,
        installments: [
          P2PInstallment(
            id: 'inst_p2p_1',
            loanId: 'loan_p2p_1',
            number: 1,
            totalCount: 1,
            dueDate: DateTime(2026, 10, 20),
            amount: const Money(50000),
            paidAmount: const Money(50000),
            paidAt: DateTime(2026, 10, 18),
          ),
        ],
      );

      final summary = engine.computeSettlement(
        cycle: cycle,
        members: [kelvyn, cris],
        expenses: const [],
        contributions: const [],
        loans: [loanBetweenMembers],
      );

      final kelvynAudit = summary.auditTrails['member_kelvyn']!;
      expect(kelvynAudit.p2pPaidInCycle.length, 1);
      expect(kelvynAudit.p2pPaidInCycle.first.otherMemberName, 'Cris');

      final crisAudit = summary.auditTrails['member_cris']!;
      expect(crisAudit.p2pReceivedInCycle.length, 1);
      expect(crisAudit.p2pReceivedInCycle.first.description, 'Notebook');
      expect(crisAudit.p2pReceivedInCycle.first.otherMemberName, 'Kelvyn');
      expect(crisAudit.p2pReceivedInCycle.first.amount.cents, 50000);
      expect(crisAudit.p2pReceivedInCycleTotal.cents, 50000);
    });

    test('SettlementSummaryCodec preserves p2pPaidInCycle and p2pReceivedInCycle across JSON serialization', () {
      final loan = P2PLoan(
        id: 'loan_codec_test',
        title: 'Reforma',
        totalAmount: const Money(60000),
        lenderMemberId: 'member_cris',
        borrowerMemberId: 'member_kelvyn',
        installmentsCount: 2,
        createdAt: DateTime(2026, 10, 1),
        firstDueDate: DateTime(2026, 10, 15),
        status: LoanStatus.active,
        installments: [
          P2PInstallment(
            id: 'inst_c_1',
            loanId: 'loan_codec_test',
            number: 1,
            totalCount: 2,
            dueDate: DateTime(2026, 10, 15),
            amount: const Money(30000),
            paidAmount: const Money(30000),
            paidAt: DateTime(2026, 10, 14),
          ),
          P2PInstallment(
            id: 'inst_c_2',
            loanId: 'loan_codec_test',
            number: 2,
            totalCount: 2,
            dueDate: DateTime(2026, 11, 15),
            amount: const Money(30000),
          ),
        ],
      );

      final summary = engine.computeSettlement(
        cycle: cycle,
        members: [kelvyn, cris],
        expenses: const [],
        contributions: const [],
        loans: [loan],
      );

      final json = settlementSummaryToJson(summary);
      final restored = settlementSummaryFromJson(json, cycle: cycle);

      expect(restored, isNotNull);
      final restoredKelvynAudit = restored!.auditTrails['member_kelvyn']!;
      expect(restoredKelvynAudit.p2pPaidInCycle.length, 1);
      expect(restoredKelvynAudit.p2pPaidInCycle.first.description, 'Reforma');
      expect(restoredKelvynAudit.p2pPaidInCycle.first.amount.cents, 30000);
      expect(restoredKelvynAudit.p2pPaidInCycle.first.installmentNumber, 1);
      expect(restoredKelvynAudit.p2pPaidInCycle.first.totalInstallments, 2);

      final restoredCrisAudit = restored.auditTrails['member_cris']!;
      expect(restoredCrisAudit.p2pReceivedInCycle.length, 1);
      expect(restoredCrisAudit.p2pReceivedInCycle.first.description, 'Reforma');
      expect(restoredCrisAudit.p2pReceivedInCycle.first.amount.cents, 30000);
    });
  });
}
