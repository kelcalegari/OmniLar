import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/domain/value_objects/cycle_schedule.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/features/finance/domain/entities/category.dart';
import 'package:omni_lar/features/finance/domain/entities/house_member.dart';
import 'package:omni_lar/features/finance/domain/entities/payment_method.dart';
import 'package:omni_lar/features/p2p/domain/entities/p2p_loan.dart';
import 'package:omni_lar/features/reconciliation/domain/entities/imported_statement_line.dart';
import 'package:omni_lar/features/reconciliation/domain/repositories/import_repository.dart';
import 'package:omni_lar/features/reconciliation/domain/services/import_session.dart';

const _members = [
  HouseMember(id: 'kelvynn', name: 'Kelvynn Calegari', defaultSplitPercent: 60),
  HouseMember(id: 'cristiano', name: 'Cristiano', defaultSplitPercent: 40),
];

const _categories = [
  ExpenseCategory(id: 'cat_mercado', name: 'Mercado', icon: 'cart', colorHex: '#10B981'),
];

ImportedStatementLine _line(String id, String description, int cents) => ImportedStatementLine(
      id: id,
      date: DateTime(2026, 10, 2),
      description: description,
      amount: Money(cents),
      kind: StatementLineKind.purchase,
      destination: LineDestination.house,
    );

PaymentMethod _card({String? owner}) => PaymentMethod(
      id: 'pm_mp',
      name: 'Crédito Mercado Pago',
      type: PaymentMethodType.card,
      ownerMemberId: owner,
      closingDay: 9,
      dueDay: 14,
    );

void main() {
  const schedule = CycleSchedule(1);
  var ids = 0;
  String newId() => 'id_${ids++}';

  ImportSession start(PaymentMethod card) => ImportSession.start(
        source: card,
        fileName: 'fatura.pdf',
        lines: [_line('a', 'CesarAugusto', 60961), _line('b', 'Padaria', 19188), _line('c', 'Posto', 4032)],
        payerMemberId: 'kelvynn',
      ).withInvoiceDueDate(DateTime(2026, 10, 14));

  ImportedStatementLine owes(ImportSession session, String lineId, String member) => session.lines
      .firstWhere((l) => l.id == lineId)
      .copyWith(destination: LineDestination.splitP2P, assignedMemberId: member);

  ImportPlan plan(ImportSession session) => session.buildPlan(
        members: _members,
        categories: _categories,
        schedule: schedule,
        now: DateTime(2026, 10, 17),
        newId: newId,
      );

  group('cartão da Casa (sem dono)', () {
    test('cada morador, inclusive quem importa, deve para o Caixa', () {
      var session = start(_card());
      expect(session.isHouseCard, isTrue);
      session = session
          .withLine(owes(session, 'a', 'cristiano'))
          .withLine(owes(session, 'b', 'kelvynn'))
          .withLine(owes(session, 'c', 'kelvynn'));
      expect(session.blockers, isEmpty);

      final loans = plan(session).loans;
      expect(loans, hasLength(2));
      expect(loans.every((loan) => loan.isHouseLender), isTrue);
      final byBorrower = {for (final loan in loans) loan.borrowerMemberId: loan};
      expect(byBorrower['cristiano']!.totalAmount.cents, 60961);
      expect(byBorrower['kelvynn']!.totalAmount.cents, 19188 + 4032);
    });

    test('gasto pessoal não existe: bloqueia até dizer quem deve', () {
      var session = start(_card());
      session = session.withLine(
        session.lines.first.copyWith(destination: LineDestination.cardOwnerPersonal),
      );
      expect(session.blockers.single, contains('Cartão da Casa'));
    });

    test('regra antiga de pessoal vira Casa; trocar quem paga não apaga devedor', () {
      var session = start(_card()).withRules(
        const [
          ImportRule(matchKey: 'padaria', merchantName: 'Padaria', destination: LineDestination.cardOwnerPersonal),
        ],
        memberIds: {'kelvynn', 'cristiano'},
        categoryIds: {'cat_mercado'},
      );
      expect(session.lines.firstWhere((l) => l.id == 'b').destination, LineDestination.house);

      session = session.withLine(owes(session, 'a', 'kelvynn')).withPayer('kelvynn');
      expect(session.lines.firstWhere((l) => l.id == 'a').assignedMemberId, 'kelvynn');
    });
  });

  group('cartão de um morador', () {
    test('compra de outro morador vira dívida com o dono do cartão', () {
      var session = start(_card(owner: 'kelvynn'));
      expect(session.isHouseCard, isFalse);
      session = session
          .withLine(owes(session, 'a', 'cristiano'))
          .withLine(session.lines[1].copyWith(destination: LineDestination.cardOwnerPersonal));
      expect(session.blockers, isEmpty);

      final loan = plan(session).loans.single;
      expect(loan.isHouseLender, isFalse);
      expect(loan.lenderMemberId, 'kelvynn');
      expect(loan.borrowerMemberId, 'cristiano');
      expect(loan.lenderMemberId, isNot(P2PLoan.houseLenderId));
    });

    test('o dono não pode dever para si mesmo', () {
      var session = start(_card(owner: 'kelvynn'));
      session = session.withLine(owes(session, 'a', 'kelvynn'));
      expect(session.blockers, contains('Escolha quem deve em cada linha marcada como empréstimo.'));
    });
  });
}
