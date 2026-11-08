import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/domain/value_objects/financial_cycle.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/features/finance/data/datasources/house_expense_payload.dart';
import 'package:omni_lar/features/finance/data/datasources/mock_finance_datasource.dart';
import 'package:omni_lar/features/finance/data/offline/house_expense_offline_codec.dart';
import 'package:omni_lar/features/finance/domain/entities/house_expense.dart';
import 'package:omni_lar/features/finance/domain/entities/house_expense_item.dart';
import 'package:omni_lar/features/finance/domain/entities/payment_method.dart';
import 'package:omni_lar/features/finance/domain/entities/split_rule.dart';
import 'package:omni_lar/features/finance/domain/services/cycle_expense_filter.dart';
import 'package:omni_lar/features/finance/domain/services/expense_payment_split.dart';
import 'package:omni_lar/features/finance/domain/services/self_funded_expenses.dart';

/// Nota paga com mais de um meio (0124): R$ 150 com R$ 50 no VA e R$ 100 no
/// cartão vira uma despesa por meio, cada uma com a regra do próprio meio.
void main() {
  const va = PaymentMethod(
    id: 'pm_va',
    name: 'VA Kelvynn',
    type: PaymentMethodType.va,
    ownerMemberId: 'k',
    consumesContributions: false,
  );
  const card = PaymentMethod(
    id: 'pm_card',
    name: 'Cartão',
    type: PaymentMethodType.card,
    ownerMemberId: 'c',
    closingDay: 28,
    dueDay: 5,
  );
  const caixa = PaymentMethod(
    id: 'pm_caixa',
    name: 'Caixa',
    type: PaymentMethodType.account,
  );
  final methods = {
    for (final m in [va, card, caixa]) m.id: m,
  };

  HouseExpense note({
    int cents = 15000,
    SplitRule rule = const SplitRule.percentage({'k': 50, 'c': 50}),
    List<HouseExpenseItem> items = const [],
  }) => HouseExpense(
    id: 'nota',
    title: 'Mercado',
    amount: Money(cents),
    date: DateTime(2026, 11, 7, 12),
    categoryId: 'cat_mercado',
    paidByMemberId: 'k',
    paymentMethodId: 'pm_card',
    splitRule: rule,
    items: items,
    attachmentPath: 'casa/expenses/nota.jpg',
  );

  List<HouseExpense> split(HouseExpense n, List<PaymentPart> parts) =>
      ExpensePaymentSplit.build(
        note: n,
        parts: parts,
        methods: methods,
        groupId: 'grp',
        partId: (i) => 'parte_$i',
      );

  const vaCardParts = [
    PaymentPart(paymentMethodId: 'pm_card', amountCents: 10000),
    PaymentPart(paymentMethodId: 'pm_va', amountCents: 5000),
  ];

  group('validate', () {
    test('aceita partes que somam o valor da nota', () {
      expect(ExpensePaymentSplit.validate(15000, vaCardParts), isNull);
    });

    test('recusa soma diferente, meio repetido, valor zero e um meio só', () {
      expect(
        ExpensePaymentSplit.validate(15000, const [
          PaymentPart(paymentMethodId: 'pm_card', amountCents: 10000),
          PaymentPart(paymentMethodId: 'pm_va', amountCents: 4000),
        ]),
        contains('deve ser igual'),
      );
      expect(
        ExpensePaymentSplit.validate(15000, const [
          PaymentPart(paymentMethodId: 'pm_va', amountCents: 10000),
          PaymentPart(paymentMethodId: 'pm_va', amountCents: 5000),
        ]),
        contains('uma vez só'),
      );
      expect(
        ExpensePaymentSplit.validate(15000, const [
          PaymentPart(paymentMethodId: 'pm_card', amountCents: 15000),
          PaymentPart(paymentMethodId: 'pm_va', amountCents: 0),
        ]),
        contains('maior que zero'),
      );
      expect(
        ExpensePaymentSplit.validate(15000, const [
          PaymentPart(paymentMethodId: 'pm_card', amountCents: 15000),
        ]),
        contains('dois meios'),
      );
    });
  });

  group('build', () {
    test('VA + cartão: cada parte segue a regra do próprio meio', () {
      final parts = split(note(), vaCardParts);
      expect(parts, hasLength(2));
      final cardPart = parts[0];
      final vaPart = parts[1];

      expect(parts.map((p) => p.paymentGroupId).toSet(), {'grp'});
      expect(parts.fold<int>(0, (a, p) => a + p.amount.cents), 15000);

      // Cartão: espera a fatura (fecha dia 28, vence dia 5 do mês seguinte)
      expect(cardPart.amount.cents, 10000);
      expect(cardPart.isPending, isTrue);
      expect(cardPart.dueDate, DateTime(2026, 12, 5));
      expect(cardPart.paidOutOfPocket, isFalse);

      // VA: paga na hora, do bolso do dono, e fora dos aportes
      expect(vaPart.amount.cents, 5000);
      expect(vaPart.isPaid, isTrue);
      expect(vaPart.dueDate, isNull);
      expect(vaPart.paidOutOfPocket, isTrue);
      expect(vaPart.paidByMemberId, 'k');
      final selfFunded = SelfFundedExpenses.methodIds(methods.values);
      expect(SelfFundedExpenses.funded(parts, selfFunded).map((e) => e.id), [
        'parte_0',
      ]);

      // Comprovante só na primeira parte
      expect(cardPart.attachmentPath, 'casa/expenses/nota.jpg');
      expect(vaPart.attachmentPath, isNull);
    });

    test('cada parte cai no ciclo da própria competência', () {
      final parts = split(note(), vaCardParts);
      final november = FinancialCycle(
        start: DateTime(2026, 11, 5),
        end: DateTime(2026, 12, 4),
      );
      final december = FinancialCycle(
        start: DateTime(2026, 12, 5),
        end: DateTime(2027, 1, 4),
      );
      final now = DateTime(2026, 11, 7, 13);

      bool inCycle(HouseExpense e, FinancialCycle c) => expenseBelongsToCycle(
        e,
        c,
        isCardPayment: e.paymentMethodId == 'pm_card',
        now: now,
      );

      expect(
        inCycle(parts[1], november),
        isTrue,
        reason: 'VA conta no ciclo da compra',
      );
      expect(inCycle(parts[0], november), isFalse);
      expect(
        inCycle(parts[0], december),
        isTrue,
        reason: 'cartão conta no ciclo da fatura',
      );
    });

    test('rateio percentual vale igual em cada parte; o fixo é repartido', () {
      final percent = split(note(), vaCardParts);
      expect(percent.every((p) => p.splitRule.percentages!['k'] == 50), isTrue);

      final fixed = split(
        note(
          rule: SplitRule.fixed({
            'k': const Money(5000),
            'c': const Money(10000),
          }),
        ),
        vaCardParts,
      );
      expect(fixed[0].splitRule.fixedAmounts, {
        'k': const Money(5000),
        'c': const Money(5000),
      });
      expect(fixed[1].splitRule.fixedAmounts, {'c': const Money(5000)});
    });

    test(
      'sub-itens são repartidos sem perder centavo e mantêm o responsável',
      () {
        final parts = split(
          note(
            items: const [
              HouseExpenseItem(
                id: 'a',
                expenseId: 'nota',
                title: 'Comida',
                amount: Money(8000),
              ),
              HouseExpenseItem(
                id: 'b',
                expenseId: 'nota',
                title: 'Marmita Cris',
                amount: Money(7000),
                responsibleMemberId: 'c',
              ),
            ],
          ),
          vaCardParts,
        );
        expect(parts[0].items.map((i) => (i.title, i.amount.cents)), [
          ('Comida', 8000),
          ('Marmita Cris', 2000),
        ]);
        expect(parts[1].items.map((i) => (i.title, i.amount.cents)), [
          ('Marmita Cris', 5000),
        ]);
        expect(parts[1].items.single.responsibleMemberId, 'c');
        expect(parts.every((p) => p.isItemsBalanced), isTrue);
      },
    );

    test(
      'nota pendente: a parte que não é cartão fica pendente no vencimento',
      () {
        final parts = ExpensePaymentSplit.build(
          note: note(),
          parts: const [
            PaymentPart(paymentMethodId: 'pm_caixa', amountCents: 10000),
            PaymentPart(paymentMethodId: 'pm_card', amountCents: 5000),
          ],
          methods: methods,
          groupId: 'grp',
          partId: (i) => 'parte_$i',
          status: ExpenseStatus.pending,
          dueDate: DateTime(2026, 11, 20),
        );
        expect(parts[0].isPending, isTrue);
        expect(parts[0].dueDate, DateTime(2026, 11, 20));
        expect(parts[0].paidOutOfPocket, isFalse, reason: 'meio da casa');
        expect(parts[1].dueDate, DateTime(2026, 12, 5));
      },
    );
  });

  test(
    'merge refaz a nota a partir das partes (valor, itens e rateio fixo)',
    () {
      final original = note(
        rule: SplitRule.fixed({
          'k': const Money(5000),
          'c': const Money(10000),
        }),
        items: const [
          HouseExpenseItem(
            id: 'a',
            expenseId: 'nota',
            title: 'Comida',
            amount: Money(8000),
          ),
          HouseExpenseItem(
            id: 'b',
            expenseId: 'nota',
            title: 'Marmita Cris',
            amount: Money(7000),
            responsibleMemberId: 'c',
          ),
        ],
      );
      final parts = split(original, vaCardParts);
      final merged = ExpensePaymentSplit.merge(parts, mainId: 'parte_0');

      expect(merged.id, 'parte_0');
      expect(merged.amount.cents, 15000);
      expect(merged.paymentMethodId, 'pm_card');
      expect(merged.items.map((i) => (i.title, i.amount.cents)), [
        ('Comida', 8000),
        ('Marmita Cris', 7000),
      ]);
      expect(merged.splitRule.fixedAmounts, {
        'k': const Money(5000),
        'c': const Money(10000),
      });
      expect(
        merged.attachmentPath,
        'casa/expenses/nota.jpg',
        reason: 'o comprovante está só na primeira parte',
      );
    },
  );

  test('cut reparte como fita: linhas somam as partes e colunas as peças', () {
    final cuts = ExpensePaymentSplit.cut([1, 1, 1, 7], [3, 3, 4]);
    expect(cuts, [
      [1, 1, 1, 0],
      [0, 0, 0, 3],
      [0, 0, 0, 4],
    ]);
  });

  test('o grupo vai para o banco e para a fila offline', () {
    final part = split(
      note(),
      vaCardParts,
    ).first.copyWith(id: '11111111-1111-4111-8111-111111111111');
    final grouped = part.copyWith(
      paymentGroupId: '22222222-2222-4222-8222-222222222222',
      splitRule: const SplitRule.singleResponsible('k'),
    );
    expect(
      houseExpensePayload(
        grouped,
        houseId: 'h',
        currentUserId: null,
      )['payment_group_id'],
      '22222222-2222-4222-8222-222222222222',
    );
    expect(
      houseExpenseFromJson(houseExpenseToJson(grouped)).paymentGroupId,
      grouped.paymentGroupId,
    );
  });

  test('modo demo: excluir uma parte exclui a nota inteira', () async {
    final ds = MockFinanceDataSource();
    final cycle = FinancialCycle(
      start: DateTime(2026, 11, 5),
      end: DateTime(2026, 12, 4),
    );
    final before = (await ds.getExpensesForCycle(cycle)).length;

    final parts = ExpensePaymentSplit.build(
      note: note(),
      parts: const [
        PaymentPart(paymentMethodId: 'pm_caixa', amountCents: 10000),
        PaymentPart(paymentMethodId: 'pm_vr_marina', amountCents: 5000),
      ],
      methods: methods,
      groupId: 'grp_demo',
      partId: (i) => 'demo_$i',
    );
    await ds.addExpenseGroup(parts);
    final added = (await ds.getExpensesForCycle(
      cycle,
    )).where((e) => e.paymentGroupId == 'grp_demo');
    expect(added, hasLength(2));

    await ds.deleteExpense('demo_1');
    final after = await ds.getExpensesForCycle(cycle);
    expect(after.where((e) => e.paymentGroupId == 'grp_demo'), isEmpty);
    expect(after.length, before);
  });
}
