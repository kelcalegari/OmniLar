import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/features/finance/domain/entities/house_expense.dart';
import 'package:omni_lar/features/finance/domain/entities/savings_vault.dart';
import 'package:omni_lar/features/finance/domain/entities/split_rule.dart';
import 'package:omni_lar/features/projects/domain/entities/project_participant.dart';
import 'package:omni_lar/features/projects/domain/entities/shared_project.dart';
import 'package:omni_lar/features/projects/domain/services/project_report_export.dart';
import 'package:omni_lar/features/projects/domain/services/project_settlement_service.dart';

void main() {
  group('ProjectReportExport - PDF e CSV do Projeto', () {
    final now = DateTime(2026, 10, 20);
    final p1 = ProjectParticipant(
      id: 'part_carlos',
      projectId: 'proj_eurotrip',
      userId: 'user_carlos',
      externalName: 'Carlos',
      defaultSplitPercent: 50.0,
      createdAt: now,
    );
    final p2 = ProjectParticipant(
      id: 'part_marina',
      projectId: 'proj_eurotrip',
      userId: 'user_marina',
      externalName: 'Marina',
      pixKey: 'marina@pix.com',
      phone: '5511999998888',
      defaultSplitPercent: 50.0,
      createdAt: now,
    );

    final project = SharedProject(
      id: 'proj_eurotrip',
      houseId: 'house_1',
      title: 'EuroTrip 2026 ✈️',
      description: 'Paris e Roma com amigos',
      type: ProjectType.trip,
      targetBudget: const Money(1500000), // R$ 15.000,00
      vaultId: 'vault_viagem',
      participants: [p1, p2],
      createdBy: 'user_carlos',
      createdAt: now,
      updatedAt: now,
    );

    final vault = SavingsVault(
      id: 'vault_viagem',
      name: 'Reserva EuroTrip',
      currentBalance: const Money(500000), // R$ 5.000,00
      targetAmount: const Money(1000000),
      createdAt: now,
    );

    final expenses = [
      HouseExpense(
        id: 'exp_hotel_paris',
        title: 'Hotel Paris',
        amount: const Money(280000), // R$ 2.800,00
        date: now,
        categoryId: 'cat_trip',
        paidByMemberId: 'part_carlos',
        paymentMethodId: 'card',
        splitRule: const SplitRule.percentage(null),
        status: ExpenseStatus.paid,
        projectId: 'proj_eurotrip',
        notes: '[Câmbio: EUR 450.00 @ R\$ 6.22]',
      ),
      HouseExpense(
        id: 'exp_coliseu',
        title: 'Ingressos Coliseu',
        amount: const Money(62000), // R$ 620,00
        date: now,
        categoryId: 'cat_trip',
        paidByMemberId: 'part_marina',
        paymentMethodId: 'pix',
        splitRule: const SplitRule.percentage(null),
        status: ExpenseStatus.paid,
        projectId: 'proj_eurotrip',
        notes: '[Câmbio: EUR 100.00 @ R\$ 6.20]',
      ),
    ];

    const settlementService = ProjectSettlementService();
    final summary = settlementService.computeProjectSettlement(
      project: project,
      expenses: expenses,
      participants: [p1, p2],
    );

    const exporter = ProjectReportExport();

    test('buildPdf gera bytes de PDF válidos com todas as seções', () async {
      final pdfBytes = await exporter.buildPdf(
        project: project,
        summary: summary,
        expenses: expenses,
        linkedVault: vault,
        resolvePayerName: (id) => id == 'part_carlos' ? 'Carlos' : 'Marina',
      );

      expect(pdfBytes, isNotNull);
      expect(pdfBytes.length, greaterThan(1000));
      // Começa com a assinatura mágica de PDF '%PDF'
      final header = String.fromCharCodes(pdfBytes.sublist(0, 4));
      expect(header, '%PDF');
    });

    test('buildCsv gera planilha com formatação UTF-8 BOM e ponto e vírgula', () {
      final csv = exporter.buildCsv(
        project: project,
        summary: summary,
        expenses: expenses,
        linkedVault: vault,
        resolvePayerName: (id) => id == 'part_carlos' ? 'Carlos' : 'Marina',
      );

      expect(csv.startsWith('\uFEFF'), isTrue);
      expect(csv.contains('PROJETO;EuroTrip 2026 ✈️'), isTrue);
      expect(csv.contains('CAIXINHA VINCULADA;Reserva EuroTrip'), isTrue);
      expect(csv.contains('--- BALANÇO POR PARTICIPANTE ---'), isTrue);
      expect(csv.contains('--- TRANSFERÊNCIAS MÍNIMAS (SUPER PIX) ---'), isTrue);
      expect(csv.contains('--- DESPESAS DO PROJETO ---'), isTrue);
      expect(csv.contains('Hotel Paris;Carlos;2800.00;[Câmbio: EUR 450.00 @ R\$ 6.22]'), isTrue);
    });

    test('fileNamePdf e fileNameCsv sanitizam caracteres especiais', () {
      expect(ProjectReportExport.fileNamePdf(project), 'omnilar_projeto_eurotrip_2026__relatorio.pdf');
      expect(ProjectReportExport.fileNameCsv(project), 'omnilar_projeto_eurotrip_2026__planilha.csv');
    });
  });
}
