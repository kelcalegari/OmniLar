import '../../../finance/domain/services/pending_payment.dart';
import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/domain/value_objects/financial_cycle.dart';
import '../../../../core/domain/value_objects/money.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/uuid.dart';
import '../../../../core/widgets/money_input_field.dart';
import '../../../../core/widgets/responsive_container.dart';
import '../../../auth/domain/repositories/auth_repository.dart';
import '../../../finance/domain/entities/card_invoice.dart';
import '../../../finance/domain/entities/contribution.dart';
import '../../../finance/domain/entities/house_expense.dart';
import '../../../finance/domain/entities/house_member.dart';
import '../../../finance/domain/entities/payment_method.dart';
import '../../../finance/domain/repositories/finance_repository.dart';
import '../../../finance/presentation/cubit/finance_cubit.dart';
import '../../../finance/presentation/cubit/finance_state.dart';
import '../../../p2p/domain/repositories/p2p_repository.dart';
import '../../../p2p/presentation/cubit/p2p_cubit.dart';
import '../../../settlement/domain/entities/settlement_summary.dart';
import '../../../settlement/domain/repositories/settlement_repository.dart';
import '../../data/csv_mapping_store.dart';
import '../../data/import_ai_service.dart';
import '../../data/import_draft_store.dart';
import '../../domain/services/import_draft_codec.dart';
import '../../domain/entities/csv_mapping.dart';
import '../widgets/csv_mapping_dialog.dart';
import '../../domain/entities/imported_statement_line.dart';
import '../../domain/repositories/import_repository.dart';
import '../../domain/services/import_session.dart';
import '../../domain/services/installment_matcher.dart';
import '../../domain/services/statement_extras.dart';
import '../../domain/services/statement_matcher.dart';
import '../../domain/services/statement_parser.dart';
import '../../domain/services/statement_text.dart';

/// Importa a fatura de um cartão ou o extrato de uma conta: o usuário escolhe
/// a origem e o arquivo, revisa o que já estava lançado e para onde vai cada
/// linha nova, e só então o app grava.
class ImportPage extends StatefulWidget {
  /// Cartão ou conta já escolhido por quem abriu a página.
  final String? initialSourceId;

  const ImportPage({super.key, this.initialSourceId});

  @override
  State<ImportPage> createState() => _ImportPageState();
}

class _ImportPageState extends State<ImportPage> {
  static final _dayFormat = DateFormat('dd/MM/yyyy');
  static final _shortDay = DateFormat('dd/MM');

  String? _sourceId;

  /// Revisão em andamento. Toda mudança dela é guardada como rascunho.
  ImportSession? _sessionValue;
  ImportSession? get _session => _sessionValue;
  set _session(ImportSession? session) {
    _sessionValue = session;
    _scheduleDraftSave();
  }

  /// Rascunho de outra hora para o cartão ou conta escolhido (sem revisão aberta).
  ImportDraft? _draft;
  Timer? _draftTimer;
  bool _busy = false;

  /// Um arquivo está sendo arrastado sobre a página.
  bool _dragging = false;
  String? _fileWarning;
  Set<FinancialCycle> _closedCycles = const {};
  ClosedCyclePolicy _closedCyclePolicy = ClosedCyclePolicy.adjustInCurrentCycle;
  LineStatus? _filter;
  String? _failure;
  String? _resultMessage;
  List<String> _resultWarnings = const [];

  /// Linhas marcadas para a edição em lote (pelo id).
  Set<String> _selected = const {};
  List<ImportBatch> _history = const [];

  /// Regras aprendidas do cartão ou conta escolhido.
  List<ImportRule> _rules = const [];

  /// CSV aberto na revisão, para poder ajustar as colunas depois.
  ({String content, String fileName})? _csv;

  FinanceCubit get _finance => context.read<FinanceCubit>();

  @override
  void initState() {
    super.initState();
    _sourceId = widget.initialSourceId;
    // Aberta direto pelo endereço: a casa pode não estar carregada ainda
    if (_finance.state.paymentMethods.isEmpty) _finance.loadCycleData();
    _loadHistory();
    if (_sourceId != null) {
      _loadRules(_sourceId!);
      _loadDraft(_sourceId!);
    }
  }

  @override
  void dispose() {
    // O que estava esperando para ser guardado vai agora
    if (_draftTimer?.isActive ?? false) {
      _draftTimer!.cancel();
      _saveDraftNow();
    }
    super.dispose();
  }

  void _scheduleDraftSave() {
    if (_sessionValue == null) return;
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 600), _saveDraftNow);
  }

  void _saveDraftNow() {
    final session = _sessionValue;
    if (session == null) return;
    sl<ImportDraftStore>().save(
      session.source.id,
      session.fileName,
      ImportDraftCodec.toJson(session),
    );
  }

  Future<void> _loadDraft(String sourceId) async {
    final draft = await sl<ImportDraftStore>().load(sourceId);
    if (!mounted || _sourceId != sourceId) return;
    setState(() => _draft = draft);
  }

  Future<void> _resumeDraft(PaymentMethod source) async {
    final draft = _draft;
    if (draft == null) return;
    final session = ImportDraftCodec.fromJson(draft.session, source);
    if (session == null) {
      _showMessage(
        'Não foi possível retomar esta revisão. Importe o arquivo de novo.',
        error: true,
      );
      await _discardDraft(source);
      return;
    }
    setState(() {
      _session = session;
      _draft = null;
      _csv = null;
      _fileWarning = null;
      _failure = null;
      _resultMessage = null;
      _resultWarnings = const [];
      _selected = const {};
      _filter = null;
    });
    // Despesas parecidas, ciclos fechados e importações anteriores são buscados de novo
    await _refresh();
  }

  Future<void> _discardDraft(PaymentMethod source) async {
    _draftTimer?.cancel();
    setState(() => _draft = null);
    // A tela não espera o armazenamento do aparelho
    unawaited(sl<ImportDraftStore>().clear(source.id));
  }

  Future<List<ImportRule>> _loadRules(String sourceId) async {
    var rules = const <ImportRule>[];
    try {
      rules = await sl<ImportRepository>().getRules(sourceId);
    } catch (_) {
      // Sem as regras a importação continua funcionando
    }
    if (mounted && _sourceId == sourceId) setState(() => _rules = rules);
    return rules;
  }

  Future<void> _loadHistory() async {
    try {
      final history = await sl<ImportRepository>().getHistory();
      if (mounted) setState(() => _history = history);
    } catch (_) {
      // Sem o histórico a importação continua funcionando
    }
  }

  static bool _canImport(PaymentMethod method) =>
      method.type == PaymentMethodType.card ||
      method.type == PaymentMethodType.account;

  PaymentMethod? _sourceOf(FinanceState state) {
    final sources = state.paymentMethods.where(_canImport).toList();
    return sources.where((p) => p.id == _sourceId).firstOrNull ??
        // Cartão ou conta que a casa escolheu abrir (0100)
        sources
            .where(
              (p) => p.id == state.houseSettings.importDefaults.paymentMethodId,
            )
            .firstOrNull ??
        (sources.length == 1 ? sources.first : null);
  }

  String _memberName(String? memberId) {
    final member = _finance.state.members
        .where((m) => m.id == memberId)
        .firstOrNull;
    return member?.name.split(' ').first ?? 'morador';
  }

  void _showMessage(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? AppColors.debtRed : null,
      ),
    );
  }

  // --- Leitura do arquivo ---

  Future<void> _pickFile(PaymentMethod source) async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: _allowedExtensions,
      );
      if (files.isEmpty) return;

      final file = files.first;
      await _readFile(source, file.name, await file.readAsBytes());
    } catch (e) {
      _showMessage('Erro ao importar arquivo: $e', error: true);
    }
  }

  static final _allowedExtensions = [
    'ofx',
    'csv',
    'txt',
    ...ImportAiService.mimeTypes.keys,
  ];

  /// Arquivo solto sobre a página (navegador e computador).
  Future<void> _onDrop(List<DropItem> files, FinanceState state) async {
    setState(() => _dragging = false);
    if (files.isEmpty || _busy) return;
    final source = _sourceOf(state);
    if (source == null) {
      _showMessage(
        'Escolha primeiro o cartão ou a conta de origem.',
        error: true,
      );
      return;
    }
    final file = files.first;
    final extension = file.name.contains('.')
        ? file.name.split('.').last.toLowerCase()
        : '';
    if (!_allowedExtensions.contains(extension)) {
      _showMessage(
        'Formato não aceito. Use OFX, CSV, PDF ou foto da fatura.',
        error: true,
      );
      return;
    }
    try {
      await _readFile(source, file.name, await file.readAsBytes());
    } catch (e) {
      _showMessage('Erro ao importar arquivo: $e', error: true);
    }
  }

  Future<void> _readFile(
    PaymentMethod source,
    String fileName,
    Uint8List bytes,
  ) async {
    final sourceType = source.isCreditCard
        ? StatementSourceType.creditCard
        : StatementSourceType.bankAccount;

    // PDF e foto não têm estrutura: quem lê é a IA, e a revisão confere
    final mimeType = ImportAiService.mimeTypeOf(fileName);
    if (mimeType != null) {
      await _readWithAi(source, fileName, bytes, mimeType, sourceType);
      return;
    }

    final content = StatementParser.decodeBytes(bytes);
    final isOfx =
        fileName.toLowerCase().endsWith('.ofx') ||
        content.contains('<STMTTRN>');
    if (!isOfx) {
      await _importCsv(source, fileName, content, sourceType);
      return;
    }

    final lines = StatementParser.parseOfx(content, source: sourceType);
    if (lines.isEmpty) {
      _showMessage(
        'Nenhum lançamento encontrado no arquivo selecionado.',
        error: true,
      );
      return;
    }

    String? warning;
    if (isOfx &&
        StatementParser.isCreditCardOfx(content) != source.isCreditCard) {
      warning = source.isCreditCard
          ? 'Este arquivo parece ser o extrato de uma conta, e não a fatura de um cartão. Confira a origem escolhida.'
          : 'Este arquivo parece ser a fatura de um cartão, e não o extrato de uma conta. Confira a origem escolhida.';
    }
    _csv = null;
    await _start(source, fileName, lines, warning: warning);
  }

  /// CSV: lê com as colunas guardadas para este cartão ou conta; sem elas,
  /// tenta reconhecer sozinho. Se não achar nada, pergunta ao usuário.
  Future<void> _importCsv(
    PaymentMethod source,
    String fileName,
    String content,
    StatementSourceType sourceType,
  ) async {
    final saved = await sl<CsvMappingStore>().load(source.id);
    var lines = saved != null
        ? StatementParser.parseCsvWithMapping(
            content,
            saved,
            source: sourceType,
          )
        : const <ImportedStatementLine>[];
    if (lines.isEmpty)
      lines = StatementParser.parseCsv(content, source: sourceType);
    if (!mounted) return;

    if (lines.isEmpty) {
      _showMessage(
        'Não reconheci as colunas deste arquivo. Diga o que é cada uma.',
      );
      await _mapCsvColumns(
        source,
        fileName,
        content,
        sourceType,
        initial: saved,
      );
      return;
    }
    _csv = (content: content, fileName: fileName);
    await _start(source, fileName, lines);
  }

  /// Abre a escolha das colunas; com a resposta, lê o arquivo de novo e guarda
  /// o mapeamento para os próximos arquivos deste cartão ou conta.
  Future<void> _mapCsvColumns(
    PaymentMethod source,
    String fileName,
    String content,
    StatementSourceType sourceType, {
    CsvMapping? initial,
  }) async {
    final mapping = await CsvMappingDialog.show(
      context,
      content: content,
      fileName: fileName,
      initial: initial ?? StatementParser.guessCsvMapping(content),
      source: sourceType,
    );
    if (mapping == null || !mounted) return;

    final lines = StatementParser.parseCsvWithMapping(
      content,
      mapping,
      source: sourceType,
    );
    if (lines.isEmpty) {
      _showMessage(
        'Nenhuma linha com data e valor nessas colunas.',
        error: true,
      );
      return;
    }
    await sl<CsvMappingStore>().save(source.id, mapping);
    if (!mounted) return;
    _csv = (content: content, fileName: fileName);
    await _start(source, fileName, lines);
  }

  Future<void> _readWithAi(
    PaymentMethod source,
    String fileName,
    Uint8List bytes,
    String mimeType,
    StatementSourceType sourceType,
  ) async {
    setState(() => _busy = true);
    _showMessage(
      'Lendo "$fileName" com IA. Isso pode levar alguns segundos...',
    );
    final AiStatementReading reading;
    try {
      reading = await sl<ImportAiService>().readFile(
        bytes: bytes,
        mimeType: mimeType,
        source: sourceType,
      );
    } catch (e) {
      if (mounted) setState(() => _busy = false);
      _showMessage('$e', error: true);
      return;
    }
    if (!mounted) return;
    setState(() => _busy = false);

    final warning = switch (reading.sumMatchesTotal) {
      false =>
        'Lido por IA: a soma das linhas (${reading.linesSum.format()}) não bate com o total impresso '
            '(${reading.printedTotal!.format()}). Pode faltar ou sobrar alguma linha: confira com o arquivo.',
      true =>
        'Lido por IA: a soma das linhas bate com o total impresso. Confira as linhas antes de confirmar.',
      null =>
        'Lido por IA: o arquivo não traz um total para conferir. Confira as linhas antes de confirmar.',
    };
    _csv = null;
    await _start(
      source,
      fileName,
      reading.lines,
      warning: warning,
      dueDate: reading.dueDate,
    );
  }

  /// Informa que a fatura importada já foi paga: data e, se o cartão tem
  /// dono, com que dinheiro.
  Future<void> _pickInvoicePayment() async {
    final session = _session;
    if (session == null) return;
    final picked = await showDatePicker(
      context: context,
      initialDate: session.invoicePaidAt ?? DateTime.now(),
      firstDate: DateTime(2015, 1, 1),
      lastDate: DateTime(DateTime.now().year + 2, 12, 31),
      helpText: 'Dia em que a fatura foi paga',
    );
    if (picked == null || !mounted) return;

    final options = invoicePaymentOptions(
      session.source,
      _finance.state.paymentMethods,
      memberNames: {
        for (final m in _finance.state.members) m.id: m.name.split(' ').first,
      },
      usualPayerId: session.source.usualInvoicePayerId,
    );
    var byHouse = options.first.byHouse;
    if (options.length > 1) {
      final choice = await showDialog<InvoicePaymentOption>(
        context: context,
        builder: (dialogContext) => SimpleDialog(
          title: const Text(
            'Com que meio foi paga?',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          children: [
            for (final option in options)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(dialogContext, option),
                child: Text(
                  option.byHouse
                      ? '${option.label}: sem reembolso; o que não é da casa vira dívida com o Caixa'
                      : '${option.label}: reembolsado no fechamento',
                ),
              ),
          ],
        ),
      );
      if (choice == null || !mounted) return;
      byHouse = choice.byHouse;
    }
    _update(_session!.withInvoicePayment(picked, byHouse: byHouse));
  }

  /// Pede à IA nome e categoria para as linhas da Casa que ainda não têm.
  Future<void> _suggestWithAi() async {
    final session = _session;
    if (session == null) return;
    final targets = [
      for (final line in session.newLines)
        if (line.destination == LineDestination.house &&
            line.categoryId == null)
          line,
    ];
    if (targets.isEmpty) return;

    setState(() => _busy = true);
    try {
      final suggestions = await sl<ImportAiService>().classify(
        lines: targets,
        categories: _finance.state.categories,
      );
      if (!mounted) return;
      var updated = _session ?? session;
      var applied = 0;
      for (final line in updated.lines) {
        final suggestion = suggestions[line.id];
        if (suggestion == null || line.categoryId != null) continue;
        updated = updated.withLine(
          line.copyWith(
            // O nome que o usuário já deu vale mais que o da IA
            title: line.title ?? suggestion.title,
            categoryId: suggestion.categoryId,
          ),
        );
        if (suggestion.categoryId != null) applied++;
      }
      setState(() => _session = updated);
      _showMessage(
        applied == 0
            ? 'A IA não soube sugerir categoria para essas linhas.'
            : '$applied ${applied == 1 ? 'linha ganhou' : 'linhas ganharam'} categoria sugerida. Confira antes de confirmar.',
      );
    } catch (e) {
      _showMessage('$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Fatura de exemplo do modo demo, para ver a tela sem ter um arquivo.
  Future<void> _useSample(PaymentMethod source) async {
    final now = DateTime.now();
    ImportedStatementLine line(
      int index,
      int daysAgo,
      String description,
      int cents,
    ) {
      final date = now.subtract(Duration(days: daysAgo));
      return ImportedStatementLine(
        id: 'sample_$index',
        date: date,
        description: description,
        amount: Money(cents),
        signature:
            '${StatementParser.signatureContent(date, cents, description)}#1',
      );
    }

    _csv = null;
    await _start(source, 'fatura_exemplo.csv', [
      line(1, 2, 'PAO DE ACUCAR LJ 1234', 48560),
      line(2, 4, 'ZARA SHOPPING', 17990),
      line(3, 6, 'FARM RIO', 32000),
      line(4, 8, 'STEAM GAMES', 15000),
      line(5, 10, 'ENEL ENERGIA ELETRICA', 21000),
    ]);
  }

  Future<void> _start(
    PaymentMethod source,
    String fileName,
    List<ImportedStatementLine> lines, {
    String? warning,
    DateTime? dueDate,
  }) async {
    final currentUserId = sl<AuthRepository>().currentUser?.id;
    final members = _finance.state.members;
    // Quem costuma pagar a fatura (0100) abre como pagador; trocar na tela vale mais
    final usualPayer = members.any((m) => m.id == source.usualInvoicePayerId)
        ? source.usualInvoicePayerId
        : null;
    final payer =
        usualPayer ??
        source.ownerMemberId ??
        currentUserId ??
        (members.isNotEmpty ? members.first.id : '');

    _sourceId = source.id;
    _draft = null;
    final rules = await _loadRules(source.id);
    if (!mounted) return;
    final state = _finance.state;

    setState(() {
      _session =
          ImportSession.start(
            source: source,
            fileName: fileName,
            lines: lines,
            payerMemberId: payer,
            matching: state.houseSettings.importMatching,
            defaults: state.houseSettings.importDefaults,
          ).withRules(
            rules,
            memberIds: {for (final m in state.members) m.id},
            categoryIds: {for (final c in state.categories) c.id},
          );
      // O vencimento impresso na fatura vale mais que o calculado pelas compras
      if (source.isCreditCard && dueDate != null) {
        _session = _session!.withInvoiceDueDate(dueDate);
      }
      _sourceId = source.id;
      _fileWarning = warning;
      _failure = null;
      _resultMessage = null;
      _resultWarnings = const [];
      _selected = const {};
      _filter = null;
    });
    await _refresh(suggestCategories: true);
  }

  /// Busca no app o que pode ser igual às linhas e quais ciclos já fecharam.
  Future<void> _refresh({bool suggestCategories = false}) async {
    final session = _session;
    if (session == null) return;
    final p2pCubit = context.read<P2PCubit>();
    setState(() => _busy = true);

    final schedule = _finance.cycleSchedule;
    final byId = <String, HouseExpense>{};
    final closed = <FinancialCycle>{};
    try {
      final repository = sl<FinanceRepository>();
      for (final cycle in session.cyclesToSearch(schedule)) {
        for (final expense in await repository.getExpensesForCycle(cycle)) {
          byId[expense.id] = expense;
        }
      }
    } catch (e) {
      _showMessage(
        'Não foi possível comparar com os lançamentos do app: $e',
        error: true,
      );
    }

    var imported = session.importedSignatures;
    try {
      imported = await sl<ImportRepository>().importedSignatures(
        session.source.id,
      );
    } catch (_) {
      // Sem a resposta, vale a comparação com as despesas do app
    }

    var plans = session.installmentPlans;
    if (session.source.isCreditCard) {
      try {
        plans = await sl<ImportRepository>().installmentPlans(
          session.source.id,
        );
      } catch (_) {
        // Sem a resposta, cada parcela é tratada como compra nova
      }
    }

    final settlements = sl<SettlementRepository>();
    for (final cycle in session.countingCycles(schedule)) {
      try {
        final summary = await settlements.getSettlementSummary(cycle);
        if (summary.status == SettlementStatus.settled) closed.add(cycle);
      } catch (_) {
        // Sem a resposta, o banco ainda recusa o que cair em ciclo fechado
      }
    }

    // Extrato de conta: o que as linhas que não são compra podem ser
    final openInvoices = <CardInvoice>[];
    final cards = _finance.state.paymentMethods
        .where((p) => p.isCreditCard)
        .toList();
    if (!session.source.isCreditCard) {
      try {
        for (final card in cards) {
          openInvoices.addAll(
            await sl<FinanceRepository>().getOpenCardInvoices(card.id),
          );
        }
        await p2pCubit.loadLoans();
      } catch (_) {
        // Sem essas respostas as linhas só ficam sem sugestão
      }
    }

    if (!mounted) return;
    // A revisão pode ter mudado enquanto a busca corria: parte da atual
    final current = _session ?? session;
    final houseSettings = _finance.state.houseSettings;
    var updated = current
        .withParams(
          matching: houseSettings.importMatching,
          defaults: houseSettings.importDefaults,
        )
        .withImportedSignatures(imported)
        .withInstallmentPlans(
          plans,
          memberIds: {for (final m in _finance.state.members) m.id},
          categoryIds: {for (final c in _finance.state.categories) c.id},
        )
        .withExpenses(byId.values.toList())
        .withExtraOptions(
          StatementExtras.optionsFor(
            lines: current.lines,
            source: current.source,
            payerMemberId: current.payerMemberId,
            members: _finance.state.members,
            cards: cards,
            openInvoices: openInvoices,
            history: _history,
            loans: p2pCubit.state.allLoans,
            vaults: _finance.state.savingsVaults,
            matching: houseSettings.importMatching,
          ),
        );
    if (suggestCategories) {
      updated = updated.withSuggestedCategories(
        categories: _finance.state.categories,
        history: byId.values.toList(),
      );
    }
    setState(() {
      _session = updated;
      _closedCycles = closed;
      _busy = false;
    });
  }

  void _update(ImportSession session) => setState(() => _session = session);

  /// Copia destino, categoria e devedor de [from] para [target].
  static ImportedStatementLine _sameClassification(
    ImportedStatementLine target,
    ImportedStatementLine from,
  ) => target.copyWith(
    destination: from.destination,
    categoryId: from.categoryId,
    assignedMemberId: from.assignedMemberId,
    clearAssignedMember: from.assignedMemberId == null,
  );

  /// Grava a decisão de uma linha e oferece repetir nas outras do mesmo lugar.
  void _classify(ImportSession session, ImportedStatementLine changed) {
    final updated = session.withLine(changed);
    _update(updated);

    final others = updated
        .similarLines(changed)
        .where(
          (other) =>
              other.destination != changed.destination ||
              other.categoryId != changed.categoryId ||
              other.assignedMemberId != changed.assignedMemberId,
        );
    if (others.isEmpty) return;

    final ids = {for (final other in others) other.id};
    final name = StatementText.cleanTitle(changed.description);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 8),
          content: Text(
            ids.length == 1
                ? 'Há outra linha de $name.'
                : 'Há outras ${ids.length} linhas de $name.',
          ),
          action: SnackBarAction(
            label: 'Aplicar a todas',
            onPressed: () {
              final current = _session;
              if (current == null) return;
              final source = current.lines
                  .where((l) => l.id == changed.id)
                  .firstOrNull;
              if (source == null) return;
              _update(
                current.withLines(
                  ids,
                  (line) => _sameClassification(line, source),
                ),
              );
            },
          ),
        ),
      );
  }

  // Destinos de uma linha no seletor: a Casa, cada outro morador (que passa a
  // dever para quem paga), o gasto pessoal de quem paga, ou ignorar.
  static const _houseKey = 'house';
  static const _personalKey = 'personal';
  static const _ignoredKey = 'ignored';
  static const _thirdPartyKey = 'third_party';
  static const _loanPrefix = 'loan:';

  /// Opção marcada para [line]. Null quando é empréstimo ainda sem devedor.
  static String? _destinationKeyOf(
    ImportedStatementLine line,
    List<HouseMember> debtors, {
    bool allowPersonal = true,
  }) {
    switch (line.destination) {
      case LineDestination.house:
        return _houseKey;
      case LineDestination.cardOwnerPersonal:
        return allowPersonal ? _personalKey : null;
      case LineDestination.ignored:
        return _ignoredKey;
      case LineDestination.thirdParty:
        return _thirdPartyKey;
      case LineDestination.splitP2P:
        return debtors.any((m) => m.id == line.assignedMemberId)
            ? '$_loanPrefix${line.assignedMemberId}'
            : null;
    }
  }

  static ImportedStatementLine _withDestinationKey(
    ImportedStatementLine line,
    String key,
  ) {
    if (key.startsWith(_loanPrefix)) {
      return line.copyWith(
        destination: LineDestination.splitP2P,
        assignedMemberId: key.substring(_loanPrefix.length),
      );
    }
    return line.copyWith(
      destination: switch (key) {
        _personalKey => LineDestination.cardOwnerPersonal,
        _ignoredKey => LineDestination.ignored,
        _thirdPartyKey => LineDestination.thirdParty,
        _ => LineDestination.house,
      },
      clearAssignedMember: true,
    );
  }

  static List<DropdownMenuItem<String>> _destinationItems(
    List<HouseMember> debtors,
    String? payerName, {
    required bool colored,
  }) {
    TextStyle style(Color color, {bool bold = false}) => TextStyle(
      fontSize: 12,
      color: colored ? color : null,
      fontWeight: colored && bold ? FontWeight.bold : null,
    );

    return [
      DropdownMenuItem(
        value: _houseKey,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Casa', style: style(AppColors.primary, bold: true)),
            const SizedBox(width: 4),
            Text('(gasto)', style: style(Colors.grey)),
          ],
        ),
      ),
      for (final member in debtors)
        DropdownMenuItem(
          value: '$_loanPrefix${member.id}',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${member.name.split(' ').first} deve',
                style: style(AppColors.debtRed, bold: true),
              ),
              const SizedBox(width: 4),
              Text('(empréstimo)', style: style(Colors.grey)),
            ],
          ),
        ),
      if (payerName != null)
        DropdownMenuItem(
          value: _personalKey,
          child: Text('Pessoal de $payerName', style: style(Colors.blueGrey)),
        ),
      DropdownMenuItem(
        value: _thirdPartyKey,
        child: Text('Pago por terceiros', style: style(Colors.teal)),
      ),
      DropdownMenuItem(
        value: _ignoredKey,
        child: Text('Ignorar', style: style(Colors.grey)),
      ),
    ];
  }

  /// Aplica uma mudança às linhas marcadas.
  void _bulk(
    ImportedStatementLine Function(ImportedStatementLine line) change,
  ) {
    final session = _session;
    if (session == null) return;
    _update(session.withLines(_selected, change));
  }

  Future<void> _pickDueDate() async {
    final session = _session!;
    final initial = session.invoiceDueDate ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(
        [
          initial.year - 5,
          DateTime.now().year - 10,
          2015,
        ].reduce((a, b) => a < b ? a : b),
        1,
        1,
      ),
      lastDate: DateTime(
        [
          initial.year + 5,
          DateTime.now().year + 10,
          2035,
        ].reduce((a, b) => a > b ? a : b),
        12,
        31,
      ),
      helpText: 'Vencimento da fatura',
    );
    if (picked == null || !mounted) return;
    _update(_session!.withInvoiceDueDate(picked));
    await _refresh();
  }

  /// Divide uma compra em duas: o usuário diz o valor da primeira parte e a
  /// segunda fica com o resto.
  Future<void> _splitLine(ImportedStatementLine line) async {
    var first = Money(line.amount.cents ~/ 2);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final valid = first.cents > 0 && first.cents < line.amount.cents;
          return AlertDialog(
            title: const Text(
              'Dividir em duas partes',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${StatementText.cleanTitle(line.description)} • ${line.amount.format()}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Cada parte pode ir para um destino diferente: parte da Casa, parte de um morador, parte pessoal.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 12),
                MoneyInputField(
                  key: const Key('import_split_amount'),
                  label: 'Valor da primeira parte',
                  initialValue: first,
                  autoFocus: true,
                  onChanged: (value) => setDialogState(() => first = value),
                ),
                const SizedBox(height: 8),
                Text(
                  valid
                      ? 'Segunda parte: ${(line.amount - first).format()}'
                      : 'A primeira parte precisa ser maior que zero e menor que ${line.amount.format()}.',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: valid ? null : AppColors.debtRed,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                key: const Key('import_split_confirm'),
                onPressed: valid
                    ? () => Navigator.pop(dialogContext, true)
                    : null,
                child: const Text('Dividir'),
              ),
            ],
          );
        },
      ),
    );
    if (confirmed != true || !mounted || _session == null) return;
    setState(
      () => _selected = {
        for (final id in _selected)
          if (id != line.id) id,
      },
    );
    _update(_session!.splitLine(line.id, first));
  }

  /// "Parte 1 de 2 de R$ X", com o atalho para juntar as partes de novo.
  Widget _splitInfo(ImportSession session, ImportedStatementLine line) {
    final parts = session.partsOf(line.splitFrom!);
    final index = parts.indexWhere((p) => p.id == line.id) + 1;
    final total = Money(parts.fold<int>(0, (acc, p) => acc + p.amount.cents));
    return Row(
      children: [
        Text(
          'Parte $index de ${parts.length} de ${total.format()}',
          style: const TextStyle(
            fontSize: 11,
            color: AppColors.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 4),
        InkWell(
          onTap: _busy
              ? null
              : () => _update(session.mergeSplit(line.splitFrom!)),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Text(
              'Juntar',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.primary,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _editLine(ImportedStatementLine line) async {
    final controller = TextEditingController(
      text: line.title ?? StatementText.cleanTitle(line.description),
    );
    var date = line.date;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text(
            'Editar linha',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                line.description,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  labelText: 'Nome do lançamento',
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.event_rounded, size: 18),
                label: Text('Compra em ${_dayFormat.format(date)}'),
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: date,
                    firstDate: DateTime(
                      [
                        date.year - 5,
                        DateTime.now().year - 10,
                        2015,
                      ].reduce((a, b) => a < b ? a : b),
                      1,
                      1,
                    ),
                    lastDate: DateTime(
                      [
                        date.year + 5,
                        DateTime.now().year + 2,
                        2035,
                      ].reduce((a, b) => a > b ? a : b),
                      12,
                      31,
                    ),
                  );
                  if (picked != null) setDialogState(() => date = picked);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
    final title = controller.text.trim();
    controller.dispose();
    if (saved != true || !mounted || _session == null) return;

    final dateChanged = date != line.date;
    final current = _session!.lines.firstWhere((l) => l.id == line.id);
    _update(_session!.withLine(current.copyWith(title: title, date: date)));
    // Outra data pode casar com outra despesa ou cair em outro ciclo
    if (dateChanged) await _refresh();
  }

  // --- Gravação ---

  Future<void> _confirm() async {
    final session = _session!;
    final state = _finance.state;
    final plan = session.buildPlan(
      members: state.members,
      categories: state.categories,
      schedule: _finance.cycleSchedule,
      closedCycles: _closedCycles,
      closedCyclePolicy: _closedCyclePolicy,
    );
    final p2pCubit = context.read<P2PCubit>();

    setState(() {
      _busy = true;
      _failure = null;
    });

    try {
      // Tudo ou nada: se algo falha, nenhuma linha é gravada
      await sl<ImportRepository>().confirmImport(session, plan);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _failure = '$e';
      });
      return;
    }

    // O que foi decidido para cada estabelecimento vale para a próxima fatura
    try {
      await sl<ImportRepository>().saveRules(
        session.source.id,
        session.rulesToLearn(),
      );
    } catch (_) {
      // Regra não gravada não desfaz a importação
    }
    await _loadRules(session.source.id);

    // Movimentos do extrato que não são despesa: cada um é gravado à parte, e
    // o que falhar aparece como aviso (a importação em si já está gravada)
    final warnings = <String>[];
    // Despesas já lançadas que um estorno cobriu por inteiro
    for (final expense in plan.expenseDeletions) {
      try {
        await sl<FinanceRepository>().deleteExpense(expense.id);
      } catch (e) {
        warnings.add('Excluir "${expense.title}" pelo estorno: $e');
      }
    }

    final invoicePayment = plan.invoicePayment;
    if (invoicePayment != null) {
      try {
        await sl<FinanceRepository>().payCardInvoice(
          paymentMethodId: session.source.id,
          invoiceDueDate: invoicePayment.dueDate,
          paidAt: invoicePayment.paidAt,
          paidByHouse: invoicePayment.paidByHouse,
        );
      } catch (e) {
        warnings.add('Pagamento da fatura: $e');
      }
    }
    final finance = sl<FinanceRepository>();
    for (final extra in plan.extraActions) {
      final action = extra.action;
      try {
        switch (action.type) {
          case ExtraActionType.payInvoice:
            await finance.payCardInvoice(
              paymentMethodId: action.paymentMethodId!,
              invoiceDueDate: action.invoiceDueDate!,
              paidAt: extra.line.date,
              // Saiu da conta da casa: pago pelo Caixa; da conta de um morador: por ele
              paidByHouse: session.source.ownerMemberId == null,
            );
          case ExtraActionType.contribution:
            await finance.addContribution(
              Contribution(
                id: generateUuidV4(),
                memberId: action.memberId!,
                amount: extra.line.amount,
                date: extra.line.date,
                paymentMethodId: session.source.id,
              ),
            );
          case ExtraActionType.loanPayment:
            await sl<P2PRepository>().payLoan(
              action.loanId!,
              extra.line.amount,
            );
          case ExtraActionType.thirdPartyReceipt:
            await finance.registerThirdPartyReceipt(
              payerName: StatementText.cleanTitle(extra.line.description),
              amount: extra.line.amount,
              receivedOn: extra.line.date,
              vaultId: action.vaultId!,
              description: 'Entrada importada de ${session.source.name}',
            );
        }
      } catch (e) {
        warnings.add('${action.label}: $e');
      }
    }

    await _finance.loadCycleData();
    await p2pCubit.loadLoans();
    await _loadHistory();
    if (!mounted) return;

    final extrasDone = plan.extraActions.length - warnings.length;
    final linked =
        session.countOf(LineStatus.linked) +
        session.countOf(LineStatus.alreadyImported);
    final summary = [
      '${plan.newExpenses.length} ${plan.newExpenses.length == 1 ? 'despesa lançada' : 'despesas lançadas'}',
      if (plan.loans.isNotEmpty)
        '${plan.loans.length} ${plan.loans.length == 1 ? 'empréstimo criado' : 'empréstimos criados'}',
      if (extrasDone > 0)
        '$extrasDone ${extrasDone == 1 ? 'movimento registrado' : 'movimentos registrados'}',
      if (linked > 0)
        '$linked já ${linked == 1 ? 'estava lançada' : 'estavam lançadas'}',
      if (plan.skippedClosedCycle.isNotEmpty)
        '${plan.skippedClosedCycle.length} de ciclo fechado ${plan.skippedClosedCycle.length == 1 ? 'ficou' : 'ficaram'} de fora',
    ].join(' • ');

    _draftTimer?.cancel();
    unawaited(sl<ImportDraftStore>().clear(session.source.id));
    setState(() {
      _session = null;
      _busy = false;
      _selected = const {};
      _resultMessage = '${session.fileName} importado: $summary.';
      _resultWarnings = warnings;
    });
  }

  Future<void> _undo(ImportBatch batch) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text(
          'Desfazer importação?',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        content: Text(
          'As despesas e os empréstimos criados por "${batch.fileName}" serão excluídos. '
          'Correções feitas em despesas que já existiam continuam como estão.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.debtRed),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Desfazer'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final p2pCubit = context.read<P2PCubit>();
    setState(() => _busy = true);
    try {
      await sl<ImportRepository>().undoImport(batch.id);
      await _finance.loadCycleData();
      await p2pCubit.loadLoans();
      _showMessage('Importação de "${batch.fileName}" desfeita.');
    } catch (e) {
      _showMessage('$e', error: true);
    }
    await _loadHistory();
    if (!mounted) return;
    setState(() => _busy = false);
    // As linhas desfeitas voltam a ser novas na revisão aberta
    await _refresh();
  }

  // --- Tela ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Importar fatura ou extrato',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: BlocBuilder<FinanceCubit, FinanceState>(
        builder: (context, state) {
          final session = _session;
          return DropTarget(
            enable: !_busy,
            onDragEntered: (_) => setState(() => _dragging = true),
            onDragExited: (_) => setState(() => _dragging = false),
            onDragDone: (detail) => _onDrop(detail.files, state),
            child: Stack(
              children: [
                ResponsiveContainer(
                  maxWidth: 920,
                  child: ListView(
                    // Folga no fim para o botão de ações rápidas não cobrir o Confirmar
                    padding: const EdgeInsets.only(bottom: 96),
                    children: [
                      _originCard(state),
                      if (_resultMessage != null)
                        _banner(
                          _resultMessage!,
                          AppColors.creditGreen,
                          Icons.check_circle_outline_rounded,
                        ),
                      if (_resultWarnings.isNotEmpty)
                        _banner(
                          'A importação foi gravada, mas parte dos movimentos não pôde ser registrada:',
                          AppColors.folegoWarning,
                          Icons.warning_amber_rounded,
                          children: [
                            for (final warning in _resultWarnings)
                              Padding(
                                padding: const EdgeInsets.only(
                                  top: 6,
                                  left: 26,
                                ),
                                child: Text(
                                  warning,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                          ],
                        ),
                      if (session != null) ..._review(state, session),
                      if (_rules.isNotEmpty) _rulesCard(state),
                      if (_history.isNotEmpty) _historyCard(),
                    ],
                  ),
                ),
                if (_dragging)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Container(
                        margin: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.12),
                          border: Border.all(
                            color: AppColors.primary,
                            width: 2,
                          ),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        alignment: Alignment.center,
                        child: const Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.file_download_outlined,
                              size: 40,
                              color: AppColors.primary,
                            ),
                            SizedBox(height: 8),
                            Text(
                              'Solte o arquivo para importar',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: AppColors.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _card({required List<Widget> children}) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }

  Widget _banner(
    String text,
    Color color,
    IconData icon, {
    List<Widget> children = const [],
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
            ],
          ),
          ...children,
        ],
      ),
    );
  }

  /// Navegador e computador aceitam arrastar o arquivo.
  bool get _canDropFiles =>
      kIsWeb ||
      const {
        TargetPlatform.windows,
        TargetPlatform.macOS,
        TargetPlatform.linux,
      }.contains(defaultTargetPlatform);

  Widget _originCard(FinanceState state) {
    final sources = state.paymentMethods.where(_canImport).toList();
    final source = _sourceOf(state);
    final isDemo = sl<AuthRepository>().isDemoMode;

    String detail(PaymentMethod method) {
      if (!method.isCreditCard) return 'Conta';
      if (method.closingDay == null || method.dueDay == null)
        return 'Cartão sem fechamento e vencimento cadastrados';
      return 'Cartão • fecha dia ${method.closingDay}, vence dia ${method.dueDay}';
    }

    return _card(
      children: [
        const Text(
          '1. De onde é o arquivo?',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        const SizedBox(height: 4),
        const Text(
          'Escolha o cartão ou a conta. É por ele que o app sabe o vencimento da fatura e o que já foi lançado.',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 12),
        if (sources.isEmpty)
          const Text(
            'Nenhum cartão ou conta cadastrado. Cadastre em Ajustes, em Pagamentos e contas.',
            style: TextStyle(fontSize: 13),
          )
        else ...[
          DropdownButton<String>(
            key: const Key('import_source'),
            value: source?.id,
            isExpanded: true,
            hint: const Text('Escolher cartão ou conta'),
            onChanged: _busy
                ? null
                : (id) => setState(() {
                    if (id != _sourceId) {
                      _session = null;
                      _fileWarning = null;
                      _failure = null;
                      _rules = const [];
                      _draft = null;
                      _draftTimer?.cancel();
                      if (id != null) {
                        _loadRules(id);
                        _loadDraft(id);
                      }
                    }
                    _sourceId = id;
                  }),
            items: [
              for (final method in sources)
                DropdownMenuItem(
                  value: method.id,
                  child: Text(
                    '${method.name} — ${detail(method)}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                icon: const Icon(Icons.upload_file_rounded, size: 18),
                label: Text(
                  _session == null ? 'Escolher arquivo' : 'Trocar arquivo',
                ),
                onPressed: source == null || _busy
                    ? null
                    : () => _pickFile(source),
              ),
              if (_canDropFiles)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: Text(
                    'ou arraste o arquivo para esta página',
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                ),
              if (isDemo)
                OutlinedButton(
                  onPressed: source == null || _busy
                      ? null
                      : () => _useSample(source),
                  child: const Text('Usar fatura de exemplo'),
                ),
            ],
          ),
          if (_draft != null && _session == null && source != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Icon(
                    Icons.history_rounded,
                    size: 18,
                    color: AppColors.primary,
                  ),
                  Text(
                    'Revisão em andamento: ${_draft!.fileName} '
                    '(salva em ${DateFormat('dd/MM HH:mm').format(_draft!.savedAt)})',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  FilledButton(
                    key: const Key('import_resume_draft'),
                    onPressed: _busy ? null : () => _resumeDraft(source),
                    child: const Text('Retomar'),
                  ),
                  TextButton(
                    onPressed: _busy ? null : () => _discardDraft(source),
                    child: const Text('Descartar'),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 8),
          const Text(
            'OFX e CSV são lidos direto. PDF e foto são lidos por IA: o arquivo é enviado ao provedor de IA e as linhas precisam ser conferidas.',
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ],
      ],
    );
  }

  List<Widget> _review(FinanceState state, ImportSession session) {
    final schedule = _finance.cycleSchedule;
    final totals = session.totals;
    final blockers = session.blockers;
    final closedLines = session.linesInClosedCycles(schedule, _closedCycles);
    final visible = [
      for (final line in session.lines)
        if (_filter == null || session.statusOf(line) == _filter) line,
    ];

    Widget filterChip(String label, LineStatus? status) {
      final count = status == null
          ? session.lines.length
          : session.countOf(status);
      return ChoiceChip(
        label: Text('$label ($count)'),
        selected: _filter == status,
        onSelected: (_) => setState(() => _filter = status),
      );
    }

    return [
      _card(
        children: [
          Text(
            '2. ${session.source.isCreditCard ? 'Fatura' : 'Extrato'} • ${session.source.name}',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Flexible(
                child: Text(
                  '${session.fileName} • ${session.lines.length} linhas',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_csv != null)
                TextButton.icon(
                  icon: const Icon(Icons.view_column_outlined, size: 18),
                  label: const Text('Ajustar colunas'),
                  onPressed: _busy
                      ? null
                      : () async {
                          final csv = _csv!;
                          await _mapCsvColumns(
                            session.source,
                            csv.fileName,
                            csv.content,
                            session.source.isCreditCard
                                ? StatementSourceType.creditCard
                                : StatementSourceType.bankAccount,
                            initial: await sl<CsvMappingStore>().load(
                              session.source.id,
                            ),
                          );
                        },
                ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (session.source.isCreditCard)
                OutlinedButton.icon(
                  icon: const Icon(Icons.event_rounded, size: 18),
                  label: Text(
                    session.invoiceDueDate == null
                        ? 'Informar vencimento da fatura'
                        : 'Vence em ${_dayFormat.format(session.invoiceDueDate!)}',
                  ),
                  onPressed: _busy ? null : _pickDueDate,
                ),
              if (session.waitsForInvoice && session.invoicePaidAt == null)
                TextButton.icon(
                  icon: const Icon(Icons.receipt_long_outlined, size: 18),
                  label: const Text('Fatura já paga?'),
                  onPressed: _busy ? null : _pickInvoicePayment,
                )
              else if (session.waitsForInvoice)
                InputChip(
                  avatar: const Icon(
                    Icons.check_circle_outline_rounded,
                    size: 18,
                    color: AppColors.creditGreen,
                  ),
                  label: Text(
                    'Paga em ${_dayFormat.format(session.invoicePaidAt!)}'
                    '${session.invoicePaidByHouse ? ' pelo Caixa' : ''}',
                  ),
                  onPressed: _busy ? null : _pickInvoicePayment,
                  onDeleted: _busy
                      ? null
                      : () => _update(session.withInvoicePayment(null)),
                ),
              if (session.isHouseCard)
                const Text(
                  'Quem paga: Caixa da Casa',
                  style: TextStyle(fontSize: 13),
                )
              else
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Quem paga: ', style: TextStyle(fontSize: 13)),
                    DropdownButton<String>(
                      value:
                          state.members.any(
                            (m) => m.id == session.payerMemberId,
                          )
                          ? session.payerMemberId
                          : null,
                      underline: const SizedBox.shrink(),
                      onChanged: _busy
                          ? null
                          : (id) {
                              if (id != null) _update(session.withPayer(id));
                            },
                      items: [
                        for (final member in state.members)
                          DropdownMenuItem(
                            value: member.id,
                            child: Text(member.name.split(' ').first),
                          ),
                      ],
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 20,
            runSpacing: 10,
            children: [
              _total('Total do arquivo', totals.file, Colors.grey),
              _total('Já lançado', totals.alreadyLaunched, Colors.blueGrey),
              _total('Casa', totals.house, AppColors.primary),
              _total('Empréstimos', totals.loans, AppColors.debtRed),
              _total('Pessoal', totals.personal, Colors.blueGrey),
              if (!totals.thirdParty.isZero)
                _total('Pago por terceiros', totals.thirdParty, Colors.teal),
              if (!totals.ignored.isZero)
                _total('Ignorado', totals.ignored, Colors.grey),
            ],
          ),
        ],
      ),
      if (_fileWarning != null)
        _banner(
          _fileWarning!,
          AppColors.folegoWarning,
          Icons.warning_amber_rounded,
        ),
      if (_failure != null)
        _banner(
          'Nada foi gravado. $_failure',
          AppColors.debtRed,
          Icons.error_outline_rounded,
        ),
      if (closedLines.isNotEmpty)
        _banner(
          '${closedLines.length == 1 ? '1 linha cai' : '${closedLines.length} linhas caem'} em um ciclo que já foi fechado. '
          'Para lançar na data certa, reabra o ciclo no Fechamento e importe de novo.',
          AppColors.folegoWarning,
          Icons.lock_clock_outlined,
          children: [
            RadioGroup<ClosedCyclePolicy>(
              groupValue: _closedCyclePolicy,
              onChanged: (policy) => setState(
                () => _closedCyclePolicy = policy ?? _closedCyclePolicy,
              ),
              child: const Column(
                children: [
                  RadioListTile<ClosedCyclePolicy>(
                    dense: true,
                    value: ClosedCyclePolicy.adjustInCurrentCycle,
                    title: Text('Lançar no ciclo atual como ajuste'),
                  ),
                  RadioListTile<ClosedCyclePolicy>(
                    dense: true,
                    value: ClosedCyclePolicy.skip,
                    title: Text('Não lançar essas linhas agora'),
                  ),
                ],
              ),
            ),
          ],
        ),
      Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.help_outline_rounded, size: 18, color: Colors.grey),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                '• Casa (gasto): despesa coletiva da casa, rateada entre os moradores no fechamento mensal.\n'
                '• [Nome] deve (empréstimo): empréstimo individual direto entre o morador e quem paga a fatura.',
                style: TextStyle(fontSize: 12, height: 1.4, color: Colors.grey),
              ),
            ),
          ],
        ),
      ),
      if (session.installmentMatches.values.any(
        (m) => m.kind == InstallmentMatchKind.newPlan,
      ))
        SwitchListTile(
          key: const Key('import_forecast_installments'),
          contentPadding: EdgeInsets.zero,
          dense: true,
          value: session.forecastInstallments,
          onChanged: _busy
              ? null
              : (value) => _update(session.withForecastInstallments(value)),
          title: const Text('Prever as próximas parcelas'),
          subtitle: const Text(
            'Compra parcelada nova da Casa já deixa as parcelas seguintes como contas pendentes. A próxima fatura só as confirma.',
            style: TextStyle(fontSize: 12),
          ),
        ),
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            filterChip('Todas', null),
            filterChip('Novas', LineStatus.newLine),
            filterChip('Para revisar', LineStatus.needsReview),
            filterChip('Já lançadas', LineStatus.linked),
            if (session.countOf(LineStatus.alreadyImported) > 0)
              filterChip('Já importadas', LineStatus.alreadyImported),
            filterChip('Ignoradas', LineStatus.ignored),
          ],
        ),
      ),
      if (!sl<AuthRepository>().isDemoMode &&
          session.newLines.any(
            (l) =>
                l.destination == LineDestination.house && l.categoryId == null,
          ))
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: const Icon(Icons.auto_awesome_rounded, size: 18),
            label: const Text(
              'Sugerir nome e categoria com IA para as linhas sem categoria',
            ),
            onPressed: _busy ? null : _suggestWithAi,
          ),
        ),
      _bulkBar(state, session, visible),
      if (_busy) const LinearProgressIndicator(minHeight: 2),
      if (visible.isEmpty)
        const Padding(
          padding: EdgeInsets.all(24),
          child: Center(
            child: Text(
              'Nenhuma linha neste filtro.',
              style: TextStyle(color: Colors.grey),
            ),
          ),
        )
      else
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).dividerColor),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              for (var i = 0; i < visible.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                _lineTile(state, session, visible[i]),
              ],
            ],
          ),
        ),
      const SizedBox(height: 16),
      for (final blocker in blockers)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            blocker,
            style: const TextStyle(fontSize: 12, color: AppColors.debtRed),
          ),
        ),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 16, color: AppColors.primary),
                SizedBox(width: 8),
                Text(
                  'O que acontece ao confirmar?',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
            SizedBox(height: 6),
            Text(
              '• Casa: cria despesas da casa com rateio compartilhado (fechamento no Super Pix).\n'
              '• [Morador] deve: cria empréstimos diretos P2P (o titular do cartão é o credor).\n'
              '• Pessoal e Ignoradas: não geram lançamentos na casa.',
              style: TextStyle(fontSize: 12, height: 1.35),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      SizedBox(
        height: 48,
        child: FilledButton.icon(
          key: const Key('import_confirm'),
          icon: const Icon(Icons.check_circle_outline_rounded),
          label: Text(_busy ? 'Aguarde...' : 'Confirmar importação'),
          onPressed: _busy || blockers.isNotEmpty ? null : _confirm,
        ),
      ),
    ];
  }

  Widget _total(String label, Money value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: Colors.grey,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value.format(),
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _lineTile(
    FinanceState state,
    ImportSession session,
    ImportedStatementLine line,
  ) {
    final status = session.statusOf(line);
    final title = line.title?.trim().isNotEmpty == true
        ? line.title!.trim()
        : StatementText.cleanTitle(line.description);
    final installment = _installmentLabel(session, line);
    final muted =
        status == LineStatus.informational || status == LineStatus.ignored;
    final confirmsForecast = session.confirmsForecast(line);
    final editable =
        status == LineStatus.newLine ||
        status == LineStatus.ignored ||
        confirmsForecast;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (editable)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: Checkbox(
                      value: _selected.contains(line.id),
                      onChanged: _busy
                          ? null
                          : (checked) => setState(() {
                              _selected = {
                                for (final id in _selected)
                                  if (id != line.id) id,
                                if (checked == true) line.id,
                              };
                            }),
                    ),
                  ),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: muted ? Colors.grey : null,
                      ),
                    ),
                    Text(
                      '${_shortDay.format(line.date)} • ${line.description}$installment',
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (line.splitFrom != null) _splitInfo(session, line),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (line.isPurchase &&
                  session.effectiveAmountOf(line) != line.amount)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      line.amount.format(),
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.grey,
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                    Text(
                      session.effectiveAmountOf(line).format(),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ],
                )
              else
                Text(
                  line.amount.format(),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: muted ? Colors.grey : null,
                  ),
                ),
              if (editable) ...[
                IconButton(
                  key: Key('import_split_${line.id}'),
                  icon: const Icon(Icons.call_split_rounded, size: 18),
                  tooltip: 'Dividir em duas partes',
                  onPressed: _busy || line.amount.cents < 2
                      ? null
                      : () => _splitLine(line),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  tooltip: 'Editar nome e data',
                  onPressed: _busy ? null : () => _editLine(line),
                ),
              ] else
                const SizedBox(width: 8),
            ],
          ),
          const SizedBox(height: 4),
          switch (status) {
            LineStatus.informational => _informationalRow(session, line),
            LineStatus.alreadyImported => _importedRow(session, line),
            LineStatus.linked when confirmsForecast => _forecastRow(
              state,
              session,
              line,
            ),
            LineStatus.linked ||
            LineStatus.needsReview => _matchRow(state, session, line),
            LineStatus.newLine ||
            LineStatus.ignored => _destinationRow(state, session, line),
          },
          if (status == LineStatus.newLine || status == LineStatus.ignored)
            for (final option in session.prepaymentOptionsOf(line))
              _prepaymentRow(session, line, option),
        ],
      ),
    );
  }

  /// Linha que pode estar quitando de uma vez as parcelas que faltavam.
  Widget _prepaymentRow(
    ImportSession session,
    ImportedStatementLine line,
    PrepaymentOption option,
  ) {
    final chosen = session.chosenPrepayment(line)?.plan.id == option.plan.id;
    final forecasts = [
      for (final n in option.numbers)
        if (option.plan.forecastOf(n) != null) n,
    ].length;
    return CheckboxListTile(
      key: Key('import_prepayment_${line.id}_${option.plan.id}'),
      contentPadding: EdgeInsets.zero,
      dense: true,
      controlAffinity: ListTileControlAffinity.leading,
      value: chosen,
      onChanged: _busy
          ? null
          : (value) => _update(
              session.withPrepaymentChoice(
                line.id,
                value == true ? option.plan.id : null,
              ),
            ),
      title: Text(
        'Antecipação: quita as parcelas ${option.rangeLabel} de "${option.plan.title}"',
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        [
          'Faltavam ${option.remaining.format()}.',
          if (forecasts > 0)
            forecasts == 1
                ? 'A parcela prevista sai e a compra termina.'
                : 'As $forecasts parcelas previstas saem e a compra termina.'
          else
            'A compra termina e não é mais projetada.',
        ].join(' '),
        style: const TextStyle(fontSize: 11),
      ),
    );
  }

  Widget _informationalRow(ImportSession session, ImportedStatementLine line) {
    if (session.wasImported(line)) {
      return const Text(
        'Já veio em uma importação anterior.',
        style: TextStyle(fontSize: 12, color: Colors.grey),
      );
    }

    if (line.kind == StatementLineKind.refund) return _refundRow(session, line);

    final label = switch (line.kind) {
      StatementLineKind.payment =>
        'Pagamento de fatura: não é uma despesa nova',
      StatementLineKind.refund =>
        'Estorno ou crédito: confira a compra original no app',
      StatementLineKind.income => 'Entrada na conta: não é uma despesa',
      StatementLineKind.purchase => '',
    };
    final options = session.extraOptionsOf(line);
    if (options.isEmpty) {
      return Text(
        label,
        style: const TextStyle(fontSize: 12, color: Colors.grey),
      );
    }

    final chosen = session.chosenExtra(line);
    final suggestion = options.where((o) => o.suggested).firstOrNull;
    return Wrap(
      spacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        DropdownButton<String>(
          value: chosen?.key ?? '',
          underline: const SizedBox.shrink(),
          isDense: true,
          onChanged: _busy
              ? null
              : (key) => _update(
                  session.withExtraChoice(
                    line.id,
                    key == null || key.isEmpty ? null : key,
                  ),
                ),
          items: [
            const DropdownMenuItem(
              value: '',
              child: Text(
                'Não registrar nada',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
            for (final option in options)
              DropdownMenuItem(
                value: option.key,
                child: Text(
                  option.label,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
        if (chosen == null && suggestion != null)
          TextButton(
            onPressed: _busy
                ? null
                : () =>
                      _update(session.withExtraChoice(line.id, suggestion.key)),
            child: Text(
              'Parece: ${suggestion.label}',
              style: const TextStyle(fontSize: 12),
            ),
          ),
      ],
    );
  }

  /// Estorno: de qual compra ele é abatido (desta fatura ou já lançada).
  Widget _refundRow(ImportSession session, ImportedStatementLine line) {
    final options = session.refundOptionsOf(line);
    if (options.isEmpty) {
      return const Text(
        'Estorno: nenhuma compra deste cartão com esse valor para abater. Confira no app.',
        style: TextStyle(fontSize: 12, color: Colors.grey),
      );
    }

    final chosen = session.chosenRefund(line);
    final suggestion = options.where((o) => o.suggested).firstOrNull;
    return Wrap(
      spacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        DropdownButton<String>(
          key: Key('import_refund_${line.id}'),
          value: chosen?.key ?? '',
          underline: const SizedBox.shrink(),
          isDense: true,
          onChanged: _busy
              ? null
              : (key) => _update(
                  session.withRefundChoice(
                    line.id,
                    key == null || key.isEmpty ? null : key,
                  ),
                ),
          items: [
            const DropdownMenuItem(
              value: '',
              child: Text(
                'Estorno: não abater de nada',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
            for (final option in options)
              DropdownMenuItem(
                value: option.key,
                child: Text(
                  option.label,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
        if (chosen == null && suggestion != null)
          TextButton(
            onPressed: _busy
                ? null
                : () => _update(
                    session.withRefundChoice(line.id, suggestion.key),
                  ),
            child: Text(
              'Parece: ${suggestion.label}',
              style: const TextStyle(fontSize: 12),
            ),
          ),
      ],
    );
  }

  /// Seleção e edição de várias linhas de uma vez.
  Widget _bulkBar(
    FinanceState state,
    ImportSession session,
    List<ImportedStatementLine> visible,
  ) {
    final selectable = {
      for (final line in visible)
        if (session.statusOf(line) == LineStatus.newLine ||
            session.statusOf(line) == LineStatus.ignored)
          line.id,
    };
    if (selectable.isEmpty && _selected.isEmpty) return const SizedBox.shrink();

    final debtors = [
      for (final member in state.members)
        if (session.canOwe(member.id)) member,
    ];

    if (_selected.isEmpty) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          icon: const Icon(Icons.checklist_rounded, size: 18),
          label: Text(
            'Selecionar as ${selectable.length} linhas para editar juntas',
          ),
          onPressed: _busy
              ? null
              : () => setState(() => _selected = selectable),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            _selected.length == 1
                ? '1 linha marcada'
                : '${_selected.length} linhas marcadas',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
          ),
          DropdownButton<String>(
            key: const Key('import_bulk_destination'),
            hint: const Text('Destino', style: TextStyle(fontSize: 12)),
            underline: const SizedBox.shrink(),
            isDense: true,
            onChanged: _busy
                ? null
                : (key) {
                    if (key != null)
                      _bulk((line) => _withDestinationKey(line, key));
                  },
            items: _destinationItems(
              debtors,
              session.isHouseCard ? null : _memberName(session.payerMemberId),
              colored: false,
            ),
          ),
          if (state.categories.isNotEmpty)
            DropdownButton<String>(
              key: const Key('import_bulk_category'),
              hint: const Text('Categoria', style: TextStyle(fontSize: 12)),
              underline: const SizedBox.shrink(),
              isDense: true,
              onChanged: _busy
                  ? null
                  : (id) => _bulk((line) => line.copyWith(categoryId: id)),
              items: [
                for (final category in state.categories)
                  DropdownMenuItem(
                    value: category.id,
                    child: Text(
                      category.name,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
              ],
            ),
          TextButton(
            onPressed: () => setState(() => _selected = const {}),
            child: const Text('Limpar seleção'),
          ),
        ],
      ),
    );
  }

  /// Parcela da linha e o que a importação faz com a compra parcelada.
  String _installmentLabel(ImportSession session, ImportedStatementLine line) {
    if (!line.isInstallment) return '';
    final parcel = ' • parcela ${line.installmentNumber}/${line.installmentsTotal}';
    final match = session.installmentMatchOf(line);
    if (match == null) return parcel;
    if (session.confirmsForecast(line)) return '$parcel (prevista)';
    final forecasts = session.forecastsCreatedBy(line);
    if (forecasts > 0) {
      return forecasts == 1
          ? '$parcel • prevê a última'
          : '$parcel • prevê as próximas $forecasts';
    }
    if (match.kind == InstallmentMatchKind.forecast &&
        session.statusOf(line) == LineStatus.newLine) {
      return '$parcel • tira esta e as próximas previstas da Casa';
    }
    final plan = match.plan;
    if (plan != null &&
        plan.isAccepted &&
        line.destination == LineDestination.splitP2P &&
        line.assignedMemberId == plan.assignedMemberId) {
      return '$parcel • parcelamento já aceito por ${_memberName(plan.assignedMemberId!)}';
    }
    return parcel;
  }

  /// Linha que confirma uma parcela prevista: o destino ainda pode mudar.
  Widget _forecastRow(
    FinanceState state,
    ImportSession session,
    ImportedStatementLine line,
  ) {
    final forecast = session.confirmedForecastOf(line)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Parcela prevista "${forecast.title}": a fatura confirma valor e vencimento, sem lançar de novo.',
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.creditGreen,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        _destinationRow(state, session, line),
      ],
    );
  }

  Widget _importedRow(ImportSession session, ImportedStatementLine line) {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 4,
      children: [
        const Text(
          'Já veio em uma importação anterior. Não será lançada de novo.',
          style: TextStyle(
            fontSize: 12,
            color: AppColors.creditGreen,
            fontWeight: FontWeight.w600,
          ),
        ),
        TextButton(
          onPressed: _busy
              ? null
              : () => _update(session.withForcedLine(line.id)),
          child: const Text('Lançar de novo'),
        ),
      ],
    );
  }

  Widget _rulesCard(FinanceState state) {
    String describe(ImportRule rule) {
      switch (rule.destination) {
        case LineDestination.house:
          final category = state.categories
              .where((c) => c.id == rule.categoryId)
              .firstOrNull;
          return category == null ? 'Casa' : 'Casa • ${category.name}';
        case LineDestination.splitP2P:
          return '${_memberName(rule.assignedMemberId)} deve';
        case LineDestination.cardOwnerPersonal:
          return 'Pessoal';
        case LineDestination.ignored:
          return 'Ignorar';
        case LineDestination.thirdParty:
          return 'Pago por terceiros';
      }
    }

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(16),
        ),
        clipBehavior: Clip.antiAlias,
        child: Material(
          color: Colors.transparent,
          child: ExpansionTile(
            shape: const Border(),
            collapsedShape: const Border(),
            title: Text(
              'Regras aprendidas (${_rules.length})',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            subtitle: const Text(
              'O que você decidiu para cada estabelecimento deste cartão ou conta já vem assim na próxima importação.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            children: [
              for (final rule in _rules)
                ListTile(
                  dense: true,
                  title: Text(
                    rule.merchantName,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    describe(rule),
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    tooltip: 'Esquecer esta regra',
                    onPressed: _busy || rule.id == null
                        ? null
                        : () => _deleteRule(rule),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _deleteRule(ImportRule rule) async {
    try {
      await sl<ImportRepository>().deleteRule(rule.id!);
    } catch (e) {
      _showMessage('$e', error: true);
    }
    final sourceId = _sourceId;
    if (sourceId != null) await _loadRules(sourceId);
  }

  Widget _historyCard() {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: _card(
        children: [
          const Text(
            'Importações anteriores',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 4),
          for (final batch in _history)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(
                '${batch.sourceName} • ${batch.fileName}',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: batch.isUndone ? Colors.grey : null,
                  decoration: batch.isUndone
                      ? TextDecoration.lineThrough
                      : null,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                [
                  'Importado em ${_dayFormat.format(batch.createdAt)}',
                  if (batch.invoiceDueDate != null)
                    'fatura de ${_dayFormat.format(batch.invoiceDueDate!)}',
                  batch.total.format(),
                  '${batch.createdCount} ${batch.createdCount == 1 ? 'lançamento criado' : 'lançamentos criados'}',
                  if (batch.isUndone) 'desfeita',
                ].join(' • '),
                style: const TextStyle(fontSize: 12),
              ),
              trailing: batch.isUndone
                  ? null
                  : TextButton(
                      onPressed: _busy ? null : () => _undo(batch),
                      child: const Text('Desfazer'),
                    ),
            ),
        ],
      ),
    );
  }

  Widget _matchRow(
    FinanceState state,
    ImportSession session,
    ImportedStatementLine line,
  ) {
    final match = session.matchOf(line.id)!;
    final expense = match.expense;
    final accepted = session.decisionOf(line.id) == MatchDecision.accepted;
    final method = state.paymentMethods
        .where((p) => p.id == expense.paymentMethodId)
        .firstOrNull;
    final where = method == null || method.id == session.source.id
        ? ''
        : ' em ${method.name}';
    final found =
        '"${expense.title}" de ${_shortDay.format(expense.date)}$where';

    final String text;
    switch (match.kind) {
      case LineMatchKind.alreadyLaunched:
        text = 'Já lançado: $found. Não será lançado de novo.';
      case LineMatchKind.probable:
        if (expense.isPending) {
          text = accepted
              ? 'É a conta pendente $found. Não será lançada de novo; dê baixa nela na Casa.'
              : 'Parece ser a conta pendente $found.';
        } else if (!accepted) {
          text = 'Parece ser $found, com o mesmo valor.';
        } else if (expense.settledAt != null) {
          text = 'É $found, já acertada em um fechamento: fica como está.';
        } else {
          text = 'É $found: passa para ${session.source.name}.';
        }
      case LineMatchKind.amountDiffers:
        final canUpdate = ImportSession.canUpdateAmount(expense);
        if (!accepted) {
          text = 'Parece ser $found, lançada por ${expense.amount.format()}.';
        } else if (canUpdate) {
          text =
              'É $found: o valor passa de ${expense.amount.format()} para ${line.amount.format()}.';
        } else {
          text =
              'É $found, lançada por ${expense.amount.format()}. Ajuste o valor na própria despesa.';
        }
    }

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 4,
      children: [
        Text(
          text,
          style: TextStyle(
            fontSize: 12,
            color: accepted ? AppColors.creditGreen : AppColors.folegoWarning,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (!accepted)
          TextButton(
            onPressed: _busy
                ? null
                : () => _update(
                    session.withDecision(line.id, MatchDecision.accepted),
                  ),
            child: const Text('É a mesma'),
          ),
        TextButton(
          onPressed: _busy
              ? null
              : () => _update(
                  session.withDecision(line.id, MatchDecision.rejected),
                ),
          child: const Text('São diferentes'),
        ),
      ],
    );
  }

  Widget _destinationRow(
    FinanceState state,
    ImportSession session,
    ImportedStatementLine line,
  ) {
    final rejected = session.matchOf(line.id);
    final debtors = [
      for (final HouseMember member in state.members)
        if (session.canOwe(member.id)) member,
    ];
    // Cartão da Casa não tem dono para ter gasto pessoal
    final payerName = session.isHouseCard
        ? null
        : _memberName(session.payerMemberId);

    return Wrap(
      spacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        DropdownButton<String>(
          value: _destinationKeyOf(
            line,
            debtors,
            allowPersonal: payerName != null,
          ),
          hint: const Text(
            'Quem deve?',
            style: TextStyle(fontSize: 12, color: AppColors.debtRed),
          ),
          underline: const SizedBox.shrink(),
          isDense: true,
          onChanged: _busy
              ? null
              : (key) {
                  if (key != null)
                    _classify(session, _withDestinationKey(line, key));
                },
          items: _destinationItems(debtors, payerName, colored: true),
        ),
        if (line.destination == LineDestination.house &&
            state.categories.isNotEmpty)
          DropdownButton<String>(
            value: state.categories.any((c) => c.id == line.categoryId)
                ? line.categoryId
                : null,
            // Sem sugestão, vale a primeira categoria da casa
            hint: Text(
              '${state.categories.first.name} (padrão)',
              style: const TextStyle(
                fontSize: 12,
                color: Colors.grey,
                fontStyle: FontStyle.italic,
              ),
            ),
            underline: const SizedBox.shrink(),
            isDense: true,
            onChanged: _busy
                ? null
                : (id) => _classify(session, line.copyWith(categoryId: id)),
            items: [
              for (final category in state.categories)
                DropdownMenuItem(
                  value: category.id,
                  child: Text(
                    category.name,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
            ],
          ),
        if (session.ruledLineIds.contains(line.id))
          const Tooltip(
            message: 'Veio assim por uma regra aprendida em outra importação',
            child: Icon(
              Icons.auto_awesome_outlined,
              size: 14,
              color: Colors.grey,
            ),
          ),
        if (rejected != null)
          TextButton(
            onPressed: _busy
                ? null
                : () => _update(
                    session.withDecision(line.id, MatchDecision.accepted),
                  ),
            child: Text(
              'Era "${rejected.expense.title}"',
              style: const TextStyle(fontSize: 12),
            ),
          ),
      ],
    );
  }
}
