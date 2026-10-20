import 'package:omni_lar/features/finance/domain/entities/savings_vault.dart';
import 'package:omni_lar/features/projects/domain/entities/project_participant.dart';
import 'package:omni_lar/features/projects/domain/services/project_settlement_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/features/projects/data/repositories/mock_projects_repository.dart';
import 'package:omni_lar/features/projects/domain/entities/shared_project.dart';
import 'package:omni_lar/features/projects/presentation/cubit/projects_cubit.dart';
import 'package:omni_lar/features/projects/presentation/cubit/projects_state.dart';
import 'package:omni_lar/features/finance/domain/repositories/finance_repository.dart';
import 'package:omni_lar/features/finance/domain/entities/house_expense.dart';
import 'package:omni_lar/features/finance/domain/entities/split_rule.dart';
import 'package:omni_lar/features/finance/domain/entities/house_member.dart';

class _FakeFinanceRepo implements FinanceRepository {
  final List<HouseExpense> projectExpenses;
  _FakeFinanceRepo({this.projectExpenses = const []});

  @override
  Future<List<HouseExpense>> getExpensesForProject(String projectId) async =>
      projectExpenses.where((e) => e.projectId == projectId).toList();

  @override
  Future<List<SavingsVault>> getSavingsVaults() async => [
        SavingsVault(
          id: 'vault_viagem',
          name: 'Viagem de Ferias',
          currentBalance: const Money(150000),
          targetAmount: const Money(500000),
          createdAt: DateTime.now(),
        ),
      ];

  @override
  Future<List<HouseMember>> getMembers() async => [
        const HouseMember(id: 'member_carlos', name: 'Carlos Silva', defaultSplitPercent: 50.0),
        const HouseMember(id: 'member_marina', name: 'Marina Souza', defaultSplitPercent: 50.0),
      ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('ProjectsCubit - Gestão de Ciclo de Vida e Orçamento', () {
    late MockProjectsRepository mockRepo;
    late _FakeFinanceRepo fakeFinance;
    late ProjectsCubit cubit;

    setUp(() {
      mockRepo = MockProjectsRepository();
      fakeFinance = _FakeFinanceRepo();
      cubit = ProjectsCubit(
        projectsRepository: mockRepo,
        financeRepository: fakeFinance,
      );
    });

    test('loadProjects calcula totais gastos e expõe projectTotals', () async {
      await cubit.loadProjects();
      expect(cubit.state, isA<ProjectsLoaded>());
      final loaded = cubit.state as ProjectsLoaded;
      expect(loaded.projects.length, 2);
      expect(loaded.projectTotals, isNotNull);
    });

    test('createProjectForHouse suporta orçamento, datas e descrição', () async {
      await cubit.createProjectForHouse(
        title: 'Viagem Serra Gaúcha',
        type: ProjectType.trip,
        description: 'Vinho e passeios',
        targetBudget: const Money(300000), // R$ 3.000,00
        startDate: DateTime(2026, 11, 1),
        endDate: DateTime(2026, 11, 10),
        status: ProjectStatus.planning,
      );

      final state = cubit.state as ProjectsLoaded;
      final created = state.projects.firstWhere((p) => p.title == 'Viagem Serra Gaúcha');
      expect(created.targetBudget?.cents, 300000);
      expect(created.description, 'Vinho e passeios');
      expect(created.status, ProjectStatus.planning);
      expect(created.startDate, DateTime(2026, 11, 1));
      expect(created.endDate, DateTime(2026, 11, 10));
    });

    test('changeProjectStatus conclui e arquiva projetos corretamente', () async {
      await cubit.loadProjects();
      final state = cubit.state as ProjectsLoaded;
      final initialProject = state.projects.first;

      // Marca como concluído
      await cubit.changeProjectStatus(initialProject, ProjectStatus.settled);
      var updatedState = cubit.state as ProjectsLoaded;
      var updatedProject = updatedState.projects.firstWhere((p) => p.id == initialProject.id);
      expect(updatedProject.status, ProjectStatus.settled);

      // Arquiva
      await cubit.changeProjectStatus(updatedProject, ProjectStatus.archived);
      updatedState = cubit.state as ProjectsLoaded;
      updatedProject = updatedState.projects.firstWhere((p) => p.id == initialProject.id);
      expect(updatedProject.status, ProjectStatus.archived);
    });

    test('deleteProject remove o projeto do repositório e do estado', () async {
      await cubit.loadProjects();
      final state = cubit.state as ProjectsLoaded;
      final toDelete = state.projects.first;
      final initialCount = state.projects.length;

      await cubit.deleteProject(toDelete);
      final afterState = cubit.state as ProjectsLoaded;
      expect(afterState.projects.length, initialCount - 1);
      expect(afterState.projects.any((p) => p.id == toDelete.id), isFalse);
    });

    test('selectProject expõe despesas do projeto no selectedProjectExpenses', () async {
      final now = DateTime.now();
      final testExpense = HouseExpense(
        id: 'exp_1',
        title: 'Hotel',
        amount: const Money(80000),
        date: now,
        categoryId: 'cat_trip',
        paidByMemberId: 'member_carlos',
        paymentMethodId: 'pix',
        splitRule: const SplitRule.percentage(null),
        status: ExpenseStatus.paid,
        projectId: 'proj_trip_praia',
      );

      final financeRepo = _FakeFinanceRepo(projectExpenses: [testExpense]);
      final testCubit = ProjectsCubit(
        projectsRepository: mockRepo,
        financeRepository: financeRepo,
      );

      await testCubit.loadProjects();
      final state = testCubit.state as ProjectsLoaded;
      final floripa = state.projects.firstWhere((p) => p.id == 'proj_trip_praia');

      await testCubit.selectProject(floripa);
      final finalState = testCubit.state as ProjectsLoaded;
      expect(finalState.selectedProjectExpenses, isNotNull);
      expect(finalState.selectedProjectExpenses!.length, 1);
      expect(finalState.selectedProjectExpenses!.first.title, 'Hotel');
      expect(finalState.settlementSummary?.totalExpenses.cents, 80000);
    });

    test('Participante externo com chave Pix e WhatsApp recebe transferencias no Super Pix', () async {
      final now = DateTime.now();
      final guest = ProjectParticipant(
        id: 'part_guest_carlos',
        projectId: 'proj_trip_praia',
        externalName: 'Tio Carlos',
        pixKey: 'carlos@pix.com',
        phone: '5511988887777',
        defaultSplitPercent: 50.0,
        createdAt: now,
      );
      final member = ProjectParticipant(
        id: 'part_member_marina',
        projectId: 'proj_trip_praia',
        userId: 'member_marina',
        defaultSplitPercent: 50.0,
        createdAt: now,
      );

      final project = SharedProject(
        id: 'proj_trip_praia',
        houseId: 'house_1',
        title: 'Churrasco de Ferias',
        type: ProjectType.event,
        createdBy: 'user_1',
        participants: [guest, member],
        createdAt: now,
        updatedAt: now,
      );

      // Convidado Tio Carlos pagou a carne (R$ 200,00)
      final expense = HouseExpense(
        id: 'exp_picanha',
        title: 'Carne Churrasco',
        amount: const Money(20000), // R$ 200,00
        date: now,
        categoryId: 'cat_food',
        paidByMemberId: 'part_guest_carlos',
        paidByParticipantId: 'part_guest_carlos',
        paymentMethodId: 'pix',
        splitRule: const SplitRule.percentage(null), // 50/50
        status: ExpenseStatus.paid,
        projectId: 'proj_trip_praia',
      );

      const service = ProjectSettlementService();
      final summary = service.computeProjectSettlement(
        project: project,
        expenses: [expense],
        participants: [guest, member],
      );

      expect(summary.totalExpenses.cents, 20000);
      expect(summary.transfers.length, 1);
      final transfer = summary.transfers.first;
      // Marina deve transferir R$ 100,00 para Tio Carlos
      expect(transfer.toMemberName, 'Tio Carlos');
      expect(transfer.amount.cents, 10000);
      expect(transfer.pixKey, 'carlos@pix.com');
    });

    test('loadProjects e createProject vinculam Caixinha (SavingsVault) ao projeto', () async {
      await cubit.loadProjects();
      final loaded = cubit.state as ProjectsLoaded;
      expect(loaded.vaults.length, 1);
      expect(loaded.vaults.first.name, 'Viagem de Ferias');

      await cubit.createProjectForHouse(
        title: 'Fim de Ano em Ilhabela',
        type: ProjectType.trip,
        vaultId: 'vault_viagem',
        targetBudget: const Money(400000),
      );

      final state = cubit.state as ProjectsLoaded;
      final created = state.projects.firstWhere((p) => p.title == 'Fim de Ano em Ilhabela');
      expect(created.vaultId, 'vault_viagem');

      // Atualiza desvinculando a caixinha
      await cubit.updateProject(created.copyWith(clearVaultId: true));
      final afterUpdate = (cubit.state as ProjectsLoaded).projects.firstWhere((p) => p.id == created.id);
      expect(afterUpdate.vaultId, isNull);
    });
  });
}
