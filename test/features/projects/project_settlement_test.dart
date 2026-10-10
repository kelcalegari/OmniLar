import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/features/finance/domain/entities/house_expense.dart';
import 'package:omni_lar/features/finance/domain/entities/split_rule.dart';
import 'package:omni_lar/features/projects/domain/entities/project_participant.dart';
import 'package:omni_lar/features/projects/domain/entities/shared_project.dart';
import 'package:omni_lar/features/projects/domain/services/project_settlement_service.dart';

void main() {
  group('ProjectSettlementService - Rateio de Viagens e Projetos', () {
    const service = ProjectSettlementService();

    final now = DateTime.now();
    final project = SharedProject(
      id: 'proj_trip_1',
      houseId: 'house_1',
      title: 'Viagem Florianópolis',
      type: ProjectType.trip,
      targetBudget: const Money(400000), // R$ 4.000,00
      status: ProjectStatus.active,
      createdBy: 'user_ana',
      createdAt: now,
      updatedAt: now,
    );

    final participantAna = ProjectParticipant(
      id: 'part_ana',
      projectId: 'proj_trip_1',
      userId: 'user_ana',
      externalName: 'Ana',
      createdAt: now,
    );

    final participantBeto = ProjectParticipant(
      id: 'part_beto',
      projectId: 'proj_trip_1',
      userId: 'user_beto',
      externalName: 'Beto',
      createdAt: now,
    );

    final participantCaio = ProjectParticipant(
      id: 'part_caio',
      projectId: 'proj_trip_1',
      userId: null, // Convidado externo
      externalName: 'Caio (Amigo)',
      createdAt: now,
    );

    final participants = [participantAna, participantBeto, participantCaio];

    test('Rateio igualitário de despesas na viagem entre 3 participantes', () {
      // Ana pagou R$ 900,00 de hospedagem dividida em 3 partes iguais (R$ 300 cada)
      final expenseHospedagem = HouseExpense(
        id: 'exp_1',
        title: 'Pousada',
        amount: const Money(90000),
        date: now,
        categoryId: 'cat_hospedagem',
        paidByMemberId: 'part_ana',
        paymentMethodId: 'pix',
        splitRule: const SplitRule.percentage(null), // divisão igualitária
        projectId: 'proj_trip_1',
      );

      // Beto pagou R$ 300,00 de combustível dividido em 3 partes iguais (R$ 100 cada)
      final expenseCombustivel = HouseExpense(
        id: 'exp_2',
        title: 'Gasolina',
        amount: const Money(30000),
        date: now,
        categoryId: 'cat_transporte',
        paidByMemberId: 'part_beto',
        paymentMethodId: 'pix',
        splitRule: const SplitRule.percentage(null),
        projectId: 'proj_trip_1',
      );

      final summary = service.computeProjectSettlement(
        project: project,
        expenses: [expenseHospedagem, expenseCombustivel],
        participants: participants,
      );

      // Total de despesas: R$ 1.200,00
      expect(summary.totalExpenses.cents, equals(120000));

      // Cada um deve R$ 400,00
      // Ana pagou 900 -> saldo líquido: +500
      // Beto pagou 300 -> saldo líquido: -100
      // Caio pagou 0 -> saldo líquido: -400
      final balAna = summary.participantBalances.firstWhere((b) => b.participantId == 'part_ana');
      final balBeto = summary.participantBalances.firstWhere((b) => b.participantId == 'part_beto');
      final balCaio = summary.participantBalances.firstWhere((b) => b.participantId == 'part_caio');

      expect(balAna.netBalance.cents, equals(50000));
      expect(balBeto.netBalance.cents, equals(-10000));
      expect(balCaio.netBalance.cents, equals(-40000));

      // Transferências mínimas geradas (Super Pix do Projeto):
      // Caio paga 400 para Ana
      // Beto paga 100 para Ana
      expect(summary.transfers.length, equals(2));
      expect(summary.transfers[0].fromMemberName, equals('Caio (Amigo)'));
      expect(summary.transfers[0].toMemberName, equals('Ana'));
      expect(summary.transfers[0].amount.cents, equals(40000));

      expect(summary.transfers[1].fromMemberName, equals('Beto'));
      expect(summary.transfers[1].toMemberName, equals('Ana'));
      expect(summary.transfers[1].amount.cents, equals(10000));
    });

    test('Progresso e estouro de orçamento no SharedProject', () {
      expect(project.budgetProgressPercent(const Money(200000)), equals(0.5));
      expect(project.isOverBudget(const Money(400000)), isFalse);
      expect(project.isOverBudget(const Money(450000)), isTrue);
    });

    test('Resolução de pagador por userId e SplitRule percentual por userId', () {
      // Ana pagou R$ 100,00 identificada por seu userId ('user_ana')
      // Rateio definido por userId: Ana 60% e Beto 40%
      final expense = HouseExpense(
        id: 'exp_percent',
        title: 'Jantar',
        amount: const Money(10000), // R$ 100,00
        date: now,
        categoryId: 'cat_lazer',
        paidByMemberId: 'user_ana', // Usando userId em vez de participantId
        paymentMethodId: 'cartao',
        splitRule: const SplitRule.percentage({'user_ana': 60.0, 'user_beto': 40.0}),
        projectId: 'proj_trip_1',
      );

      final summary = service.computeProjectSettlement(
        project: project,
        expenses: [expense],
        participants: [participantAna, participantBeto],
      );

      final balAna = summary.participantBalances.firstWhere((b) => b.participantId == 'part_ana');
      final balBeto = summary.participantBalances.firstWhere((b) => b.participantId == 'part_beto');

      // Ana: pagou 100, deve 60 -> saldo +40
      // Beto: pagou 0, deve 40 -> saldo -40
      expect(balAna.netBalance.cents, equals(4000));
      expect(balBeto.netBalance.cents, equals(-4000));

      expect(summary.transfers.length, equals(1));
      expect(summary.transfers.first.fromMemberName, equals('Beto'));
      expect(summary.transfers.first.toMemberName, equals('Ana'));
      expect(summary.transfers.first.amount.cents, equals(4000));
    });

    test('Rateio respeita defaultSplitPercent dos participantes quando a regra não define', () {
      final p1 = ProjectParticipant(
        id: 'p1',
        projectId: 'p',
        userId: 'u1',
        externalName: 'P1',
        defaultSplitPercent: 70.0,
        createdAt: now,
      );
      final p2 = ProjectParticipant(
        id: 'p2',
        projectId: 'p',
        userId: 'u2',
        externalName: 'P2',
        defaultSplitPercent: 30.0,
        createdAt: now,
      );

      final expense = HouseExpense(
        id: 'exp_default_split',
        title: 'Passeio',
        amount: const Money(20000), // R$ 200,00
        date: now,
        categoryId: 'cat_lazer',
        paidByMemberId: 'u1',
        paymentMethodId: 'pix',
        splitRule: const SplitRule.percentage(null),
        projectId: 'p',
      );

      final summary = service.computeProjectSettlement(
        project: project,
        expenses: [expense],
        participants: [p1, p2],
      );

      final bal1 = summary.participantBalances.firstWhere((b) => b.participantId == 'p1');
      final bal2 = summary.participantBalances.firstWhere((b) => b.participantId == 'p2');

      // P1: pagou 200, deve 140 (70%) -> saldo +60
      // P2: pagou 0, deve 60 (30%) -> saldo -60
      expect(bal1.netBalance.cents, equals(6000));
      expect(bal2.netBalance.cents, equals(-6000));
    });
  });
}
