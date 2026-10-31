import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/domain/value_objects/cycle_schedule.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/core/utils/uuid.dart';
import 'package:omni_lar/features/finance/data/datasources/house_expense_payload.dart';
import 'package:omni_lar/features/finance/data/datasources/house_expense_row.dart';
import 'package:omni_lar/features/finance/data/offline/house_expense_offline_codec.dart';
import 'package:omni_lar/features/finance/domain/entities/category.dart';
import 'package:omni_lar/features/finance/domain/entities/house_expense.dart';
import 'package:omni_lar/features/finance/domain/entities/house_member.dart';
import 'package:omni_lar/features/finance/domain/entities/payment_method.dart';
import 'package:omni_lar/features/finance/domain/entities/split_rule.dart';
import 'package:omni_lar/features/finance/domain/services/expense_search.dart';
import 'package:omni_lar/features/reconciliation/domain/entities/imported_statement_line.dart';
import 'package:omni_lar/features/reconciliation/domain/services/import_draft_codec.dart';
import 'package:omni_lar/features/reconciliation/domain/services/import_session.dart';
import 'package:omni_lar/features/reconciliation/domain/services/installment_purchase.dart';

const _members = [
  HouseMember(id: 'kelvynn', name: 'Kelvynn Calegari', defaultSplitPercent: 60),
  HouseMember(id: 'cristiano', name: 'Cristiano', defaultSplitPercent: 40),
];

const _categories = [
  ExpenseCategory(id: 'cat_casa', name: 'Casa', icon: 'home', colorHex: '#10B981'),
];

const _card = PaymentMethod(
  id: 'pm_magalu',
  name: 'Cartão Magalu',
  type: PaymentMethodType.card,
  closingDay: 9,
  dueDay: 14,
);

HouseExpense _expense({String? description}) => HouseExpense(
      id: 'e1',
      title: 'Mercado',
      description: description,
      amount: const Money(10000),
      date: DateTime(2026, 10, 13),
      categoryId: 'cat_casa',
      paidByMemberId: 'kelvynn',
      paymentMethodId: 'pm_caixa',
      splitRule: const SplitRule.percentage(null),
      notes: 'Importado de Nubank: PAO DE ACUCAR',
    );

void main() {
  group('Descrição do gasto', () {
    test('vai para o banco, volta dele e passa pelo cache offline, separada das notas', () {
      final expense = _expense(description: 'Compra do mês com os itens da festa');
      final payload = houseExpensePayload(expense, houseId: 'h', currentUserId: 'kelvynn');
      expect(payload['description'], 'Compra do mês com os itens da festa');
      expect(payload['notes'], 'Importado de Nubank: PAO DE ACUCAR');

      final row = houseExpenseFromRow({
        'id': 'e1',
        'title': 'Mercado',
        'description': 'Compra do mês',
        'amount_cents': 10000,
        'date': '2026-10-13T12:00:00Z',
        'paid_by_id': 'kelvynn',
        'split_type': 'percentage',
        'status': 'paid',
      });
      expect(row.description, 'Compra do mês');

      expect(houseExpenseFromJson(houseExpenseToJson(expense)).description, expense.description);
      expect(houseExpensePayload(_expense(), houseId: 'h', currentUserId: 'kelvynn').containsKey('description'), isFalse);
    });

    test('editar pode trocar ou apagar a descrição', () {
      final expense = _expense(description: 'antes');
      expect(expense.copyWith(title: 'Feira').description, 'antes');
      expect(expense.copyWith(description: 'depois').description, 'depois');
      expect(expense.copyWith(clearDescription: true).description, isNull);
    });

    test('a busca encontra o gasto pela descrição', () {
      final expense = _expense(description: 'Itens da festa junina');
      expect(expenseMatchesSearch(expense, 'festa'), isTrue);
      expect(expenseMatchesSearch(_expense(), 'festa'), isFalse);
    });

    test('compra parcelada leva a descrição a cada parcela e ao empréstimo do morador', () {
      InstallmentPurchase build({String? debtor}) => InstallmentPurchase.build(
            title: 'Geladeira',
            description: '  Frost free, para a cozinha  ',
            total: const Money(30000),
            count: 3,
            purchaseDate: DateTime(2026, 10, 5),
            card: _card,
            categoryId: 'cat_casa',
            paidByMemberId: 'kelvynn',
            splitRule: const SplitRule.percentage(null),
            debtorMemberId: debtor,
            now: DateTime(2026, 10, 5),
          );

      final house = build();
      expect(house.expenses.map((e) => e.description).toSet(), {'Frost free, para a cozinha'});
      expect(house.expenses.first.notes, contains('lançada à mão'));

      final loans = build(debtor: 'cristiano').loans;
      expect(loans.first.description, 'Parcela 1 de 3 no Cartão Magalu\nFrost free, para a cozinha');
    });
  });

  group('Descrição na revisão da importação', () {
    final line = ImportedStatementLine(
      id: 'mercado',
      date: DateTime(2026, 10, 2),
      description: 'PAO DE ACUCAR',
      amount: const Money(48560),
      signature: '2026-10-02|48560|pao de acucar#1',
      categoryId: 'cat_casa',
    );

    test('a descrição dada na linha vira a descrição do gasto lançado', () {
      final session = ImportSession.start(
        source: _card,
        fileName: 'fatura.csv',
        lines: [line.copyWith(title: 'Mercado', note: 'Churrasco de sábado')],
        payerMemberId: 'kelvynn',
      ).withInvoiceDueDate(DateTime(2026, 10, 14)).withExpenses(const []);
      final plan = session.buildPlan(
        members: _members,
        categories: _categories,
        schedule: const CycleSchedule(1),
        now: DateTime(2026, 10, 3),
        newId: generateUuidV4,
      );
      final expense = plan.newExpenses.single;
      expect(expense.title, 'Mercado');
      expect(expense.description, 'Churrasco de sábado');
      expect(expense.notes, 'Importado de Cartão Magalu: PAO DE ACUCAR');
    });

    test('a descrição fica no rascunho e pode ser apagada', () {
      final withNote = line.copyWith(note: 'Churrasco');
      expect(ImportDraftCodec.lineFromJson(ImportDraftCodec.lineToJson(withNote)).note, 'Churrasco');
      expect(withNote.copyWith(clearNote: true).note, isNull);
      expect(withNote.copyWith(title: 'Mercado').note, 'Churrasco');
    });
  });
}
