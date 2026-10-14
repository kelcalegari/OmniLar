import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/domain/value_objects/cycle_schedule.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/features/finance/domain/entities/category.dart';
import 'package:omni_lar/features/finance/domain/entities/house_expense.dart';
import 'package:omni_lar/features/finance/domain/entities/house_member.dart';
import 'package:omni_lar/features/finance/domain/entities/payment_method.dart';
import 'package:omni_lar/features/finance/domain/entities/split_rule.dart';
import 'package:omni_lar/features/reconciliation/data/supabase_import_repository.dart';
import 'package:omni_lar/features/reconciliation/domain/entities/imported_statement_line.dart';
import 'package:omni_lar/features/finance/domain/entities/card_invoice.dart';
import 'package:omni_lar/features/p2p/domain/entities/p2p_installment.dart';
import 'package:omni_lar/features/p2p/domain/entities/p2p_loan.dart';
import 'package:omni_lar/features/reconciliation/domain/repositories/import_repository.dart';
import 'package:omni_lar/features/reconciliation/domain/services/import_session.dart';
import 'package:omni_lar/features/reconciliation/domain/services/statement_extras.dart';
import 'package:omni_lar/features/reconciliation/domain/services/statement_matcher.dart';
import 'package:omni_lar/features/reconciliation/domain/services/statement_parser.dart';
import 'package:omni_lar/features/reconciliation/domain/services/statement_text.dart';

const _nubank = PaymentMethod(
  id: 'pm_nubank',
  name: 'Nubank',
  type: PaymentMethodType.card,
  ownerMemberId: 'kelvynn',
  closingDay: 28,
  dueDay: 10,
);

const _account = PaymentMethod(
  id: 'pm_conta',
  name: 'Conta Itaú',
  type: PaymentMethodType.account,
  ownerMemberId: 'kelvynn',
);

const _members = [
  HouseMember(id: 'kelvynn', name: 'Kelvynn Calegari', defaultSplitPercent: 60),
  HouseMember(id: 'cristiano', name: 'Cristiano', defaultSplitPercent: 40),
];

const _categories = [
  ExpenseCategory(id: 'cat_mercado', name: 'Mercado', icon: 'cart', colorHex: '#10B981'),
  ExpenseCategory(id: 'cat_contas', name: 'Contas', icon: 'bolt', colorHex: '#F59E0B'),
];

ImportedStatementLine _line(
  String id,
  DateTime date,
  String description,
  int cents, {
  StatementLineKind kind = StatementLineKind.purchase,
}) =>
    ImportedStatementLine(
      id: id,
      date: date,
      description: description,
      amount: Money(cents),
      kind: kind,
      signature: '${StatementParser.signatureContent(date, cents, description)}#1',
      destination: kind == StatementLineKind.purchase ? LineDestination.house : LineDestination.ignored,
    );

HouseExpense _expense(
  String id,
  String title,
  int cents,
  DateTime date, {
  String paymentMethodId = 'pm_nubank',
  ExpenseStatus status = ExpenseStatus.paid,
  DateTime? settledAt,
  SplitRule splitRule = const SplitRule.percentage({'kelvynn': 60, 'cristiano': 40}),
}) =>
    HouseExpense(
      id: id,
      title: title,
      amount: Money(cents),
      date: date,
      categoryId: 'cat_mercado',
      paidByMemberId: 'kelvynn',
      paymentMethodId: paymentMethodId,
      splitRule: splitRule,
      status: status,
      settledAt: settledAt,
    );

void main() {
  group('Leitura de valores e datas', () {
    test('valor aceita os formatos brasileiro e internacional, com sinal', () {
      expect(StatementParser.parseSignedCents('1.234,56'), 123456);
      expect(StatementParser.parseSignedCents('1234.56'), 123456);
      expect(StatementParser.parseSignedCents('1,234.56'), 123456);
      expect(StatementParser.parseSignedCents('R\$ 10,00'), 1000);
      expect(StatementParser.parseSignedCents('-320.50'), -32050);
      expect(StatementParser.parseSignedCents('10,00-'), -1000);
      expect(StatementParser.parseSignedCents('(45,90)'), -4590);
      expect(StatementParser.parseSignedCents('1.234'), 123400);
      expect(StatementParser.parseSignedCents('12,5'), 1250);
      expect(StatementParser.parseSignedCents('500'), 50000);
      expect(StatementParser.parseSignedCents('Mercado'), isNull);
      expect(StatementParser.parseSignedCents('05/10/2026'), isNull);
    });

    test('data aceita ISO, dia/mês/ano e dia/mês sem ano', () {
      final now = DateTime(2026, 10, 13);
      expect(StatementParser.parseDate('2026-10-05'), DateTime(2026, 10, 5));
      expect(StatementParser.parseDate('05/10/2026'), DateTime(2026, 10, 5));
      expect(StatementParser.parseDate('05/10/26'), DateTime(2026, 10, 5));
      expect(StatementParser.parseDate('05/10', now: now), DateTime(2026, 10, 5));
      // Dezembro visto em outubro só pode ser do ano passado
      expect(StatementParser.parseDate('20/12', now: now), DateTime(2025, 12, 20));
      expect(StatementParser.parseDate('31/02/2026'), isNull);
      expect(StatementParser.parseDate('Mercado'), isNull);
    });

    test('arquivo em Latin-1 mantém os acentos', () {
      final bytes = latin1.encode('05/10/2026;Pão de Açúcar;10,00');
      expect(StatementParser.decodeBytes(bytes), contains('Pão de Açúcar'));
      expect(StatementParser.decodeBytes(utf8.encode('Pão')), 'Pão');
    });
  });

  group('CSV', () {
    test('lê separador ponto e vírgula com data e valor brasileiros', () {
      const csv = '''
Data;Histórico;Valor
05/10/2026;PAO DE ACUCAR LJ 1234;1.485,60
07/10/2026;FARM RIO;320,00
''';
      final lines = StatementParser.parseCsv(csv);

      expect(lines, hasLength(2));
      expect(lines[0].date, DateTime(2026, 10, 5));
      expect(lines[0].description, 'PAO DE ACUCAR LJ 1234');
      expect(lines[0].amount.cents, 148560);
      expect(lines[1].amount.cents, 32000);
    });

    test('lê valor com vírgula decimal mesmo quando a vírgula separa as colunas', () {
      final lines = StatementParser.parseCsv('05/10/2026,Mercado,485,60\n06/10/2026,Padaria,12,00');

      expect(lines, hasLength(2));
      expect(lines[0].amount.cents, 48560);
      expect(lines[0].description, 'Mercado');
      expect(lines[1].amount.cents, 1200);
    });

    test('na fatura, o sinal da minoria é pagamento ou estorno, e não compra', () {
      const csv = '''
date,title,amount
2026-10-01,Pagamento recebido,-1200.00
2026-10-03,Enel Energia,210.00
2026-10-05,Restaurante Sabor,154.00
2026-10-06,Estorno Loja X,-50.00
''';
      final lines = StatementParser.parseCsv(csv);

      expect(lines.map((l) => l.kind), [
        StatementLineKind.payment,
        StatementLineKind.purchase,
        StatementLineKind.purchase,
        StatementLineKind.refund,
      ]);
      // Sempre positivo, e só compra entra como lançamento
      expect(lines[0].amount.cents, 120000);
      expect(lines[0].destination, LineDestination.ignored);
      expect(lines[3].destination, LineDestination.ignored);
      expect(lines[1].destination, LineDestination.house);
    });

    test('linhas iguais no mesmo arquivo ganham assinaturas diferentes, estáveis entre leituras', () {
      const csv = '2026-10-05,PADARIA,25.00\n2026-10-05,PADARIA,25.00\n2026-10-06,PADARIA,25.00';
      final first = StatementParser.parseCsv(csv).map((l) => l.signature).toList();
      final second = StatementParser.parseCsv(csv).map((l) => l.signature).toList();

      expect(first, ['2026-10-05|2500|padaria#1', '2026-10-05|2500|padaria#2', '2026-10-06|2500|padaria#1']);
      expect(second, first);
    });

    test('reconhece a parcela no fim da descrição', () {
      final lines = StatementParser.parseCsv('2026-10-02,MAGALU 03/10,99.90\n2026-10-03,POSTO 24/7,80.00');

      expect(lines[0].installmentNumber, 3);
      expect(lines[0].installmentsTotal, 10);
      expect(lines[1].isInstallment, isFalse);
    });
  });

  group('OFX', () {
    const cardOfx = '''
<OFX><CREDITCARDMSGSRSV1><CCSTMTTRNRS><CCSTMTRS><BANKTRANLIST>
<STMTTRN><TRNTYPE>DEBIT<DTPOSTED>20261003<TRNAMT>-210.00<FITID>abc1<MEMO>ENEL ENERGIA</STMTTRN>
<STMTTRN><TRNTYPE>DEBIT<DTPOSTED>20261005<TRNAMT>-154.00<FITID>abc2<MEMO>RESTAURANTE SABOR</STMTTRN>
<STMTTRN><TRNTYPE>CREDIT<DTPOSTED>20261001<TRNAMT>1200.00<FITID>abc3<MEMO>Pagamento recebido</STMTTRN>
</BANKTRANLIST></CCSTMTRS></CCSTMTTRNRS></CREDITCARDMSGSRSV1></OFX>
''';

    test('fatura de cartão: compras negativas e pagamento positivo', () {
      expect(StatementParser.isCreditCardOfx(cardOfx), isTrue);

      final lines = StatementParser.parseFile(cardOfx, filename: 'fatura.ofx');
      expect(lines, hasLength(3));
      expect(lines[0].kind, StatementLineKind.purchase);
      expect(lines[0].amount.cents, 21000);
      expect(lines[0].externalId, 'abc1');
      expect(lines[2].kind, StatementLineKind.payment);
    });

    test('extrato de conta: saída é compra, entrada e pagamento de fatura ficam de fora', () {
      const bankOfx = '''
<OFX><BANKMSGSRSV1><STMTTRNRS><STMTRS><BANKTRANLIST>
<STMTTRN><DTPOSTED>20261003<TRNAMT>-89.90<MEMO>PIX ENVIADO PADARIA</STMTTRN>
<STMTTRN><DTPOSTED>20261004<TRNAMT>200.00<MEMO>PIX RECEBIDO CRISTIANO</STMTTRN>
<STMTTRN><DTPOSTED>20261009<TRNAMT>-1482.40<MEMO>PAGTO FATURA NUBANK</STMTTRN>
</BANKTRANLIST></STMTRS></STMTTRNRS></BANKMSGSRSV1></OFX>
''';
      expect(StatementParser.isCreditCardOfx(bankOfx), isFalse);

      final lines = StatementParser.parseFile(bankOfx, filename: 'extrato.ofx');
      expect(lines.map((l) => l.kind), [
        StatementLineKind.purchase,
        StatementLineKind.income,
        StatementLineKind.payment,
      ]);
      expect(lines.where((l) => l.destination == LineDestination.house), hasLength(1));
    });
  });

  group('Texto das descrições', () {
    test('nome limpo tira número da loja, parcela e caixa alta', () {
      expect(StatementText.cleanTitle('PAO DE ACUCAR LJ 1234'), 'Pao de Acucar');
      expect(StatementText.cleanTitle('MAGALU 03/10'), 'Magalu');
      expect(StatementText.cleanTitle('PAG*JoseDaSilva'), 'JoseDaSilva');
      expect(StatementText.cleanTitle('Feira do bairro'), 'Feira do bairro');
    });

    test('semelhança compara as palavras que identificam o lugar', () {
      expect(StatementText.similarity('RESTAURANTE SABOR SP', 'Jantar no Sabor'), greaterThan(0.3));
      expect(StatementText.similarity('SUPERMERCADO EXTRA', 'Mercado'), 1);
      expect(StatementText.similarity('PAO DE ACUCAR', 'Farmácia'), 0);
    });
  });

  group('Detecção do que já foi lançado', () {
    // O exemplo do plano: fatura Nubank com vencimento em 10/11
    final lines = [
      _line('mercado', DateTime(2026, 10, 12), 'PAO DE ACUCAR LJ 1234', 48560),
      _line('farmacia', DateTime(2026, 10, 9), 'DROGASIL 0456', 6290),
      _line('jantar', DateTime(2026, 10, 5), 'RESTAURANTE SABOR', 15400),
      _line('farm', DateTime(2026, 10, 7), 'FARM RIO', 32000),
      _line('pagamento', DateTime(2026, 10, 1), 'PAGAMENTO RECEBIDO', 120000, kind: StatementLineKind.payment),
    ];
    final expenses = [
      _expense('e_mercado', 'Mercado', 48560, DateTime(2026, 10, 11)),
      _expense('e_farmacia', 'Farmácia', 6290, DateTime(2026, 10, 8), paymentMethodId: 'pm_caixa'),
      _expense('e_jantar', 'Jantar no Sabor', 14000, DateTime(2026, 10, 5)),
    ];

    test('classifica cada linha: já lançada, provável, valor diferente ou nova', () {
      final matches = StatementMatcher.match(lines: lines, expenses: expenses, paymentMethodId: 'pm_nubank');

      expect(matches['mercado']!.kind, LineMatchKind.alreadyLaunched);
      expect(matches['mercado']!.expense.id, 'e_mercado');
      expect(matches['farmacia']!.kind, LineMatchKind.probable);
      expect(matches['jantar']!.kind, LineMatchKind.amountDiffers);
      expect(matches.containsKey('farm'), isFalse);
      // Pagamento não é comparado com despesa
      expect(matches.containsKey('pagamento'), isFalse);
    });

    test('duas compras iguais no mesmo dia casam com despesas diferentes', () {
      final twins = [
        _line('a', DateTime(2026, 10, 5), 'PADARIA', 2500),
        _line('b', DateTime(2026, 10, 5), 'PADARIA', 2500),
        _line('c', DateTime(2026, 10, 5), 'PADARIA', 2500),
      ];
      final launched = [
        _expense('e1', 'Padaria', 2500, DateTime(2026, 10, 5)),
        _expense('e2', 'Padaria', 2500, DateTime(2026, 10, 5)),
      ];
      final matches = StatementMatcher.match(lines: twins, expenses: launched, paymentMethodId: 'pm_nubank');

      expect(matches, hasLength(2));
      expect(matches.values.map((m) => m.expense.id).toSet(), {'e1', 'e2'});
    });

    test('mesmo valor longe da data, ou valor diferente em outro lugar, não casa', () {
      final matches = StatementMatcher.match(
        lines: [
          _line('longe', DateTime(2026, 10, 20), 'MERCADO', 48560),
          _line('outro', DateTime(2026, 10, 5), 'POSTO IPIRANGA', 15000),
        ],
        expenses: expenses,
        paymentMethodId: 'pm_nubank',
      );
      expect(matches, isEmpty);
    });

    test('conta pendente de mesmo valor é só provável: quem decide é o usuário', () {
      final matches = StatementMatcher.match(
        lines: [_line('netflix', DateTime(2026, 10, 10), 'NETFLIX.COM', 5590)],
        expenses: [
          _expense('e_netflix', 'Netflix', 5590, DateTime(2026, 10, 10), status: ExpenseStatus.pending),
        ],
        paymentMethodId: 'pm_nubank',
      );
      expect(matches['netflix']!.kind, LineMatchKind.probable);
    });
  });

  group('Revisão e plano de gravação', () {
    final schedule = const CycleSchedule(5);
    final lines = [
      _line('mercado', DateTime(2026, 10, 12), 'PAO DE ACUCAR LJ 1234', 48560),
      _line('farmacia', DateTime(2026, 10, 9), 'DROGASIL 0456', 6290),
      _line('jantar', DateTime(2026, 10, 5), 'RESTAURANTE SABOR', 15400),
      _line('farm', DateTime(2026, 10, 7), 'FARM RIO', 32000),
      _line('enel', DateTime(2026, 10, 3), 'ENEL ENERGIA', 21000),
      _line('steam', DateTime(2026, 10, 4), 'STEAM GAMES', 15000),
      _line('pagamento', DateTime(2026, 10, 1), 'PAGAMENTO RECEBIDO', 120000, kind: StatementLineKind.payment),
    ];
    final expenses = [
      _expense('e_mercado', 'Mercado', 48560, DateTime(2026, 10, 11)),
      _expense('e_farmacia', 'Farmácia', 6290, DateTime(2026, 10, 8), paymentMethodId: 'pm_caixa'),
      _expense('e_jantar', 'Jantar no Sabor', 14000, DateTime(2026, 10, 5)),
    ];

    ImportSession start() => ImportSession.start(
          source: _nubank,
          fileName: 'fatura.csv',
          lines: lines,
          payerMemberId: 'kelvynn',
        ).withExpenses(expenses);

    var nextId = 0;
    String newId() => 'id_${nextId++}';
    setUp(() => nextId = 0);

    test('sugere o vencimento da fatura pelas datas das compras', () {
      // Fecha dia 28, vence dia 10: compras de outubro vencem em 10/11
      expect(start().invoiceDueDate, DateTime(2026, 11, 10));
    });

    test('já lançado vem aceito; provável e valor diferente esperam resposta', () {
      final session = start();

      expect(session.statusOf(lines[0]), LineStatus.linked);
      expect(session.statusOf(lines[1]), LineStatus.needsReview);
      expect(session.statusOf(lines[2]), LineStatus.needsReview);
      expect(session.statusOf(lines[3]), LineStatus.newLine);
      expect(session.statusOf(lines[6]), LineStatus.informational);
      expect(session.blockers, hasLength(1));

      // Total do arquivo conta só compras; o pagamento fica de fora
      expect(session.totals.file.cents, 48560 + 6290 + 15400 + 32000 + 21000 + 15000);
      expect(session.totals.alreadyLaunched.cents, 48560);
    });

    test('confirmar grava uma despesa por linha da Casa, o empréstimo e as correções', () {
      var session = start()
          .withDecision('farmacia', MatchDecision.accepted)
          .withDecision('jantar', MatchDecision.accepted);
      session = session
          .withLine(lines[3].copyWith(destination: LineDestination.splitP2P, assignedMemberId: 'cristiano'))
          .withLine(lines[5].copyWith(destination: LineDestination.cardOwnerPersonal))
          .withSuggestedCategories(categories: _categories, history: expenses);
      expect(session.blockers, isEmpty);

      final plan = session.buildPlan(
        members: _members,
        categories: _categories,
        schedule: schedule,
        now: DateTime(2026, 10, 13),
        newId: newId,
      );

      // Só a Enel é despesa nova: o resto já existia, é empréstimo ou é pessoal
      expect(plan.newExpenses, hasLength(1));
      final enel = plan.newExpenses.single;
      expect(enel.title, 'Enel Energia');
      expect(enel.amount.cents, 21000);
      expect(enel.date, DateTime(2026, 10, 3));
      expect(enel.dueDate, DateTime(2026, 11, 10));
      expect(enel.paymentMethodId, 'pm_nubank');
      expect(enel.paidByMemberId, 'kelvynn');
      expect(enel.paidOutOfPocket, isTrue);
      expect(enel.splitRule.percentages, {'kelvynn': 60.0, 'cristiano': 40.0});

      // O histórico guarda o que cada linha virou
      String outcome(String lineId) =>
          plan.lineRecords.firstWhere((r) => r.line.id == lineId).outcome.name;
      expect(plan.lineRecords, hasLength(lines.length));
      expect(plan.lineRecords.firstWhere((r) => r.line.id == 'enel').expenseId, enel.id);
      expect(outcome('enel'), 'created');
      expect(outcome('mercado'), 'linked');
      expect(outcome('farmacia'), 'linked');
      expect(outcome('steam'), 'ignored');
      expect(outcome('pagamento'), 'ignored');
      expect(plan.lineRecords.firstWhere((r) => r.line.id == 'farm').loanId, plan.loans.single.id);

      expect(plan.loans, hasLength(1));
      final loan = plan.loans.single;
      expect(loan.totalAmount.cents, 32000);
      expect(loan.lenderMemberId, 'kelvynn');
      expect(loan.borrowerMemberId, 'cristiano');
      expect(loan.firstDueDate, DateTime(2026, 11, 10));
      expect(loan.description, contains('Farm Rio'));

      // Farmácia passa para o cartão; o jantar ganha o valor real da fatura
      expect(plan.expenseUpdates, hasLength(2));
      final farmacia = plan.expenseUpdates.firstWhere((e) => e.id == 'e_farmacia');
      expect(farmacia.paymentMethodId, 'pm_nubank');
      expect(farmacia.dueDate, DateTime(2026, 11, 10));
      expect(farmacia.paidOutOfPocket, isTrue);
      final jantar = plan.expenseUpdates.firstWhere((e) => e.id == 'e_jantar');
      expect(jantar.amount.cents, 15400);

      // Casa + empréstimo + pessoal + já lançado = total do arquivo
      final totals = session.totals;
      expect(
        totals.house.cents + totals.loans.cents + totals.personal.cents + totals.alreadyLaunched.cents,
        totals.file.cents,
      );
    });

    test('linha que já veio em outra importação não é lançada, a menos que o usuário mande', () {
      var session = start()
          .withDecision('farmacia', MatchDecision.accepted)
          .withDecision('jantar', MatchDecision.accepted)
          .withImportedSignatures({lines[4].signature!, lines[3].signature!});

      expect(session.statusOf(lines[4]), LineStatus.alreadyImported);
      expect(session.statusOf(lines[3]), LineStatus.alreadyImported);
      var plan = session.buildPlan(members: _members, categories: _categories, schedule: schedule, newId: newId);
      // Só o Steam continua novo; as já importadas nem entram no histórico de novo
      expect(plan.newExpenses.map((e) => e.amount.cents), [15000]);
      expect(plan.lineRecords.any((r) => r.line.id == 'enel' || r.line.id == 'farm'), isFalse);

      session = session.withForcedLine('enel');
      expect(session.statusOf(lines[4]), LineStatus.newLine);
      plan = session.buildPlan(members: _members, categories: _categories, schedule: schedule, newId: newId);
      expect(plan.newExpenses.map((e) => e.amount.cents), containsAll([15000, 21000]));
    });

    test('o que vai para o banco: despesas, empréstimo, correções e linhas em um pacote só', () {
      const house = '11111111-1111-4111-8111-111111111111';
      const card = PaymentMethod(
        id: '22222222-2222-4222-8222-222222222222',
        name: 'Nubank',
        type: PaymentMethodType.card,
        ownerMemberId: '33333333-3333-4333-8333-333333333333',
        closingDay: 28,
        dueDay: 10,
      );
      const members = [
        HouseMember(id: '33333333-3333-4333-8333-333333333333', name: 'Kelvynn', defaultSplitPercent: 60),
        HouseMember(id: '44444444-4444-4444-8444-444444444444', name: 'Cristiano', defaultSplitPercent: 40),
      ];
      final session = ImportSession.start(
        source: card,
        fileName: 'fatura.csv',
        lines: [
          _line('enel', DateTime(2026, 10, 3), 'ENEL ENERGIA', 21000),
          _line('farm', DateTime(2026, 10, 7), 'FARM RIO', 32000)
              .copyWith(destination: LineDestination.splitP2P, assignedMemberId: members[1].id),
          _line('steam', DateTime(2026, 10, 4), 'STEAM GAMES', 15000)
              .copyWith(destination: LineDestination.cardOwnerPersonal),
        ],
        payerMemberId: members[0].id,
      );
      final plan = session.buildPlan(members: members, categories: const [], schedule: schedule);
      final payload = importPayload(session, plan, houseId: house, currentUserId: members[0].id);

      final batch = payload['batch'] as Map;
      expect(batch['house_id'], house);
      expect(batch['source_type'], 'credit_card');
      expect(batch['payment_method_id'], card.id);
      expect(batch['invoice_due_date'], '2026-11-10');
      expect(batch['total_cents'], 68000);

      final expense = (payload['expenses'] as List).single as Map;
      expect(expense['amount_cents'], 21000);
      expect(expense['due_date'], '2026-11-10');
      expect(expense['status'], 'paid');
      expect((expense['split_rules'] as List).map((r) => (r as Map)['calculated_cents']), [12600, 8400]);

      final loan = (payload['loans'] as List).single as Map;
      expect(loan['total_amount_cents'], 32000);
      expect(loan['borrower_id'], members[1].id);
      expect(((loan['installments'] as List).single as Map)['due_date'], '2026-11-10');

      final rows = {for (final row in payload['lines'] as List) (row as Map)['description']: row};
      expect(rows['ENEL ENERGIA']!['decision'], 'created');
      expect(rows['ENEL ENERGIA']!['expense_id'], expense['id']);
      expect(rows['ENEL ENERGIA']!['signature'], '2026-10-03|21000|enel energia#1');
      expect(rows['FARM RIO']!['split_destination'], 'p2p_loan');
      expect(rows['FARM RIO']!['loan_id'], loan['id']);
      expect(rows['STEAM GAMES']!['decision'], 'ignored');
      expect(rows['STEAM GAMES']!['split_destination'], 'personal');
    });

    test('"são diferentes" faz a linha virar lançamento novo', () {
      final session = start()
          .withDecision('farmacia', MatchDecision.rejected)
          .withDecision('jantar', MatchDecision.rejected);

      expect(session.statusOf(lines[1]), LineStatus.newLine);
      final plan = session.buildPlan(members: _members, categories: _categories, schedule: schedule, newId: newId);
      expect(plan.newExpenses.map((e) => e.amount.cents), containsAll([6290, 15400]));
      expect(plan.expenseUpdates, isEmpty);
    });

    test('empréstimo sem devedor, ou devendo para quem paga, bloqueia a confirmação', () {
      var session = start()
          .withDecision('farmacia', MatchDecision.accepted)
          .withDecision('jantar', MatchDecision.accepted)
          .withLine(lines[3].copyWith(destination: LineDestination.splitP2P));
      expect(session.blockers, hasLength(1));

      session = session.withLine(
        lines[3].copyWith(destination: LineDestination.splitP2P, assignedMemberId: 'cristiano'),
      );
      expect(session.blockers, isEmpty);

      // Trocar quem paga para o devedor desfaz a escolha
      expect(session.withPayer('cristiano').blockers, hasLength(1));
    });

    test('despesa já acertada em fechamento, ou com rateio fixo, não é alterada', () {
      final locked = [
        _expense('e_farmacia', 'Farmácia', 6290, DateTime(2026, 10, 8),
            paymentMethodId: 'pm_caixa', settledAt: DateTime(2026, 10, 10)),
        _expense('e_jantar', 'Jantar no Sabor', 14000, DateTime(2026, 10, 5),
            splitRule: const SplitRule.fixed({'kelvynn': Money(7000), 'cristiano': Money(7000)})),
      ];
      final session = ImportSession.start(
        source: _nubank,
        fileName: 'fatura.csv',
        lines: lines,
        payerMemberId: 'kelvynn',
      )
          .withExpenses(locked)
          .withDecision('farmacia', MatchDecision.accepted)
          .withDecision('jantar', MatchDecision.accepted);

      final plan = session.buildPlan(members: _members, categories: _categories, schedule: schedule, newId: newId);
      expect(plan.expenseUpdates, isEmpty);
      // Continuam vinculadas: não são lançadas de novo
      expect(plan.newExpenses.map((e) => e.amount.cents), isNot(contains(6290)));
    });

    test('ciclo fechado: lança como ajuste no ciclo de hoje ou deixa de fora', () {
      final session = start()
          .withDecision('farmacia', MatchDecision.accepted)
          .withDecision('jantar', MatchDecision.accepted);
      final today = DateTime(2026, 12, 10);
      // No cartão, todas as linhas contam no ciclo do vencimento da fatura
      final closed = {schedule.cycleFor(DateTime(2026, 11, 10))};
      expect(session.countingCycles(schedule), closed);
      expect(session.linesInClosedCycles(schedule, closed), hasLength(3));

      final adjusted = session.buildPlan(
        members: _members,
        categories: _categories,
        schedule: schedule,
        closedCycles: closed,
        now: today,
        newId: newId,
      );
      final enel = adjusted.newExpenses.firstWhere((e) => e.amount.cents == 21000);
      expect(enel.title, 'Enel Energia (ajuste de 03/10)');
      expect(enel.date, today);
      expect(enel.dueDate, today);
      expect(closed.contains(schedule.cycleFor(enel.dueDate!)), isFalse);

      final skipped = session.buildPlan(
        members: _members,
        categories: _categories,
        schedule: schedule,
        closedCycles: closed,
        closedCyclePolicy: ClosedCyclePolicy.skip,
        now: today,
        newId: newId,
      );
      expect(skipped.newExpenses, isEmpty);
      expect(skipped.skippedClosedCycle, hasLength(3));
    });

    test('extrato de conta: cada linha conta no ciclo da própria data e não tem vencimento de fatura', () {
      final session = ImportSession.start(
        source: _account,
        fileName: 'extrato.ofx',
        lines: [
          _line('a', DateTime(2026, 9, 28), 'PIX PADARIA', 2500),
          _line('b', DateTime(2026, 10, 8), 'PIX FEIRA', 4000),
        ],
        payerMemberId: 'kelvynn',
      );
      expect(session.invoiceDueDate, isNull);
      expect(session.blockers, isEmpty);
      expect(session.countingCycles(schedule), hasLength(2));

      final closed = {schedule.cycleFor(DateTime(2026, 9, 28))};
      final plan = session.buildPlan(
        members: _members,
        categories: _categories,
        schedule: schedule,
        closedCycles: closed,
        closedCyclePolicy: ClosedCyclePolicy.skip,
        newId: newId,
      );
      expect(plan.newExpenses.single.title, 'Pix Feira');
      expect(plan.newExpenses.single.dueDate, isNull);
      expect(plan.skippedClosedCycle.single.id, 'a');
    });

    test('sugere categoria por despesa parecida já lançada ou pelo nome da categoria', () {
      final session = ImportSession.start(
        source: _nubank,
        fileName: 'fatura.csv',
        lines: [
          _line('a', DateTime(2026, 10, 3), 'ENEL ENERGIA', 21000),
          _line('b', DateTime(2026, 10, 4), 'SUPERMERCADO EXTRA', 9000),
          _line('c', DateTime(2026, 10, 5), 'LOJA QUALQUER', 5000),
        ],
        payerMemberId: 'kelvynn',
      ).withSuggestedCategories(
        categories: _categories,
        history: [
          HouseExpense(
            id: 'h1',
            title: 'Enel',
            amount: const Money(19000),
            date: DateTime(2026, 9, 3),
            categoryId: 'cat_contas',
            paidByMemberId: 'kelvynn',
            paymentMethodId: 'pm_caixa',
            splitRule: const SplitRule.percentage(null),
          ),
        ],
      );

      expect(session.lines[0].categoryId, 'cat_contas');
      expect(session.lines[1].categoryId, 'cat_mercado');
      expect(session.lines[2].categoryId, isNull);
    });
  });

  group('Edição em lote', () {
    final lines = [
      _line('a', DateTime(2026, 10, 3), 'POSTO IPIRANGA LJ 0012', 15000),
      _line('b', DateTime(2026, 10, 9), 'POSTO IPIRANGA LJ 0044', 18000),
      _line('c', DateTime(2026, 10, 5), 'PADARIA', 2500),
    ];
    final session = ImportSession.start(
      source: _nubank,
      fileName: 'fatura.csv',
      lines: lines,
      payerMemberId: 'kelvynn',
    );

    test('acha as outras linhas do mesmo estabelecimento, mesmo com loja diferente', () {
      expect(session.similarLines(lines[0]).map((l) => l.id), ['b']);
      expect(session.similarLines(lines[2]), isEmpty);
    });

    test('aplica a mesma mudança às linhas marcadas e deixa as outras como estão', () {
      final updated = session.withLines(
        {'a', 'b'},
        (line) => line.copyWith(destination: LineDestination.splitP2P, assignedMemberId: 'cristiano'),
      );

      expect(updated.lines[0].destination, LineDestination.splitP2P);
      expect(updated.lines[1].assignedMemberId, 'cristiano');
      expect(updated.lines[2].destination, LineDestination.house);
      expect(updated.totals.loans.cents, 33000);
    });
  });

  group('Extrato de conta: o que não é compra', () {
    const houseAccount = PaymentMethod(id: 'pm_casa', name: 'Conta da Casa', type: PaymentMethodType.account);
    final invoice = CardInvoice(
      paymentMethodId: 'pm_nubank',
      dueDate: DateTime(2026, 11, 10),
      total: const Money(101240),
      purchasesCount: 5,
    );
    final history = [
      ImportBatch(
        id: 'b1',
        sourceName: 'Nubank',
        paymentMethodId: 'pm_nubank',
        fileName: 'fatura.csv',
        invoiceDueDate: DateTime(2026, 11, 10),
        total: const Money(148240),
        linesCount: 7,
        createdCount: 4,
        createdAt: DateTime(2026, 10, 30),
      ),
    ];
    final loan = P2PLoan(
      id: 'loan1',
      title: 'Nubank (venc. 10/11) — Cristiano',
      totalAmount: const Money(32000),
      lenderMemberId: 'kelvynn',
      borrowerMemberId: 'cristiano',
      installmentsCount: 1,
      createdAt: DateTime(2026, 10, 30),
      firstDueDate: DateTime(2026, 11, 10),
      installments: [
        P2PInstallment(
          id: 'i1',
          loanId: 'loan1',
          number: 1,
          totalCount: 1,
          amount: const Money(32000),
          dueDate: DateTime(2026, 11, 10),
        ),
      ],
    );
    final lines = [
      _line('fatura', DateTime(2026, 11, 9), 'PAGTO FATURA NUBANK', 148240, kind: StatementLineKind.payment),
      _line('pix', DateTime(2026, 11, 8), 'PIX RECEBIDO CRISTIANO SILVA', 32000, kind: StatementLineKind.income),
      _line('padaria', DateTime(2026, 11, 7), 'PIX ENVIADO PADARIA', 2500),
    ];

    Map<String, List<ExtraAction>> options(PaymentMethod source) => StatementExtras.optionsFor(
          lines: lines,
          source: source,
          payerMemberId: 'kelvynn',
          members: _members,
          cards: const [_nubank],
          openInvoices: [invoice],
          history: history,
          loans: [loan],
        );

    test('pagamento de fatura é reconhecido pelo total do arquivo importado daquela fatura', () {
      final found = options(_account)['fatura']!;

      expect(found.single.type, ExtraActionType.payInvoice);
      expect(found.single.label, 'Pagamento da fatura Nubank de 10/11');
      // O app só conhece a parte da casa (1.012,40); o banco cobrou 1.482,40
      expect(found.single.suggested, isTrue);
      expect(found.single.invoiceDueDate, DateTime(2026, 11, 10));
    });

    test('Pix recebido na conta de um morador abate o empréstimo dele, e não é aporte', () {
      final found = options(_account)['pix']!;

      expect(found.map((o) => o.type), [ExtraActionType.loanPayment]);
      expect(found.single.suggested, isTrue);
      expect(found.single.loanId, 'loan1');
    });

    test('Pix recebido na conta da casa pode ser aporte de quem aparece na descrição', () {
      final found = options(houseAccount)['pix']!;
      final contributions = found.where((o) => o.type == ExtraActionType.contribution).toList();

      expect(contributions.map((o) => o.memberId), ['kelvynn', 'cristiano']);
      expect(contributions.firstWhere((o) => o.memberId == 'cristiano').suggested, isTrue);
      expect(contributions.firstWhere((o) => o.memberId == 'kelvynn').suggested, isFalse);
    });

    test('compra e fatura de cartão não têm essas opções', () {
      expect(options(_account).containsKey('padaria'), isFalse);
      expect(options(_nubank), isEmpty);
    });

    test('o que o usuário escolhe vai para o plano; linha já importada não oferece de novo', () {
      var session = ImportSession.start(
        source: _account,
        fileName: 'extrato.ofx',
        lines: lines,
        payerMemberId: 'kelvynn',
      ).withExtraOptions(options(_account));
      final invoiceKey = session.extraOptionsOf(lines[0]).single.key;
      session = session.withExtraChoice('fatura', invoiceKey);

      var plan = session.buildPlan(members: _members, categories: _categories, schedule: const CycleSchedule(5));
      expect(plan.extraActions.single.action.type, ExtraActionType.payInvoice);
      expect(plan.extraActions.single.line.id, 'fatura');
      // O pagamento não é despesa nova
      expect(plan.newExpenses.map((e) => e.amount.cents), [2500]);
      expect(plan.lineRecords.firstWhere((r) => r.line.id == 'fatura').outcome, LineOutcome.linked);
      expect(plan.lineRecords.firstWhere((r) => r.line.id == 'pix').outcome, LineOutcome.ignored);

      session = session.withExtraChoice('fatura', null);
      expect(session.chosenExtra(lines[0]), isNull);

      session = session
          .withExtraChoice('fatura', invoiceKey)
          .withImportedSignatures({lines[0].signature!});
      expect(session.extraOptionsOf(lines[0]), isEmpty);
      plan = session.buildPlan(members: _members, categories: _categories, schedule: const CycleSchedule(5));
      expect(plan.extraActions, isEmpty);
    });
  });
}
