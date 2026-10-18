import 'package:intl/intl.dart';

import '../../../../core/domain/value_objects/cycle_schedule.dart';
import '../../../../core/domain/value_objects/financial_cycle.dart';
import '../../../../core/domain/value_objects/money.dart';
import '../../../../core/utils/uuid.dart';
import '../../../finance/domain/entities/category.dart';
import '../../../finance/domain/entities/house_expense.dart';
import '../../../finance/domain/entities/house_member.dart';
import '../../../finance/domain/entities/import_params.dart';
import '../../../finance/domain/entities/payment_method.dart';
import '../../../finance/domain/entities/split_rule.dart';
import '../../../finance/domain/services/credit_card_invoice_calculator.dart';
import '../../../finance/domain/services/expense_launch_defaults.dart';
import '../../../p2p/domain/entities/p2p_loan.dart';
import '../entities/imported_statement_line.dart';
import '../repositories/import_repository.dart';
import 'statement_extras.dart';
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

  /// Já veio em uma importação anterior deste cartão ou conta.
  alreadyImported,

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

/// Para onde vai um estorno da fatura.
class RefundOption {
  /// Identifica a opção entre as de um estorno.
  final String key;
  final String label;

  /// Mesmo valor ou descrição parecida: é provável que seja esta.
  final bool suggested;

  /// Compra da mesma fatura de que o estorno é abatido.
  final String? lineId;

  /// Despesa já lançada no app de que o estorno é abatido.
  final HouseExpense? expense;

  const RefundOption({
    required this.key,
    required this.label,
    this.suggested = false,
    this.lineId,
    this.expense,
  });

  /// O estorno cobre a despesa inteira: ela é excluída, e não abatida.
  bool coversWholeExpense(Money refund) => expense != null && expense!.amount.cents <= refund.cents;
}

/// O que uma linha do arquivo virou, para o histórico da importação.
enum LineOutcome {
  /// A importação criou a despesa ou o empréstimo.
  created,

  /// Já existia no app.
  linked,

  /// Pessoal, ignorada ou só informativa.
  ignored,

  /// Ficou de fora por cair em ciclo fechado: pode ser importada depois.
  skipped,
}

class ImportLineRecord {
  final ImportedStatementLine line;
  final LineOutcome outcome;
  final String? title;
  final String? expenseId;
  final String? loanId;

  const ImportLineRecord({
    required this.line,
    required this.outcome,
    this.title,
    this.expenseId,
    this.loanId,
  });
}

/// Tudo o que a confirmação vai gravar.
class ImportPlan {
  final List<HouseExpense> newExpenses;
  final List<HouseExpense> expenseUpdates;
  final List<P2PLoan> loans;

  /// Linhas deixadas de fora por caírem em ciclo fechado.
  final List<ImportedStatementLine> skippedClosedCycle;

  /// O que cada linha virou. Linhas já importadas antes não entram de novo.
  final List<ImportLineRecord> lineRecords;

  /// Movimentos do extrato que não são despesa: pagamento de fatura, aporte e
  /// abatimento de empréstimo. São gravados depois da importação, um a um.
  final List<({ImportedStatementLine line, ExtraAction action})> extraActions;

  /// A fatura importada já foi paga: registrar o pagamento depois de gravar.
  final ({DateTime dueDate, DateTime paidAt, bool paidByHouse})? invoicePayment;

  /// Despesas já lançadas que um estorno cobriu por inteiro: excluídas depois
  /// de gravar a importação.
  final List<HouseExpense> expenseDeletions;

  const ImportPlan({
    this.newExpenses = const [],
    this.expenseUpdates = const [],
    this.loans = const [],
    this.skippedClosedCycle = const [],
    this.lineRecords = const [],
    this.extraActions = const [],
    this.invoicePayment,
    this.expenseDeletions = const [],
  });

  bool get isEmpty =>
      newExpenses.isEmpty && expenseUpdates.isEmpty && loans.isEmpty && extraActions.isEmpty;
}

class ImportTotals {
  final Money file;
  final Money alreadyLaunched;
  final Money house;
  final Money loans;
  final Money personal;
  final Money ignored;

  /// Parte que quem não mora na casa pagou (repasse).
  final Money thirdParty;

  const ImportTotals({
    required this.file,
    required this.alreadyLaunched,
    required this.house,
    required this.loans,
    required this.personal,
    required this.ignored,
    this.thirdParty = const Money.zero(),
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

  /// Assinaturas das linhas já importadas deste cartão ou conta.
  final Set<String> importedSignatures;

  /// Linhas já importadas que o usuário mandou lançar de novo (pelo id).
  final Set<String> forcedLineIds;

  /// O que cada linha que não é compra pode virar (por id da linha).
  final Map<String, List<ExtraAction>> extraOptions;

  /// A opção escolhida pelo usuário (id da linha -> chave da opção).
  final Map<String, String> extraChoices;

  /// Despesas do app próximas das linhas, de onde saem as opções de estorno.
  final List<HouseExpense> knownExpenses;

  /// Para onde vai cada estorno (id da linha do estorno -> chave da opção).
  final Map<String, String> refundChoices;

  /// De que despesa era cada resposta em [decisions] (id da linha -> id da
  /// despesa), para a resposta sobreviver quando a comparação é refeita.
  final Map<String, String> decisionTargets;

  /// Linhas que vieram classificadas por uma regra aprendida (pelo id).
  final Set<String> ruledLineIds;

  /// Dia em que a fatura importada foi paga, se o usuário informou.
  final DateTime? invoicePaidAt;

  /// A fatura foi paga pelo Caixa da Casa (e não pelo titular).
  final bool invoicePaidByHouse;

  /// Janelas do casamento de linhas com despesas, da casa (0100).
  final ImportMatching matching;

  /// Destino padrão das linhas novas, da casa (0100).
  final ImportDefaults defaults;

  const ImportSession({
    required this.source,
    required this.fileName,
    required this.lines,
    required this.payerMemberId,
    this.matches = const {},
    this.decisions = const {},
    this.invoiceDueDate,
    this.importedSignatures = const {},
    this.forcedLineIds = const {},
    this.extraOptions = const {},
    this.extraChoices = const {},
    this.knownExpenses = const [],
    this.refundChoices = const {},
    this.decisionTargets = const {},
    this.ruledLineIds = const {},
    this.invoicePaidAt,
    this.invoicePaidByHouse = false,
    this.matching = const ImportMatching(),
    this.defaults = const ImportDefaults(),
  });

  static final _dayMonth = DateFormat('dd/MM');

  /// Cartão sem dono é da Casa: o Caixa paga a fatura e quem comprou deve
  /// para o Caixa, inclusive quem está importando.
  bool get isHouseCard => source.isCreditCard && source.ownerMemberId == null;

  /// Credor das linhas marcadas como empréstimo.
  String get lenderId => isHouseCard ? P2PLoan.houseLenderId : payerMemberId;

  /// [memberId] pode dever nesta fatura? Ninguém deve para si mesmo.
  bool canOwe(String? memberId) => memberId != null && memberId != lenderId;

  /// Sessão nova, com o vencimento da fatura sugerido pelas datas das compras.
  factory ImportSession.start({
    required PaymentMethod source,
    required String fileName,
    required List<ImportedStatementLine> lines,
    required String payerMemberId,
    ImportMatching matching = const ImportMatching(),
    ImportDefaults defaults = const ImportDefaults(),
  }) {
    return ImportSession(
      source: source,
      fileName: fileName,
      lines: lines,
      payerMemberId: payerMemberId,
      matching: matching,
      defaults: defaults,
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
    Set<String>? importedSignatures,
    Set<String>? forcedLineIds,
    Map<String, List<ExtraAction>>? extraOptions,
    Map<String, String>? extraChoices,
    List<HouseExpense>? knownExpenses,
    Map<String, String>? refundChoices,
    Map<String, String>? decisionTargets,
    Set<String>? ruledLineIds,
    ({DateTime? paidAt, bool byHouse})? invoicePayment,
  }) {
    return ImportSession(
      source: source,
      fileName: fileName,
      lines: lines ?? this.lines,
      matches: matches ?? this.matches,
      decisions: decisions ?? this.decisions,
      invoiceDueDate: invoiceDueDate ?? this.invoiceDueDate,
      payerMemberId: payerMemberId ?? this.payerMemberId,
      importedSignatures: importedSignatures ?? this.importedSignatures,
      forcedLineIds: forcedLineIds ?? this.forcedLineIds,
      extraOptions: extraOptions ?? this.extraOptions,
      extraChoices: extraChoices ?? this.extraChoices,
      knownExpenses: knownExpenses ?? this.knownExpenses,
      refundChoices: refundChoices ?? this.refundChoices,
      decisionTargets: decisionTargets ?? this.decisionTargets,
      ruledLineIds: ruledLineIds ?? this.ruledLineIds,
      invoicePaidAt: invoicePayment != null ? invoicePayment.paidAt : invoicePaidAt,
      invoicePaidByHouse: invoicePayment != null ? invoicePayment.byHouse : invoicePaidByHouse,
      matching: matching,
      defaults: defaults,
    );
  }

  /// A compra deste cartão fica pendente até a fatura ser paga?
  bool get waitsForInvoice => ExpenseLaunchDefaults.waitsForInvoice(source);

  /// Informa (ou, com [paidAt] null, desfaz) que a fatura já foi paga.
  ImportSession withInvoicePayment(DateTime? paidAt, {bool byHouse = false}) => _copy(
        invoicePayment: (
          paidAt: paidAt == null ? null : DateTime(paidAt.year, paidAt.month, paidAt.day, 12),
          byHouse: paidAt != null && byHouse,
        ),
      );

  /// Nome que identifica o estabelecimento de uma linha nas regras aprendidas.
  static String ruleKeyOf(ImportedStatementLine line) =>
      StatementText.normalize(StatementText.cleanTitle(line.description));

  /// Aplica as regras aprendidas às compras do arquivo. Regra de empréstimo
  /// cujo devedor saiu da casa (ou virou quem paga) só aproveita a categoria.
  ImportSession withRules(
    List<ImportRule> rules, {
    required Set<String> memberIds,
    required Set<String> categoryIds,
  }) {
    final byKey = {for (final rule in rules) rule.matchKey: rule};
    final ruled = <String>{};
    final updated = <ImportedStatementLine>[];

    for (final line in lines) {
      final rule = line.isPurchase ? byKey[ruleKeyOf(line)] : null;
      if (rule == null) {
        updated.add(line);
        continue;
      }
      final debtor = rule.assignedMemberId;
      final loanStillValid = rule.destination != LineDestination.splitP2P ||
          (canOwe(debtor) && memberIds.contains(debtor));
      ruled.add(line.id);
      updated.add(
        line.copyWith(
          // No cartão da Casa não existe gasto pessoal fora do Caixa
          destination: !loanStillValid ||
                  (isHouseCard && rule.destination == LineDestination.cardOwnerPersonal)
              ? LineDestination.house
              : rule.destination,
          categoryId: categoryIds.contains(rule.categoryId) ? rule.categoryId : null,
          assignedMemberId: loanStillValid ? debtor : null,
          clearAssignedMember: !loanStillValid || debtor == null,
        ),
      );
    }
    return _copy(lines: updated, ruledLineIds: ruled);
  }

  /// O que vale a pena lembrar desta revisão: um estabelecimento com a mesma
  /// decisão em todas as suas linhas. Casa sem categoria não ensina nada.
  List<ImportRule> rulesToLearn() {
    final byKey = <String, List<ImportedStatementLine>>{};
    for (final line in lines) {
      final status = statusOf(line);
      if (status != LineStatus.newLine && status != LineStatus.ignored) continue;
      final key = ruleKeyOf(line);
      if (key.length < 3) continue;
      byKey.putIfAbsent(key, () => []).add(line);
    }

    final rules = <ImportRule>[];
    for (final entry in byKey.entries) {
      final first = entry.value.first;
      final consistent = entry.value.every((line) =>
          line.destination == first.destination &&
          line.categoryId == first.categoryId &&
          line.assignedMemberId == first.assignedMemberId);
      if (!consistent) continue;
      if (first.destination == LineDestination.house && first.categoryId == null) continue;
      if (first.destination == LineDestination.splitP2P && first.assignedMemberId == null) continue;
      // Quem paga por terceiros muda de uma compra para outra: não vira regra
      if (first.destination == LineDestination.thirdParty) continue;

      final isHouse = first.destination == LineDestination.house;
      rules.add(
        ImportRule(
          matchKey: entry.key,
          merchantName: StatementText.cleanTitle(first.description),
          destination: first.destination,
          categoryId: isHouse ? first.categoryId : null,
          assignedMemberId:
              first.destination == LineDestination.splitP2P ? first.assignedMemberId : null,
        ),
      );
    }
    return rules;
  }

  /// Aplica a mesma mudança a várias linhas de uma vez.
  ImportSession withLines(
    Set<String> lineIds,
    ImportedStatementLine Function(ImportedStatementLine line) change,
  ) =>
      _copy(lines: [for (final line in lines) lineIds.contains(line.id) ? change(line) : line]);

  /// Divide uma compra em duas partes: a primeira com [firstAmount], a segunda
  /// com o resto. Cada parte recebe destino, categoria e devedor próprios (de
  /// início, os da linha). Retorna a sessão como estava se o valor não couber.
  ImportSession splitLine(String lineId, Money firstAmount) {
    final index = lines.indexWhere((l) => l.id == lineId);
    if (index < 0) return this;
    final line = lines[index];
    if (!line.isPurchase || firstAmount.cents <= 0 || firstAmount.cents >= line.amount.cents) {
      return this;
    }

    // Parte de uma parte continua apontando para a linha do arquivo
    final root = line.splitFrom ?? line.id;
    final taken = {for (final l in lines) l.id};
    var next = 1;
    String newId() {
      while (taken.contains('$root#$next')) {
        next++;
      }
      taken.add('$root#$next');
      return '$root#$next';
    }

    final parts = [
      line.asPart(id: newId(), amount: firstAmount, splitFrom: root),
      line.asPart(id: newId(), amount: line.amount - firstAmount, splitFrom: root),
    ];
    return _copy(
      refundChoices: {
        for (final entry in refundChoices.entries)
          if (entry.value != 'line:$lineId') entry.key: entry.value,
      },
      lines: [...lines.sublist(0, index), ...parts, ...lines.sublist(index + 1)],
      // A linha dividida deixa de casar com uma despesa só
      matches: {for (final e in matches.entries) if (e.key != lineId) e.key: e.value},
      decisions: {for (final e in decisions.entries) if (e.key != lineId) e.key: e.value},
    );
  }

  /// Junta de novo as partes da linha [rootId] numa linha só, com a decisão da
  /// primeira parte.
  ImportSession mergeSplit(String rootId) {
    final parts = lines.where((l) => l.splitFrom == rootId).toList();
    if (parts.isEmpty) return this;
    final total = parts.fold<int>(0, (acc, l) => acc + l.amount.cents);
    final merged = ImportedStatementLine(
      id: rootId,
      date: parts.first.date,
      description: parts.first.description,
      amount: Money(total),
      destination: parts.first.destination,
      kind: parts.first.kind,
      externalId: parts.first.externalId,
      signature: parts.first.signature,
      title: parts.first.title,
      categoryId: parts.first.categoryId,
      assignedMemberId: parts.first.assignedMemberId,
      installmentNumber: parts.first.installmentNumber,
      installmentsTotal: parts.first.installmentsTotal,
    );
    final updated = <ImportedStatementLine>[];
    var placed = false;
    for (final line in lines) {
      if (line.splitFrom != rootId) {
        updated.add(line);
      } else if (!placed) {
        updated.add(merged);
        placed = true;
      }
    }
    final partIds = {for (final p in parts) p.id};
    return _copy(
      lines: updated,
      matches: {for (final e in matches.entries) if (!partIds.contains(e.key)) e.key: e.value},
      decisions: {for (final e in decisions.entries) if (!partIds.contains(e.key)) e.key: e.value},
    );
  }

  /// Partes da divisão da linha [rootId], na ordem.
  List<ImportedStatementLine> partsOf(String rootId) =>
      [for (final line in lines) if (line.splitFrom == rootId) line];

  /// Outras linhas ainda por decidir do mesmo estabelecimento de [line].
  List<ImportedStatementLine> similarLines(ImportedStatementLine line) {
    final name = StatementText.normalize(StatementText.cleanTitle(line.description));
    return [
      for (final other in lines)
        if (other.id != line.id &&
            // As partes de uma divisão existem justamente para ter decisões diferentes
            !(line.splitFrom != null && other.splitFrom == line.splitFrom) &&
            (statusOf(other) == LineStatus.newLine || statusOf(other) == LineStatus.ignored) &&
            StatementText.normalize(StatementText.cleanTitle(other.description)) == name)
          other,
    ];
  }

  /// Guarda o que as linhas que não são compra podem virar; a escolha feita
  /// continua valendo enquanto a opção existir.
  ImportSession withExtraOptions(Map<String, List<ExtraAction>> options) => _copy(
        extraOptions: options,
        extraChoices: {
          for (final entry in extraChoices.entries)
            if (options[entry.key]?.any((o) => o.key == entry.value) ?? false) entry.key: entry.value,
        },
      );

  /// Escolhe (ou, com null, desfaz a escolha de) o que a linha vira.
  ImportSession withExtraChoice(String lineId, String? optionKey) => _copy(
        extraChoices: {
          for (final entry in extraChoices.entries)
            if (entry.key != lineId) entry.key: entry.value,
          lineId: ?optionKey,
        },
      );

  /// Opções de uma linha que não é compra. Linha que já veio em outra
  /// importação não tem opções: o movimento já foi registrado.
  List<ExtraAction> extraOptionsOf(ImportedStatementLine line) =>
      line.isPurchase || _wasImported(line) ? const [] : (extraOptions[line.id] ?? const []);

  ExtraAction? chosenExtra(ImportedStatementLine line) {
    final key = extraChoices[line.id];
    if (key == null) return null;
    return extraOptionsOf(line).where((o) => o.key == key).firstOrNull;
  }

  /// A linha que não é compra já veio em uma importação anterior?
  bool wasImported(ImportedStatementLine line) => _wasImported(line);

  ImportSession withImportedSignatures(Set<String> signatures) =>
      _copy(importedSignatures: signatures);

  /// Lança de novo uma linha que já veio em outra importação.
  ImportSession withForcedLine(String lineId) =>
      _copy(forcedLineIds: {...forcedLineIds, lineId});

  bool _wasImported(ImportedStatementLine line) =>
      line.signature != null &&
      importedSignatures.contains(line.signature) &&
      !forcedLineIds.contains(line.id);

  /// Parâmetros da casa para esta importação: janelas do casamento e destino
  /// padrão das linhas novas (0100).
  ImportSession withParams({ImportMatching? matching, ImportDefaults? defaults}) => ImportSession(
        source: source,
        fileName: fileName,
        lines: lines,
        matches: matches,
        decisions: decisions,
        invoiceDueDate: invoiceDueDate,
        payerMemberId: payerMemberId,
        importedSignatures: importedSignatures,
        forcedLineIds: forcedLineIds,
        extraOptions: extraOptions,
        extraChoices: extraChoices,
        knownExpenses: knownExpenses,
        refundChoices: refundChoices,
        decisionTargets: decisionTargets,
        ruledLineIds: ruledLineIds,
        invoicePaidAt: invoicePaidAt,
        invoicePaidByHouse: invoicePaidByHouse,
        matching: matching ?? this.matching,
        defaults: defaults ?? this.defaults,
      );

  ImportSession withInvoiceDueDate(DateTime dueDate) =>
      _copy(invoiceDueDate: DateTime(dueDate.year, dueDate.month, dueDate.day));

  ImportSession withPayer(String memberId) {
    // Quem paga a fatura não pode dever para si mesmo
    if (isHouseCard) return _copy(payerMemberId: memberId);
    final fixed = [
      for (final line in lines)
        line.assignedMemberId == memberId ? line.copyWith(clearAssignedMember: true) : line,
    ];
    return _copy(payerMemberId: memberId, lines: fixed);
  }

  ImportSession withLine(ImportedStatementLine updated) =>
      _copy(lines: [for (final line in lines) line.id == updated.id ? updated : line]);

  ImportSession withDecision(String lineId, MatchDecision decision) => _copy(
        decisions: {...decisions, lineId: decision},
        decisionTargets: {
          ...decisionTargets,
          lineId: ?matches[lineId]?.expense.id,
        },
      );

  /// Compara as linhas com as despesas do app. Mantém o que o usuário já
  /// respondeu quando a linha continua casada com a mesma despesa.
  ImportSession withExpenses(List<HouseExpense> expenses) {
    final found = StatementMatcher.match(
      lines: lines,
      expenses: expenses,
      paymentMethodId: source.id,
      pendingCountsAsLaunched: ExpenseLaunchDefaults.waitsForInvoice(source),
      matching: matching,
    );
    final kept = <String, MatchDecision>{
      for (final entry in decisions.entries)
        if (found[entry.key]?.expense.id ==
            (matches[entry.key]?.expense.id ?? decisionTargets[entry.key]))
          entry.key: entry.value,
    };
    return _copy(matches: found, decisions: kept, knownExpenses: expenses);
  }

  static final _dayMonthShort = DateFormat('dd/MM');

  /// Para onde um estorno pode ir: uma compra desta fatura ou uma despesa já
  /// lançada no mesmo cartão ou conta, com valor de pelo menos o estorno e
  /// anterior a ele. As prováveis (mesmo valor ou descrição parecida) vêm antes.
  List<RefundOption> refundOptionsOf(ImportedStatementLine refund) {
    if (refund.kind != StatementLineKind.refund || _wasImported(refund)) return const [];
    final options = <RefundOption>[];
    final cents = refund.amount.cents;
    bool similar(String text) => StatementText.similarity(refund.description, text) >= 0.5;

    for (final line in newLines) {
      if (line.date.isAfter(refund.date.add(const Duration(days: 1)))) continue;
      // O que outros estornos já abateram desta compra não pode ser abatido de novo
      final available = line.amount.cents - _refundedFromLine(line.id, except: refund.id);
      if (available < cents) continue;
      options.add(
        RefundOption(
          key: 'line:${line.id}',
          label: 'Abater de "${_titleOf(line)}" (${_dayMonthShort.format(line.date)}, ${line.amount.format()}) desta fatura',
          suggested: line.amount.cents == cents || similar(line.description),
          lineId: line.id,
        ),
      );
    }

    final earliest = refund.date.subtract(const Duration(days: 120));
    for (final expense in knownExpenses) {
      if (expense.paymentMethodId != source.id || expense.isProjectExpense) continue;
      if (!canUpdateAmount(expense) || expense.amount.cents < cents) continue;
      if (expense.date.isAfter(refund.date.add(const Duration(days: 1))) || expense.date.isBefore(earliest)) {
        continue;
      }
      final whole = expense.amount.cents == cents;
      options.add(
        RefundOption(
          key: 'expense:${expense.id}',
          label: whole
              ? 'Excluir "${expense.title}" (${_dayMonthShort.format(expense.date)}), já lançada'
              : 'Abater de "${expense.title}" (${_dayMonthShort.format(expense.date)}, ${expense.amount.format()}), já lançada',
          suggested: whole || similar(expense.title),
          expense: expense,
        ),
      );
    }

    options.sort((a, b) => (b.suggested ? 1 : 0) - (a.suggested ? 1 : 0));
    return options;
  }

  RefundOption? chosenRefund(ImportedStatementLine refund) {
    final key = refundChoices[refund.id];
    if (key == null) return null;
    return refundOptionsOf(refund).where((o) => o.key == key).firstOrNull;
  }

  /// Escolhe (ou, com null, desfaz) para onde vai o estorno.
  ImportSession withRefundChoice(String refundLineId, String? optionKey) => _copy(
        refundChoices: {
          for (final entry in refundChoices.entries)
            if (entry.key != refundLineId) entry.key: entry.value,
          refundLineId: ?optionKey,
        },
      );

  /// Quanto os estornos escolhidos abatem da compra [lineId] desta fatura.
  int _refundedFromLine(String lineId, {String? except}) {
    var total = 0;
    for (final entry in refundChoices.entries) {
      if (entry.key == except || entry.value != 'line:$lineId') continue;
      final refund = lines.where((l) => l.id == entry.key).firstOrNull;
      if (refund != null && refund.kind == StatementLineKind.refund && !_wasImported(refund)) {
        total += refund.amount.cents;
      }
    }
    return total;
  }

  /// Valor que a compra vai ter no app: o da fatura menos os estornos abatidos dela.
  Money effectiveAmountOf(ImportedStatementLine line) {
    final cents = line.amount.cents - _refundedFromLine(line.id);
    return Money(cents < 0 ? 0 : cents);
  }

  /// Sugere a categoria das linhas ainda sem uma: a de uma despesa parecida já
  /// lançada, senão a categoria cujo nome aparece na descrição.
  ImportSession withSuggestedCategories({
    required List<ExpenseCategory> categories,
    required List<HouseExpense> history,
  }) {
    if (categories.isEmpty) return this;
    final validIds = {for (final c in categories) c.id};
    // Categoria padrão da importação (0100), se ainda existir
    final defaultCategoryId = validIds.contains(defaults.categoryId) ? defaults.categoryId : null;

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
              ? line.copyWith(categoryId: suggest(line) ?? defaultCategoryId)
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
    if (_wasImported(line)) return LineStatus.alreadyImported;
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
    var thirdParty = 0;
    for (final line in lines) {
      if (!line.isPurchase) continue;
      file += line.amount.cents;
      final cents = effectiveAmountOf(line).cents;
      switch (statusOf(line)) {
        case LineStatus.linked:
        case LineStatus.alreadyImported:
          linked += line.amount.cents;
        case LineStatus.ignored:
          ignored += line.amount.cents;
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
            case LineDestination.thirdParty:
              thirdParty += cents;
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
      thirdParty: Money(thirdParty),
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
        !canOwe(line.assignedMemberId));
    if (withoutDebtor.isNotEmpty) {
      issues.add('Escolha quem deve em cada linha marcada como empréstimo.');
    }
    if (isHouseCard &&
        newLines.any((line) => line.destination == LineDestination.cardOwnerPersonal)) {
      issues.add('Cartão da Casa não tem gasto pessoal: diga quem deve para o Caixa.');
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
      // Compra pendente não é travada por ciclo fechado: em aberto, ela pesa
      // no ciclo atual como conta vencida
      waitsForInvoice
          ? const []
          : [
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
      for (final offset in [-matching.dateWindowDays, matching.dateWindowDays]) {
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

  /// Divisão das linhas novas: categoria com dono é sempre 100% do dono; no
  /// resto vale o modo escolhido pela casa (0100), e por padrão a divisão da
  /// categoria ou da casa.
  SplitRule _splitRuleFor({required ExpenseCategory? category, required List<HouseMember> members}) {
    if (category?.ownerMemberId == null && members.isNotEmpty) {
      switch (defaults.splitMode) {
        case ImportSplitMode.equal:
          return SplitRule.percentage({for (final m in members) m.id: 100.0 / members.length});
        case ImportSplitMode.payer:
          return SplitRule.singleResponsible(payerMemberId);
        case ImportSplitMode.category:
          break;
      }
    }
    return ExpenseLaunchDefaults.splitRule(
      category: category,
      members: members,
      paidByMemberId: payerMemberId,
    );
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
    final defaultCategory =
        ExpenseLaunchDefaults.matchCategory(categories, preferred: defaults.categoryId);
    final outOfPocket = ExpenseLaunchDefaults.paidOutOfPocket(source);

    final newExpenses = <HouseExpense>[];
    final records = <ImportLineRecord>[];
    final skipped = <ImportedStatementLine>[];
    final loanLines = <String, List<ImportedStatementLine>>{};

    for (final line in newLines) {
      // Estorno que cobriu a compra inteira: não sobra nada para lançar
      if (effectiveAmountOf(line).isZero) {
        records.add(ImportLineRecord(line: line, outcome: LineOutcome.ignored));
        continue;
      }
      switch (line.destination) {
        case LineDestination.house:
          final inClosedCycle =
              !waitsForInvoice && closedCycles.contains(schedule.cycleFor(_countingDate(line)));
          if (inClosedCycle && closedCyclePolicy == ClosedCyclePolicy.skip) {
            skipped.add(line);
            records.add(ImportLineRecord(line: line, outcome: LineOutcome.skipped));
            continue;
          }
          final category =
              categories.where((c) => c.id == line.categoryId).firstOrNull ?? defaultCategory;
          final title = _titleOf(line);
          final expenseId = newId();
          records.add(
            ImportLineRecord(
              line: line,
              outcome: LineOutcome.created,
              title: title,
              expenseId: expenseId,
            ),
          );
          newExpenses.add(
            HouseExpense(
              id: expenseId,
              title: inClosedCycle ? '$title (ajuste de ${_dayMonth.format(line.date)})' : title,
              amount: effectiveAmountOf(line),
              // Ajuste de ciclo fechado conta hoje, e não na data da compra
              date: inClosedCycle ? today : line.date,
              dueDate: source.isCreditCard
                  ? (inClosedCycle ? DateTime(today.year, today.month, today.day) : invoiceDueDate)
                  : null,
              categoryId: category?.id ?? '',
              paidByMemberId: payerMemberId,
              paymentMethodId: source.id,
              // Pendente até a fatura ser paga: quem pagou se decide no pagamento
              paidOutOfPocket: waitsForInvoice ? false : outOfPocket,
              splitRule: _splitRuleFor(category: category, members: members),
              status: waitsForInvoice ? ExpenseStatus.pending : ExpenseStatus.paid,
              notes: 'Importado de ${source.name}: ${line.description}',
            ),
          );
        case LineDestination.splitP2P:
          final debtor = line.assignedMemberId;
          if (debtor != null && canOwe(debtor)) {
            loanLines.putIfAbsent(debtor, () => []).add(line);
          }
        case LineDestination.cardOwnerPersonal:
        case LineDestination.ignored:
        case LineDestination.thirdParty:
          break;
      }
    }

    final todayDate = DateTime(today.year, today.month, today.day);
    final invoiceDay = invoiceDueDate ?? todayDate;
    final loanFundedOn =
        closedCycles.contains(schedule.cycleFor(invoiceDay)) ? todayDate : invoiceDay;
    final dueLabel = invoiceDueDate != null ? ' (venc. ${_dayMonth.format(invoiceDueDate!)})' : '';
    final loans = <P2PLoan>[];
    for (final entry in loanLines.entries) {
      final loanId = newId();
      for (final line in entry.value) {
        records.add(
          ImportLineRecord(
            line: line,
            outcome: LineOutcome.created,
            title: _titleOf(line),
            loanId: loanId,
          ),
        );
      }
      loans.add(
        P2PLoan(
          id: loanId,
          title: '${source.name}$dueLabel — ${memberNames[entry.key] ?? 'morador'}',
          description: entry.value
              .map((line) => '${_titleOf(line)} ${effectiveAmountOf(line).formatted}')
              .join('; '),
          totalAmount: Money(entry.value.fold<int>(0, (acc, line) => acc + effectiveAmountOf(line).cents)),
          lenderMemberId: lenderId,
          borrowerMemberId: entry.key,
          installmentsCount: 1,
          createdAt: today,
          // Quem deve paga junto com a fatura
          firstDueDate: invoiceDueDate ?? today.add(const Duration(days: 30)),
          // Cartão da Casa: a fatura sai do Caixa do ciclo dela (ou do atual,
          // como ajuste, se esse ciclo já fechou)
          houseFunding: isHouseCard ? HouseLoanFunding.cycle : null,
          fundedOn: isHouseCard ? loanFundedOn : null,
        ),
      );
    }

    final updates = <HouseExpense>[];
    final extraActions = <({ImportedStatementLine line, ExtraAction action})>[];
    final refundedExpenses = <String, int>{};
    for (final line in lines) {
      final status = statusOf(line);
      // Pessoal, de terceiros, ignorada, pagamento, estorno e entrada: ficam só no histórico
      final leftOut = status == LineStatus.informational ||
          status == LineStatus.ignored ||
          (status == LineStatus.newLine &&
              (line.destination == LineDestination.cardOwnerPersonal ||
                  line.destination == LineDestination.thirdParty));
      final refundTarget = chosenRefund(line);
      if (refundTarget != null) {
        records.add(
          ImportLineRecord(
            line: line,
            outcome: LineOutcome.linked,
            expenseId: refundTarget.expense?.id,
          ),
        );
        final expense = refundTarget.expense;
        if (expense != null) refundedExpenses[expense.id] = (refundedExpenses[expense.id] ?? 0) + line.amount.cents;
        continue;
      }
      if (leftOut && !_wasImported(line)) {
        final extra = chosenExtra(line);
        if (extra != null) extraActions.add((line: line, action: extra));
        records.add(
          ImportLineRecord(
            line: line,
            outcome: extra != null ? LineOutcome.linked : LineOutcome.ignored,
          ),
        );
      }
      if (status != LineStatus.linked) continue;

      final match = matches[line.id]!;
      final expense = match.expense;
      records.add(
        ImportLineRecord(line: line, outcome: LineOutcome.linked, expenseId: expense.id),
      );
      if (expense.settledAt != null) continue;

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
            paidOutOfPocket: waitsForInvoice ? false : outOfPocket,
            dueDate: source.isCreditCard ? invoiceDueDate : null,
          ),
        );
      }
    }

    // Despesas já lançadas que receberam estorno: abatidas ou, se cobertas por
    // inteiro, excluídas
    final deletions = <HouseExpense>[];
    for (final entry in refundedExpenses.entries) {
      final expense = knownExpenses.firstWhere((e) => e.id == entry.key);
      final updatedIndex = updates.indexWhere((e) => e.id == expense.id);
      final base = updatedIndex >= 0 ? updates[updatedIndex] : expense;
      final remaining = base.amount.cents - entry.value;
      if (updatedIndex >= 0) updates.removeAt(updatedIndex);
      if (remaining <= 0) {
        deletions.add(expense);
      } else {
        updates.add(base.copyWith(amount: Money(remaining)));
      }
    }

    return ImportPlan(
      newExpenses: newExpenses,
      expenseUpdates: updates,
      expenseDeletions: deletions,
      loans: loans,
      skippedClosedCycle: skipped,
      lineRecords: records,
      extraActions: extraActions,
      invoicePayment: waitsForInvoice && invoiceDueDate != null && invoicePaidAt != null
          ? (dueDate: invoiceDueDate!, paidAt: invoicePaidAt!, paidByHouse: invoicePaidByHouse)
          : null,
    );
  }
}
