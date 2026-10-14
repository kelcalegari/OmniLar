import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/domain/value_objects/cycle_schedule.dart';
import 'package:omni_lar/core/domain/value_objects/money.dart';
import 'package:omni_lar/features/finance/domain/entities/category.dart';
import 'package:omni_lar/features/finance/domain/entities/house_expense.dart';
import 'package:omni_lar/features/finance/domain/entities/house_member.dart';
import 'package:omni_lar/features/finance/domain/entities/payment_method.dart';
import 'package:omni_lar/features/finance/domain/entities/split_rule.dart';
import 'package:omni_lar/features/reconciliation/domain/entities/imported_statement_line.dart';
import 'package:omni_lar/features/reconciliation/domain/services/import_session.dart';
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
      expect(plan.lineIdsByRecord[enel.id], ['enel']);

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
}
