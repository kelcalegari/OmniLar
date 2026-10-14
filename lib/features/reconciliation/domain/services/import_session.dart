import 'package:intl/intl.dart';

import '../../../../core/domain/value_objects/cycle_schedule.dart';
import '../../../../core/domain/value_objects/financial_cycle.dart';
import '../../../../core/domain/value_objects/money.dart';
import '../../../../core/utils/uuid.dart';
import '../../../finance/domain/entities/category.dart';
import '../../../finance/domain/entities/house_expense.dart';
import '../../../finance/domain/entities/house_member.dart';
import '../../../finance/domain/entities/payment_method.dart';
import '../../../finance/domain/entities/split_rule.dart';
import '../../../finance/domain/services/credit_card_invoice_calculator.dart';
import '../../../finance/domain/services/expense_launch_defaults.dart';
import '../../../p2p/domain/entities/p2p_loan.dart';
import '../entities/imported_statement_line.dart';
import 'statement_matcher.dart';
import 'statement_text.dart';

/// O que o usuário decidiu sobre a despesa que o app achou parecida com a linha.
enum MatchDecision { undecided, accepted, rejected }

/// Situação de uma linha na revisão.
enum LineStatus {
  /// Vai virar lançamento (ou fica de fora, conforme o destino).
  newLine,

  /// Casada com uma despesa do app: não lança de novo.
  linked,

  /// O app achou uma despesa parecida e espera a resposta do usuário.
  needsReview,

  /// Marcada para ignorar.
  ignored,

  /// Pagamento, estorno ou entrada: aparece só para conferência.
  informational,
}

/// O que fazer com as linhas que cairiam em um ciclo já fechado.
enum ClosedCyclePolicy {
  /// Lança no ciclo de hoje, com a data original no título.
  adjustInCurrentCycle,

  /// Não lança; o usuário reabre o ciclo e importa de novo.
  skip,
}

/// Tudo o que a confirmação vai gravar.
class ImportPlan {
  final List<HouseExpense> newExpenses;
  final List<HouseExpense> expenseUpdates;
  final List<P2PLoan> loans;

  /// Linhas deixadas de fora por caírem em ciclo fechado.
  final List<ImportedStatementLine> skippedClosedCycle;

  /// Linhas do arquivo por trás de cada despesa nova, atualização ou
  /// empréstimo (pelo id dele), para saber o que já foi gravado.
  final Map<String, List<String>> lineIdsByRecord;

  const ImportPlan({
    this.newExpenses = const [],
    this.expenseUpdates = const [],
    this.loans = const [],
    this.skippedClosedCycle = const [],
    this.lineIdsByRecord = const {},
  });

  bool get isEmpty => newExpenses.isEmpty && expenseUpdates.isEmpty && loans.isEmpty;
}

class ImportTotals {
  final Money file;
  final Money alreadyLaunched;
  final Money house;
  final Money loans;
  final Money personal;
  final Money ignored;

  const ImportTotals({
    required this.file,
    required this.alreadyLaunched,
    required this.house,
    required this.loans,
    required this.personal,
    required this.ignored,
  });
}

/// Revisão de uma fatura ou extrato importado: as linhas do arquivo, o que
/// cada uma casa no app e o que o usuário decidiu. Nada é gravado aqui.
class ImportSession {
  final PaymentMethod source;
  final String fileName;
  final List<ImportedStatementLine> lines;
  final Map<String, LineMatch> matches;
  final Map<String, MatchDecision> decisions;

  /// Vencimento da fatura (só para cartão).
  final DateTime? invoiceDueDate;

  /// Quem paga a fatura ou é dono da conta.
  final String payerMemberId;

  const ImportSession({
    required this.source,
    required this.fileName,
    required this.lines,
    required this.payerMemberId,
    this.matches = const {},
    this.decisions = const {},
    this.invoiceDueDate,
  });

  static final _dayMonth = DateFormat('dd/MM');

  /// Sessão nova, com o vencimento da fatura sugerido pelas datas das compras.
  factory ImportSession.start({
    required PaymentMethod source,
    required String fileName,
    required List<ImportedStatementLine> lines,
    required String payerMemberId,
  }) {
    return ImportSession(
      source: source,
      fileName: fileName,
      lines: lines,
      payerMemberId: payerMemberId,
      invoiceDueDate: source.isCreditCard ? suggestInvoiceDueDate(lines, source) : null,
    );
  }

  /// Vencimento da fatura a que a maioria das compras pertence. Parcela fica
  /// de fora: muitos bancos a listam com a data da compra original.
  static DateTime? suggestInvoiceDueDate(List<ImportedStatementLine> lines, PaymentMethod card) {
    final closingDay = card.closingDay;
    final dueDay = card.dueDay;
    if (closingDay == null || dueDay == null) return null;

    var purchases = lines.where((l) => l.isPurchase && !l.isInstallment).toList();
    if (purchases.isEmpty) purchases = lines.where((l) => l.isPurchase).toList();

    final votes = <DateTime, int>{};
    for (final line in purchases) {
      final due = CreditCardInvoiceCalculator.calculateInvoiceDueDate(
        purchaseDate: line.date,
        closingDay: closingDay,
        dueDay: dueDay,
      );
      votes[due] = (votes[due] ?? 0) + 1;
    }
    if (votes.isEmpty) return null;

    final ranked = votes.entries.toList()
      ..sort((a, b) {
        final byVotes = b.value.compareTo(a.value);
        return byVotes != 0 ? byVotes : b.key.compareTo(a.key);
      });
    return ranked.first.key;
  }

  ImportSession _copy({
    List<ImportedStatementLine>? lines,
    Map<String, LineMatch>? matches,
    Map<String, MatchDecision>? decisions,
    DateTime? invoiceDueDate,
    String? payerMemberId,
  }) {
    return ImportSession(
      source: source,
      fileName: fileName,
      lines: lines ?? this.lines,
      matches: matches ?? this.matches,
      decisions: decisions ?? this.decisions,
      invoiceDueDate: invoiceDueDate ?? this.invoiceDueDate,
      payerMemberId: payerMemberId ?? this.payerMemberId,
    );
  }

  ImportSession withInvoiceDueDate(DateTime dueDate) =>
      _copy(invoiceDueDate: DateTime(dueDate.year, dueDate.month, dueDate.day));

  ImportSession withPayer(String memberId) {
    // Quem paga a fatura não pode dever para si mesmo
    final fixed = [
      for (final line in lines)
        line.assignedMemberId == memberId ? line.copyWith(clearAssignedMember: true) : line,
    ];
    return _copy(payerMemberId: memberId, lines: fixed);
  }

  ImportSession withLine(ImportedStatementLine updated) =>
      _copy(lines: [for (final line in lines) line.id == updated.id ? updated : line]);

  ImportSession withDecision(String lineId, MatchDecision decision) =>
      _copy(decisions: {...decisions, lineId: decision});

  /// Compara as linhas com as despesas do app. Mantém o que o usuário já
  /// respondeu quando a linha continua casada com a mesma despesa.
  ImportSession withExpenses(List<HouseExpense> expenses) {
    final found = StatementMatcher.match(
      lines: lines,
      expenses: expenses,
      paymentMethodId: source.id,
    );
    final kept = <String, MatchDecision>{
      for (final entry in decisions.entries)
        if (found[entry.key]?.expense.id == matches[entry.key]?.expense.id) entry.key: entry.value,
    };
    return _copy(matches: found, decisions: kept);
  }

  /// Sugere a categoria das linhas ainda sem uma: a de uma despesa parecida já
  /// lançada, senão a categoria cujo nome aparece na descrição.
  ImportSession withSuggestedCategories({
    required List<ExpenseCategory> categories,
    required List<HouseExpense> history,
  }) {
    if (categories.isEmpty) return this;
    final validIds = {for (final c in categories) c.id};

    String? suggest(ImportedStatementLine line) {
      HouseExpense? best;
      var bestScore = 0.6;
      for (final expense in history) {
        if (!validIds.contains(expense.categoryId)) continue;
        final score = StatementText.similarity(line.description, expense.title);
        if (score >= bestScore) {
          best = expense;
          bestScore = score;
        }
      }
      if (best != null) return best.categoryId;

      for (final category in categories) {
        if (StatementText.similarity(line.description, category.name) >= 1) return category.id;
      }
      return null;
    }

    return _copy(
      lines: [
        for (final line in lines)
          line.isPurchase && line.categoryId == null
              ? line.copyWith(categoryId: suggest(line))
              : line,
      ],
    );
  }

  LineMatch? matchOf(String lineId) => matches[lineId];

  MatchDecision decisionOf(String lineId) {
    final match = matches[lineId];
    if (match == null) return MatchDecision.rejected;
    return decisions[lineId] ??
        (match.kind == LineMatchKind.alreadyLaunched
            ? MatchDecision.accepted
            : MatchDecision.undecided);
  }

  LineStatus statusOf(ImportedStatementLine line) {
    if (!line.isPurchase) return LineStatus.informational;
    if (matches.containsKey(line.id)) {
      switch (decisionOf(line.id)) {
        case MatchDecision.accepted:
          return LineStatus.linked;
        case MatchDecision.undecided:
          return LineStatus.needsReview;
        case MatchDecision.rejected:
          break;
      }
    }
    return line.destination == LineDestination.ignored ? LineStatus.ignored : LineStatus.newLine;
  }

  /// Linhas que vão virar lançamento.
  Iterable<ImportedStatementLine> get newLines =>
      lines.where((line) => statusOf(line) == LineStatus.newLine);

  int countOf(LineStatus status) => lines.where((line) => statusOf(line) == status).length;

  ImportTotals get totals {
    var file = 0;
    var linked = 0;
    var house = 0;
    var loans = 0;
    var personal = 0;
    var ignored = 0;
    for (final line in lines) {
      if (!line.isPurchase) continue;
      final cents = line.amount.cents;
      file += cents;
      switch (statusOf(line)) {
        case LineStatus.linked:
          linked += cents;
        case LineStatus.ignored:
          ignored += cents;
        case LineStatus.newLine:
          switch (line.destination) {
            case LineDestination.house:
              house += cents;
            case LineDestination.splitP2P:
              loans += cents;
            case LineDestination.cardOwnerPersonal:
              personal += cents;
            case LineDestination.ignored:
              ignored += cents;
          }
        case LineStatus.needsReview:
        case LineStatus.informational:
          break;
      }
    }
    return ImportTotals(
      file: Money(file),
      alreadyLaunched: Money(linked),
      house: Money(house),
      loans: Money(loans),
      personal: Money(personal),
      ignored: Money(ignored),
    );
  }

  /// O valor da despesa pode ser trocado pelo da fatura? Despesa já acertada
  /// em um fechamento, com sub-itens ou com rateio em valores fixos, não.
  static bool canUpdateAmount(HouseExpense expense) =>
      expense.settledAt == null &&
      !expense.isItemized &&
      expense.splitRule.type != SplitType.fixed;

  /// O que falta resolver antes de confirmar (vazio = pode confirmar).
  List<String> get blockers {
    final issues = <String>[];
    if (source.isCreditCard && invoiceDueDate == null) {
      issues.add('Informe o vencimento da fatura.');
    }
    final pending = countOf(LineStatus.needsReview);
    if (pending > 0) {
      issues.add(pending == 1
          ? '1 linha parece já estar lançada: diga se é a mesma.'
          : '$pending linhas parecem já estar lançadas: diga se são as mesmas.');
    }
    final withoutDebtor = newLines.where((line) =>
        line.destination == LineDestination.splitP2P &&
        (line.assignedMemberId == null || line.assignedMemberId == payerMemberId));
    if (withoutDebtor.isNotEmpty) {
      issues.add('Escolha quem deve em cada linha marcada como empréstimo.');
    }
    return issues;
  }

  /// Dia que define o ciclo de uma linha nova: o vencimento da fatura, para
  /// cartão; a data do lançamento, para conta.
  DateTime _countingDate(ImportedStatementLine line) =>
      source.isCreditCard ? (invoiceDueDate ?? line.date) : line.date;

  /// Ciclos em que as compras do arquivo contam (para saber se algum já fechou).
  Set<FinancialCycle> countingCycles(CycleSchedule schedule) => {
        for (final line in lines)
          if (line.isPurchase) schedule.cycleFor(_countingDate(line)),
      };

  /// Linhas novas da Casa que cairiam em um dos [closedCycles].
  List<ImportedStatementLine> linesInClosedCycles(
    CycleSchedule schedule,
    Set<FinancialCycle> closedCycles,
  ) =>
      [
        for (final line in newLines)
          if (line.destination == LineDestination.house &&
              closedCycles.contains(schedule.cycleFor(_countingDate(line))))
            line,
      ];

  /// Ciclos onde pode haver uma despesa igual a alguma linha do arquivo.
  Set<FinancialCycle> cyclesToSearch(CycleSchedule schedule) {
    final cycles = <FinancialCycle>{};
    for (final line in lines) {
      if (!line.isPurchase) continue;
      for (final offset in const [-StatementMatcher.dateWindowDays, StatementMatcher.dateWindowDays]) {
        cycles.add(schedule.cycleFor(line.date.add(Duration(days: offset))));
      }
    }
    final dueDate = invoiceDueDate;
    if (dueDate != null) cycles.add(schedule.cycleFor(dueDate));
    return cycles;
  }

  String _titleOf(ImportedStatementLine line) {
    final edited = line.title?.trim();
    final base = edited != null && edited.isNotEmpty ? edited : StatementText.cleanTitle(line.description);
    return line.isInstallment ? '$base (${line.installmentNumber}/${line.installmentsTotal})' : base;
  }

  /// Monta o que a confirmação vai gravar. [closedCycles] são os ciclos já
  /// fechados entre os de [countingCycles].
  ImportPlan buildPlan({
    required List<HouseMember> members,
    required List<ExpenseCategory> categories,
    required CycleSchedule schedule,
    Set<FinancialCycle> closedCycles = const {},
    ClosedCyclePolicy closedCyclePolicy = ClosedCyclePolicy.adjustInCurrentCycle,
    DateTime? now,
    String Function() newId = generateUuidV4,
  }) {
    final today = now ?? DateTime.now();
    final memberNames = {for (final m in members) m.id: m.name.split(' ').first};
    final defaultCategory = ExpenseLaunchDefaults.matchCategory(categories);
    final outOfPocket = ExpenseLaunchDefaults.paidOutOfPocket(source);

    final newExpenses = <HouseExpense>[];
    final lineIdsByRecord = <String, List<String>>{};
    final skipped = <ImportedStatementLine>[];
    final loanLines = <String, List<ImportedStatementLine>>{};

    for (final line in newLines) {
      switch (line.destination) {
        case LineDestination.house:
          final inClosedCycle = closedCycles.contains(schedule.cycleFor(_countingDate(line)));
          if (inClosedCycle && closedCyclePolicy == ClosedCyclePolicy.skip) {
            skipped.add(line);
            continue;
          }
          final category =
              categories.where((c) => c.id == line.categoryId).firstOrNull ?? defaultCategory;
          final title = _titleOf(line);
          final expenseId = newId();
          lineIdsByRecord[expenseId] = [line.id];
          newExpenses.add(
            HouseExpense(
              id: expenseId,
              title: inClosedCycle ? '$title (ajuste de ${_dayMonth.format(line.date)})' : title,
              amount: line.amount,
              // Ajuste de ciclo fechado conta hoje, e não na data da compra
              date: inClosedCycle ? today : line.date,
              dueDate: source.isCreditCard
                  ? (inClosedCycle ? DateTime(today.year, today.month, today.day) : invoiceDueDate)
                  : null,
              categoryId: category?.id ?? '',
              paidByMemberId: payerMemberId,
              paymentMethodId: source.id,
              paidOutOfPocket: outOfPocket,
              splitRule: ExpenseLaunchDefaults.splitRule(
                category: category,
                members: members,
                paidByMemberId: payerMemberId,
              ),
              status: ExpenseStatus.paid,
              notes: 'Importado de ${source.name}: ${line.description}',
            ),
          );
        case LineDestination.splitP2P:
          final debtor = line.assignedMemberId;
          if (debtor != null && debtor != payerMemberId) {
            loanLines.putIfAbsent(debtor, () => []).add(line);
          }
        case LineDestination.cardOwnerPersonal:
        case LineDestination.ignored:
          break;
      }
    }

    final dueLabel = invoiceDueDate != null ? ' (venc. ${_dayMonth.format(invoiceDueDate!)})' : '';
    final loans = <P2PLoan>[];
    for (final entry in loanLines.entries) {
      final loanId = newId();
      lineIdsByRecord[loanId] = [for (final line in entry.value) line.id];
      loans.add(
        P2PLoan(
          id: loanId,
          title: '${source.name}$dueLabel — ${memberNames[entry.key] ?? 'morador'}',
          description: entry.value
              .map((line) => '${_titleOf(line)} ${line.amount.formatted}')
              .join('; '),
          totalAmount: Money(entry.value.fold<int>(0, (acc, line) => acc + line.amount.cents)),
          lenderMemberId: payerMemberId,
          borrowerMemberId: entry.key,
          installmentsCount: 1,
          createdAt: today,
          // Quem deve paga junto com a fatura
          firstDueDate: invoiceDueDate ?? today.add(const Duration(days: 30)),
        ),
      );
    }

    final updates = <HouseExpense>[];
    for (final line in lines) {
      if (statusOf(line) != LineStatus.linked) continue;
      final match = matches[line.id]!;
      final expense = match.expense;
      if (expense.settledAt != null) continue;
      lineIdsByRecord[expense.id] = [line.id];

      if (match.kind == LineMatchKind.amountDiffers && canUpdateAmount(expense)) {
        updates.add(expense.copyWith(amount: line.amount));
      } else if (match.kind == LineMatchKind.probable &&
          expense.isPaid &&
          expense.paymentMethodId != source.id) {
        // Foi lançada em outra forma de pagamento: passa para a do arquivo
        updates.add(
          expense.copyWith(
            paymentMethodId: source.id,
            paidByMemberId: payerMemberId,
            paidOutOfPocket: outOfPocket,
            dueDate: source.isCreditCard ? invoiceDueDate : null,
          ),
        );
      }
    }

    return ImportPlan(
      newExpenses: newExpenses,
      expenseUpdates: updates,
      loans: loans,
      skippedClosedCycle: skipped,
      lineIdsByRecord: lineIdsByRecord,
    );
  }
}
