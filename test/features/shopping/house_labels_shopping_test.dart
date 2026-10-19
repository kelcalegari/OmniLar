import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/domain/value_objects/cycle_schedule.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/features/finance/domain/entities/category.dart';
import 'package:omni_lar/features/finance/domain/entities/house_member.dart';
import 'package:omni_lar/features/finance/domain/entities/house_settings.dart';
import 'package:omni_lar/features/finance/domain/entities/import_params.dart';
import 'package:omni_lar/features/finance/domain/entities/payment_method.dart';
import 'package:omni_lar/features/finance/domain/services/expense_launch_defaults.dart';
import 'package:omni_lar/features/p2p/domain/entities/p2p_installment.dart';
import 'package:omni_lar/features/p2p/domain/entities/p2p_loan.dart';
import 'package:omni_lar/features/reports/domain/entities/upcoming_forecast.dart';
import 'package:omni_lar/features/reports/domain/services/upcoming_cycles_builder.dart';
import 'package:omni_lar/features/shopping/domain/entities/shopping_list.dart';

void main() {
  group('Nome do Caixa e unidades de compra da casa', () {
    test('sem escolha valem o nome e as unidades de sempre', () {
      final settings = HouseSettings.fromJson(const {});
      expect(settings.cashLabel, isNull);
      expect(settings.cashName, 'Caixa da Casa');
      expect(settings.shoppingUnits, HouseSettings.defaultShoppingUnits);
      expect(settings.defaultUnit, 'un');
    });

    test('lê o nome e as unidades escolhidos', () {
      final settings = HouseSettings.fromJson(const {
        'cash_label': '  Cofre  ',
        'shopping_units': ['cx', 'kg'],
      });
      expect(settings.cashName, 'Cofre');
      expect(settings.shoppingUnits, ['cx', 'kg']);
      expect(settings.defaultUnit, 'cx');
    });

    test('valores inválidos voltam ao padrão', () {
      final settings = HouseSettings.fromJson({
        'cash_label': 'x' * 31,
        'shopping_units': ['kg', 'KG'],
      });
      expect(settings.cashLabel, isNull);
      expect(settings.shoppingUnits, HouseSettings.defaultShoppingUnits);
      expect(HouseSettings.fromJson(const {'shopping_units': []}).shoppingUnits, HouseSettings.defaultShoppingUnits);
      expect(HouseSettings.fromJson(const {'shopping_units': [1, 'kg']}).shoppingUnits, HouseSettings.defaultShoppingUnits);
    });

    test('regras de validação', () {
      expect(HouseSettings.isValidCashLabel('Caixa'), isTrue);
      expect(HouseSettings.isValidCashLabel('   '), isFalse);
      expect(HouseSettings.areValidShoppingUnits(['un']), isTrue);
      expect(HouseSettings.areValidShoppingUnits(const []), isFalse);
      expect(HouseSettings.areValidShoppingUnits(['un', 'UN']), isFalse);
      expect(HouseSettings.areValidShoppingUnits(['123456789']), isFalse);
      expect(HouseSettings.areValidShoppingUnits(['un ']), isFalse);
      expect(HouseSettings.areValidShoppingUnits([for (var i = 0; i < 21; i++) 'u$i']), isFalse);
    });

    test('copyWith troca e limpa o nome do Caixa', () {
      final named = const HouseSettings().copyWith(cashLabel: 'Cofre');
      expect(named.cashName, 'Cofre');
      expect(named.copyWith(clearCashLabel: true).cashName, 'Caixa da Casa');
    });

    test('as colunas novas só entram na leitura mais recente', () {
      expect(HouseSettings.columns, contains('cash_label'));
      expect(HouseSettings.columns, contains('shopping_units'));
      expect(HouseSettings.columnsBefore0101, isNot(contains('cash_label')));
      expect(HouseSettings.columnsBefore0101, contains('import_defaults'));
    });

    test('a previsão dos próximos ciclos mostra o nome escolhido para o Caixa', () {
      const members = [
        HouseMember(id: 'm_ana', name: 'Ana', role: 'owner', defaultSplitPercent: 50),
        HouseMember(id: 'm_bia', name: 'Bia', role: 'member', defaultSplitPercent: 50),
      ];
      final loan = P2PLoan(
        id: 'l1',
        title: 'Reforma',
        totalAmount: const Money(10000),
        lenderMemberId: P2PLoan.houseLenderId,
        borrowerMemberId: 'm_bia',
        installmentsCount: 2,
        createdAt: DateTime(2026, 10, 1),
        firstDueDate: DateTime(2026, 11, 15),
        installments: [
          for (var n = 1; n <= 2; n++)
            P2PInstallment(
              id: 'l1-$n',
              loanId: 'l1',
              number: n,
              totalCount: 2,
              amount: const Money(5000),
              dueDate: DateTime(2026, 10 + n, 15),
            ),
        ],
      );
      UpcomingForecast build([String? label]) => label == null
          ? const UpcomingCyclesBuilder().build(
              schedule: const CycleSchedule(10),
              expensesByCycle: const {},
              loans: [loan],
              members: members,
              paymentMethods: const [PaymentMethod(id: 'pm', name: 'Conta', type: PaymentMethodType.account)],
              today: DateTime(2026, 10, 20),
            )
          : const UpcomingCyclesBuilder().build(
              schedule: const CycleSchedule(10),
              expensesByCycle: const {},
              loans: [loan],
              members: members,
              paymentMethods: const [PaymentMethod(id: 'pm', name: 'Conta', type: PaymentMethodType.account)],
              today: DateTime(2026, 10, 20),
              cashLabel: label,
            );

      expect(build().payoffs.single.lenderName, 'Caixa da Casa');
      expect(build('Cofre').payoffs.single.lenderName, 'Cofre');
    });
  });

  group('Padrões da lista de compras', () {
    const members = [
      HouseMember(id: 'a', name: 'Ana', defaultSplitPercent: 70),
      HouseMember(id: 'b', name: 'Bia', defaultSplitPercent: 30),
    ];
    const mercado = ExpenseCategory(id: 'cat_mercado', name: 'Mercado', icon: 'cart', colorHex: '#10B981');
    const casa = ExpenseCategory(id: 'cat_casa', name: 'Casa', icon: 'home', colorHex: '#000000');
    const dona = ExpenseCategory(
        id: 'cat_bia', name: 'Da Bia', icon: 'x', colorHex: '#000000', ownerMemberId: 'b');

    test('lista nova usa a categoria de mercado e a divisão de sempre', () {
      const list = ShoppingList(id: 'l', name: 'Feira');
      expect(list.defaultCategoryId, isNull);
      expect(list.defaultSplitMode, ImportSplitMode.category);
      final chosen = ExpenseLaunchDefaults.matchCategory(
        const [casa, mercado],
        preferred: list.defaultCategoryId,
        nameKeywords: const ['mercado'],
      );
      expect(chosen, mercado);
    });

    test('categoria escolhida vence; se foi apagada, volta à de mercado', () {
      expect(
        ExpenseLaunchDefaults.matchCategory(const [casa, mercado],
            preferred: 'cat_casa', nameKeywords: const ['mercado']),
        casa,
      );
      expect(
        ExpenseLaunchDefaults.matchCategory(const [casa, mercado],
            preferred: '11111111-1111-4111-8111-111111111111', nameKeywords: const ['mercado']),
        mercado,
      );
    });

    test('divisão da lista: da categoria, partes iguais ou só quem paga', () {
      Map<String, double> shares(ImportSplitMode mode, [dynamic category = mercado]) {
        final rule = ExpenseLaunchDefaults.splitRuleForMode(
          mode: mode,
          category: category as ExpenseCategory?,
          members: members,
          paidByMemberId: 'b',
        );
        final single = rule.singleResponsibleMemberId;
        if (single != null) return {single: 100.0};
        return {for (final e in rule.percentages!.entries) e.key: e.value};
      }

      expect(shares(ImportSplitMode.category), {'a': 70, 'b': 30});
      expect(shares(ImportSplitMode.equal), {'a': 50, 'b': 50});
      expect(shares(ImportSplitMode.payer), {'b': 100});
      // Categoria com dono segue 100% do dono em qualquer modo
      expect(shares(ImportSplitMode.equal, dona), {'b': 100});
    });

    test('copyWith guarda e limpa os padrões da lista', () {
      const list = ShoppingList(id: 'l', name: 'Feira');
      final set = list.copyWith(defaultCategoryId: 'cat_casa', defaultSplitMode: ImportSplitMode.equal);
      expect(set.defaultCategoryId, 'cat_casa');
      expect(set.defaultSplitMode, ImportSplitMode.equal);
      expect(set.copyWith(clearDefaultCategory: true).defaultCategoryId, isNull);
      expect(set, isNot(list));
    });
  });
}
