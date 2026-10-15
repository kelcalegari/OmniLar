import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/features/finance/data/datasources/mock_finance_datasource.dart';
import 'package:omni_lar/features/finance/data/repositories/finance_repository_impl.dart';
import 'package:omni_lar/features/finance/domain/entities/category.dart';
import 'package:omni_lar/features/finance/domain/entities/house_expense.dart';
import 'package:omni_lar/features/finance/domain/entities/house_member.dart';
import 'package:omni_lar/features/finance/domain/entities/payment_method.dart';
import 'package:omni_lar/features/finance/domain/entities/split_rule.dart';
import 'package:omni_lar/features/finance/domain/services/expense_launch_defaults.dart';
import 'package:omni_lar/features/finance/presentation/pages/add_expense_page.dart';
import 'package:omni_lar/features/projects/data/repositories/mock_projects_repository.dart';
import 'package:omni_lar/features/projects/domain/entities/shared_project.dart';
import 'package:omni_lar/features/projects/presentation/cubit/projects_cubit.dart';
import 'package:omni_lar/features/projects/presentation/cubit/projects_state.dart';

void main() {
  const members = [
    HouseMember(id: 'm1', name: 'Ana Souza', defaultSplitPercent: 60),
    HouseMember(id: 'm2', name: 'Bia Lima', defaultSplitPercent: 40),
  ];
  const categories = [
    ExpenseCategory(id: 'c-casa', name: 'Moradia & Aluguel', icon: 'home', colorHex: '#000000'),
    ExpenseCategory(id: 'c-mercado', name: 'Supermercado', icon: 'cart', colorHex: '#000000'),
    ExpenseCategory(id: 'c-contas', name: 'Contas (Luz, Água, Internet)', icon: 'bolt', colorHex: '#000000'),
    ExpenseCategory(
      id: 'c-carro',
      name: 'Transporte & Carro',
      icon: 'car',
      colorHex: '#000000',
      ownerMemberId: 'm2',
    ),
  ];

  group('ExpenseLaunchDefaults', () {
    test('pago do bolso só quando a forma de pagamento tem dono', () {
      const personalCard = PaymentMethod(
        id: 'pm-card',
        name: 'Cartão da Ana',
        type: PaymentMethodType.card,
        ownerMemberId: 'm1',
      );
      const housePix = PaymentMethod(id: 'pm-pix', name: 'Pix', type: PaymentMethodType.pix);
      const houseCash = PaymentMethod(
        id: 'pm_caixa',
        name: 'Caixa da Casa',
        type: PaymentMethodType.account,
        ownerMemberId: 'm1',
      );

      expect(ExpenseLaunchDefaults.paidOutOfPocket(personalCard), isTrue);
      expect(ExpenseLaunchDefaults.paidOutOfPocket(housePix), isFalse);
      expect(ExpenseLaunchDefaults.paidOutOfPocket(houseCash), isFalse);
      expect(ExpenseLaunchDefaults.paidOutOfPocket(null), isFalse);
    });

    test('categoria: id indicado, depois nome indicado, depois palavra-chave, depois a primeira', () {
      expect(
        ExpenseLaunchDefaults.matchCategory(categories, preferred: 'c-contas')?.id,
        'c-contas',
      );
      expect(
        ExpenseLaunchDefaults.matchCategory(categories, preferred: 'carro')?.id,
        'c-carro',
      );
      // Id de demonstração que não existe na casa: cai na palavra-chave
      expect(
        ExpenseLaunchDefaults.matchCategory(
          categories,
          preferred: 'cat_groceries',
          nameKeywords: const ['mercado'],
        )?.id,
        'c-mercado',
      );
      expect(ExpenseLaunchDefaults.matchCategory(categories)?.id, 'c-casa');
      expect(ExpenseLaunchDefaults.matchCategory(const []), isNull);
    });

    test('rateio: categoria com dono vai 100% para o dono; as demais, percentual padrão', () {
      final owned = ExpenseLaunchDefaults.splitRule(
        category: categories.last,
        members: members,
        paidByMemberId: 'm1',
      );
      expect(owned.type, SplitType.categoryOwner);
      expect(owned, SplitRule.singleResponsible('m2'));

      final shared = ExpenseLaunchDefaults.splitRule(
        category: categories.first,
        members: members,
        paidByMemberId: 'm1',
      );
      expect(shared, const SplitRule.percentage({'m1': 60.0, 'm2': 40.0}));
    });
  });

  group('Data editável de uma despesa', () {
    final purchase = DateTime(2026, 10, 3);
    final invoiceDue = DateTime(2026, 11, 10);
    HouseExpense expense({DateTime? dueDate}) => HouseExpense(
          id: 'e1',
          title: 'Compra',
          amount: const Money(10000),
          date: purchase,
          dueDate: dueDate,
          categoryId: 'c-mercado',
          paymentMethodId: 'pm-card',
          paidByMemberId: 'm1',
          splitRule: const SplitRule.percentage({'m1': 60.0, 'm2': 40.0}),
        );

    test('compra no cartão abre na data da compra, não no vencimento da fatura', () {
      const card = PaymentMethod(
        id: 'pm-card',
        name: 'Cartão',
        type: PaymentMethodType.card,
        closingDay: 3,
        dueDay: 10,
      );
      expect(editableDateOfExpense(expense(dueDate: invoiceDue), card), purchase);
    });

    test('conta fora do cartão abre no vencimento', () {
      const pix = PaymentMethod(id: 'pm-pix', name: 'Pix', type: PaymentMethodType.pix);
      expect(editableDateOfExpense(expense(dueDate: invoiceDue), pix), invoiceDue);
      expect(editableDateOfExpense(expense(), pix), purchase);
      expect(editableDateOfExpense(expense(dueDate: invoiceDue), null), invoiceDue);
    });
  });

  group('Rateio ao editar uma despesa', () {
    final old = HouseExpense(
      id: 'e1',
      title: 'Aluguel',
      amount: const Money(100000),
      date: DateTime(2026, 9, 10),
      categoryId: 'c-casa',
      paymentMethodId: 'pm-pix',
      paidByMemberId: 'm1',
      splitRule: const SplitRule.percentage({'m1': 50.0, 'm2': 50.0}),
    );
    const currentDefault = SplitRule.percentage({'m1': 60.0, 'm2': 40.0});

    test('mantém o rateio do lançamento quando a categoria não muda', () {
      expect(splitRuleForEdit(old, 'c-casa', currentDefault), old.splitRule);
    });

    test('refaz pelo padrão quando a categoria muda', () {
      expect(splitRuleForEdit(old, 'c-mercado', currentDefault), currentDefault);
    });

    test('refaz quando a despesa entra ou sai de um projeto', () {
      const projectRule = SplitRule.percentage(null);
      // Entrou num projeto: deixa o rateio da casa
      expect(
        splitRuleForEdit(old, 'c-casa', projectRule, newProjectId: 'p1'),
        projectRule,
      );
      // Saiu do projeto: volta ao rateio da casa
      final inProject = old.copyWith(projectId: 'p1', splitRule: projectRule);
      expect(splitRuleForEdit(inProject, 'c-casa', currentDefault), currentDefault);
      // Continua no mesmo projeto: mantém
      expect(
        splitRuleForEdit(inProject, 'c-casa', currentDefault, newProjectId: 'p1'),
        projectRule,
      );
    });
  });

  group('Projetos compartilhados', () {
    test('projeto novo usa a casa e o usuário da sessão e inclui os moradores', () async {
      final projects = MockProjectsRepository();
      final cubit = ProjectsCubit(
        projectsRepository: projects,
        financeRepository: FinanceRepositoryImpl(MockFinanceDataSource()),
        currentHouseId: () => 'house-real',
        currentUserId: () => 'user-real',
      );

      await cubit.createProjectForHouse(title: 'Viagem', type: ProjectType.trip);

      final created = (await projects.getProjects(houseId: 'house-real'))
          .firstWhere((p) => p.title == 'Viagem');
      expect(created.houseId, 'house-real');
      expect(created.createdBy, 'user-real');
      expect(created.participants.length, greaterThan(1));
      expect(created.participants.every((p) => p.userId != 'user_1'), isTrue);
      expect(cubit.state, isA<ProjectsLoaded>());
    });

    test('sem sessão (modo demo) continua usando os ids de demonstração', () async {
      final projects = MockProjectsRepository();
      final cubit = ProjectsCubit(
        projectsRepository: projects,
        financeRepository: FinanceRepositoryImpl(MockFinanceDataSource()),
      );

      await cubit.createProjectForHouse(title: 'Reforma', type: ProjectType.generic);

      final created = (await projects.getProjects(houseId: 'house_demo'))
          .firstWhere((p) => p.title == 'Reforma');
      expect(created.houseId, ProjectsCubit.demoHouseId);
      expect(created.createdBy, ProjectsCubit.demoUserId);
    });
  });
}
