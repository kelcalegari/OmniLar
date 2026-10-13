import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/features/finance/data/datasources/house_expense_payload.dart';
import 'package:omni_lar/features/finance/domain/entities/house_expense.dart';
import 'package:omni_lar/features/finance/domain/entities/house_expense_item.dart';
import 'package:omni_lar/features/finance/domain/entities/split_rule.dart';
import 'package:omni_lar/features/p2p/data/datasources/p2p_loan_payload.dart';
import 'package:omni_lar/features/p2p/domain/entities/p2p_loan.dart';

void main() {
  const house = '11111111-1111-4111-8111-111111111111';
  const ana = '22222222-2222-4222-8222-222222222222';
  const bia = '33333333-3333-4333-8333-333333333333';
  const caio = '44444444-4444-4444-8444-444444444444';
  const category = '55555555-5555-4555-8555-555555555555';

  group('Dados enviados para as gravações em uma transação', () {
    test('despesa leva o rateio somando o valor e os sub-itens junto', () {
      final payload = houseExpensePayload(
        HouseExpense(
          id: 'exp_local_1',
          title: 'Mercado',
          amount: const Money(10000),
          date: DateTime(2026, 10, 13, 15),
          categoryId: category,
          paidByMemberId: ana,
          paymentMethodId: 'pm_caixa',
          splitRule: const SplitRule.percentage({ana: 33.33, bia: 33.33, caio: 33.34}),
          items: const [
            HouseExpenseItem(
              id: 'item_local',
              expenseId: 'exp_local_1',
              title: 'Chocolate',
              amount: Money(1200),
              responsibleMemberId: bia,
              splitRule: SplitRule.singleResponsible(bia),
            ),
          ],
        ),
        houseId: house,
        currentUserId: ana,
      );

      // Ids que não são uuid ficam de fora: o banco gera
      expect(payload.containsKey('id'), isFalse);
      expect(payload.containsKey('payment_method_id'), isFalse);
      expect(payload['category_id'], category);
      expect(payload['house_id'], house);
      expect(payload['status'], 'paid');
      expect(payload['due_date'], '2026-10-13');

      final rules = payload['split_rules'] as List;
      expect(rules.length, 3);
      expect(
        rules.fold<int>(0, (acc, r) => acc + ((r as Map)['calculated_cents'] as int)),
        10000,
      );

      final items = payload['items'] as List;
      expect(items.single['title'], 'Chocolate');
      expect(items.single['responsible_member_id'], bia);
      expect(items.single['split_type'], 'category_owner');
    });

    test('compra no cartão usa o vencimento informado', () {
      final payload = houseExpensePayload(
        HouseExpense(
          id: 'x',
          title: 'Compra',
          amount: const Money(5000),
          date: DateTime(2026, 10, 13),
          categoryId: category,
          paidByMemberId: ana,
          paymentMethodId: category,
          splitRule: const SplitRule.singleResponsible(ana),
        ),
        houseId: house,
        currentUserId: ana,
        dueDate: DateTime(2026, 11, 5),
      );
      expect(payload['due_date'], '2026-11-05');
      expect((payload['split_rules'] as List).single['calculated_cents'], 5000);
    });

    test('empréstimo sem parcelas ganha as parcelas, somando o total', () {
      final payload = p2pLoanPayload(
        P2PLoan(
          id: 'loan_local',
          title: 'Item pessoal',
          totalAmount: const Money(10000),
          lenderMemberId: ana,
          borrowerMemberId: bia,
          installmentsCount: 3,
          createdAt: DateTime(2026, 10, 13),
          firstDueDate: DateTime(2026, 11, 10),
        ),
        houseId: house,
      );

      expect(payload['lender_id'], ana);
      expect(payload['lender_is_house'], isFalse);
      final installments = payload['installments'] as List;
      expect(installments.length, 3);
      expect(
        installments.fold<int>(0, (acc, i) => acc + ((i as Map)['amount_cents'] as int)),
        10000,
      );
      expect(installments.first['due_date'], '2026-11-10');
      expect(installments.every((i) => (i as Map)['status'] == 'pending'), isTrue);
    });

    test('acordo com o Lar vai sem credor', () {
      final payload = p2pLoanPayload(
        P2PLoan(
          id: 'loan_house',
          title: 'Pendência',
          totalAmount: const Money(3000),
          lenderMemberId: P2PLoan.houseLenderId,
          borrowerMemberId: bia,
          installmentsCount: 1,
          createdAt: DateTime(2026, 10, 13),
          firstDueDate: DateTime(2026, 11, 10),
        ),
        houseId: house,
      );
      expect(payload.containsKey('lender_id'), isFalse);
      expect(payload['lender_is_house'], isTrue);
    });
  });
}
