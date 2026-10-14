import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/domain/value_objects/financial_cycle.dart';
import '../../../../core/domain/value_objects/money.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/responsive_container.dart';
import '../../../auth/domain/repositories/auth_repository.dart';
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
import '../../domain/entities/imported_statement_line.dart';
import '../../domain/services/import_session.dart';
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
  ImportSession? _session;
  bool _busy = false;
  String? _fileWarning;
  Set<FinancialCycle> _closedCycles = const {};
  ClosedCyclePolicy _closedCyclePolicy = ClosedCyclePolicy.adjustInCurrentCycle;
  LineStatus? _filter;
  List<String> _failures = const [];
  String? _resultMessage;

  FinanceCubit get _finance => context.read<FinanceCubit>();

  @override
  void initState() {
    super.initState();
    _sourceId = widget.initialSourceId;
    // Aberta direto pelo endereço: a casa pode não estar carregada ainda
    if (_finance.state.paymentMethods.isEmpty) _finance.loadCycleData();
  }

  static bool _canImport(PaymentMethod method) =>
      method.type == PaymentMethodType.card || method.type == PaymentMethodType.account;

  PaymentMethod? _sourceOf(FinanceState state) {
    final sources = state.paymentMethods.where(_canImport).toList();
    return sources.where((p) => p.id == _sourceId).firstOrNull ??
        (sources.length == 1 ? sources.first : null);
  }

  String _memberName(String? memberId) {
    final member = _finance.state.members.where((m) => m.id == memberId).firstOrNull;
    return member?.name.split(' ').first ?? 'morador';
  }

  void _showMessage(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: error ? AppColors.debtRed : null),
    );
  }

  // --- Leitura do arquivo ---

  Future<void> _pickFile(PaymentMethod source) async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['ofx', 'csv', 'txt'],
      );
      if (files.isEmpty) return;

      final file = files.first;
      final content = StatementParser.decodeBytes(await file.readAsBytes());
      final sourceType =
          source.isCreditCard ? StatementSourceType.creditCard : StatementSourceType.bankAccount;
      final lines = StatementParser.parseFile(content, filename: file.name, source: sourceType);
      if (lines.isEmpty) {
        _showMessage('Nenhum lançamento encontrado no arquivo selecionado.', error: true);
        return;
      }

      String? warning;
      final isOfx = content.contains('<STMTTRN>');
      if (isOfx && StatementParser.isCreditCardOfx(content) != source.isCreditCard) {
        warning = source.isCreditCard
            ? 'Este arquivo parece ser o extrato de uma conta, e não a fatura de um cartão. Confira a origem escolhida.'
            : 'Este arquivo parece ser a fatura de um cartão, e não o extrato de uma conta. Confira a origem escolhida.';
      }
      await _start(source, file.name, lines, warning: warning);
    } catch (e) {
      _showMessage('Erro ao importar arquivo: $e', error: true);
    }
  }

  /// Fatura de exemplo do modo demo, para ver a tela sem ter um arquivo.
  Future<void> _useSample(PaymentMethod source) async {
    final now = DateTime.now();
    ImportedStatementLine line(int index, int daysAgo, String description, int cents) =>
        ImportedStatementLine(
          id: 'sample_$index',
          date: now.subtract(Duration(days: daysAgo)),
          description: description,
          amount: Money(cents),
        );

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
  }) async {
    final currentUserId = sl<AuthRepository>().currentUser?.id;
    final members = _finance.state.members;
    final payer = source.ownerMemberId ??
        currentUserId ??
        (members.isNotEmpty ? members.first.id : '');

    setState(() {
      _session = ImportSession.start(
        source: source,
        fileName: fileName,
        lines: lines,
        payerMemberId: payer,
      );
      _sourceId = source.id;
      _fileWarning = warning;
      _failures = const [];
      _resultMessage = null;
      _filter = null;
    });
    await _refresh(suggestCategories: true);
  }

  /// Busca no app o que pode ser igual às linhas e quais ciclos já fecharam.
  Future<void> _refresh({bool suggestCategories = false}) async {
    final session = _session;
    if (session == null) return;
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
      _showMessage('Não foi possível comparar com os lançamentos do app: $e', error: true);
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

    if (!mounted) return;
    // A revisão pode ter mudado enquanto a busca corria: parte da atual
    var updated = (_session ?? session).withExpenses(byId.values.toList());
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

  Future<void> _pickDueDate() async {
    final session = _session!;
    final initial = session.invoiceDueDate ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(initial.year - 2),
      lastDate: DateTime(initial.year + 1, 12, 31),
      helpText: 'Vencimento da fatura',
    );
    if (picked == null || !mounted) return;
    _update(_session!.withInvoiceDueDate(picked));
    await _refresh();
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
          title: const Text('Editar linha', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(line.description, style: const TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                decoration: const InputDecoration(labelText: 'Nome do lançamento'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.event_rounded, size: 18),
                label: Text('Compra em ${_dayFormat.format(date)}'),
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: date,
                    firstDate: DateTime(date.year - 2),
                    lastDate: DateTime.now().add(const Duration(days: 31)),
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
      _failures = const [];
    });

    final failures = <String>[];
    final savedLineIds = <String>{};
    Future<void> save(String recordId, String label, Future<void> Function() action) async {
      try {
        await action();
        savedLineIds.addAll(plan.lineIdsByRecord[recordId] ?? const []);
      } catch (e) {
        failures.add('$label: $e');
      }
    }

    final finance = sl<FinanceRepository>();
    final p2p = sl<P2PRepository>();
    for (final expense in plan.newExpenses) {
      await save(expense.id, expense.title, () => finance.addExpense(expense));
    }
    for (final expense in plan.expenseUpdates) {
      await save(expense.id, expense.title, () => finance.updateExpense(expense));
    }
    for (final loan in plan.loans) {
      await save(loan.id, loan.title, () => p2p.createLoan(loan));
    }

    await _finance.loadCycleData();
    await p2pCubit.loadLoans();
    if (!mounted) return;

    final linked = session.countOf(LineStatus.linked);
    final summary = [
      '${plan.newExpenses.length} ${plan.newExpenses.length == 1 ? 'despesa lançada' : 'despesas lançadas'}',
      if (plan.loans.isNotEmpty)
        '${plan.loans.length} ${plan.loans.length == 1 ? 'empréstimo criado' : 'empréstimos criados'}',
      if (linked > 0) '$linked já ${linked == 1 ? 'estava lançada' : 'estavam lançadas'}',
      if (plan.skippedClosedCycle.isNotEmpty)
        '${plan.skippedClosedCycle.length} de ciclo fechado ${plan.skippedClosedCycle.length == 1 ? 'ficou' : 'ficaram'} de fora',
    ].join(' • ');

    if (failures.isEmpty) {
      setState(() {
        _session = null;
        _busy = false;
        _resultMessage = '${session.fileName} importado: $summary.';
      });
      return;
    }

    // O que já foi gravado sai da lista, para tentar de novo só o que falhou
    var remaining = session;
    for (final line in session.lines) {
      if (savedLineIds.contains(line.id) && session.statusOf(line) == LineStatus.newLine) {
        remaining = remaining.withLine(line.copyWith(destination: LineDestination.ignored));
      }
    }
    setState(() {
      _session = remaining;
      _busy = false;
      _failures = failures;
    });
    await _refresh();
  }

  // --- Tela ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Importar fatura ou extrato', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: BlocBuilder<FinanceCubit, FinanceState>(
        builder: (context, state) {
          final session = _session;
          return ResponsiveContainer(
            maxWidth: 920,
            child: ListView(
              // Folga no fim para o botão de ações rápidas não cobrir o Confirmar
              padding: const EdgeInsets.only(bottom: 96),
              children: [
                _originCard(state),
                if (_resultMessage != null) _banner(_resultMessage!, AppColors.creditGreen, Icons.check_circle_outline_rounded),
                if (session != null) ..._review(state, session),
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
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    );
  }

  Widget _banner(String text, Color color, IconData icon, {List<Widget> children = const []}) {
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

  Widget _originCard(FinanceState state) {
    final sources = state.paymentMethods.where(_canImport).toList();
    final source = _sourceOf(state);
    final isDemo = sl<AuthRepository>().isDemoMode;

    String detail(PaymentMethod method) {
      if (!method.isCreditCard) return 'Conta';
      if (method.closingDay == null || method.dueDay == null) return 'Cartão sem fechamento e vencimento cadastrados';
      return 'Cartão • fecha dia ${method.closingDay}, vence dia ${method.dueDay}';
    }

    return _card(
      children: [
        const Text('1. De onde é o arquivo?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
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
                        _failures = const [];
                      }
                      _sourceId = id;
                    }),
            items: [
              for (final method in sources)
                DropdownMenuItem(
                  value: method.id,
                  child: Text('${method.name} — ${detail(method)}', overflow: TextOverflow.ellipsis),
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
                label: Text(_session == null ? 'Escolher arquivo OFX ou CSV' : 'Trocar arquivo'),
                onPressed: source == null || _busy ? null : () => _pickFile(source),
              ),
              if (isDemo)
                OutlinedButton(
                  onPressed: source == null || _busy ? null : () => _useSample(source),
                  child: const Text('Usar fatura de exemplo'),
                ),
            ],
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
      final count = status == null ? session.lines.length : session.countOf(status);
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
          Text(
            '${session.fileName} • ${session.lines.length} linhas',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
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
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Quem paga: ', style: TextStyle(fontSize: 13)),
                  DropdownButton<String>(
                    value: state.members.any((m) => m.id == session.payerMemberId)
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
                        DropdownMenuItem(value: member.id, child: Text(member.name.split(' ').first)),
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
              if (!totals.ignored.isZero) _total('Ignorado', totals.ignored, Colors.grey),
            ],
          ),
        ],
      ),
      if (_fileWarning != null) _banner(_fileWarning!, AppColors.folegoWarning, Icons.warning_amber_rounded),
      if (_failures.isNotEmpty)
        _banner(
          'Parte da importação não foi gravada. O que deu certo saiu da lista; corrija e confirme de novo.',
          AppColors.debtRed,
          Icons.error_outline_rounded,
          children: [
            for (final failure in _failures)
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 26),
                child: Text(failure, style: const TextStyle(fontSize: 12)),
              ),
          ],
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
              onChanged: (policy) => setState(() => _closedCyclePolicy = policy ?? _closedCyclePolicy),
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
            filterChip('Ignoradas', LineStatus.ignored),
          ],
        ),
      ),
      if (_busy) const LinearProgressIndicator(minHeight: 2),
      if (visible.isEmpty)
        const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: Text('Nenhuma linha neste filtro.', style: TextStyle(color: Colors.grey))),
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
          child: Text(blocker, style: const TextStyle(fontSize: 12, color: AppColors.debtRed)),
        ),
      const Text(
        'Ao confirmar: cada linha da Casa vira uma despesa com rateio; linhas de outro morador viram empréstimo com quem paga a fatura como credor; linhas pessoais e ignoradas não geram nada.',
        style: TextStyle(fontSize: 11, color: Colors.grey),
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
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w500)),
        const SizedBox(height: 2),
        Text(value.format(), style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }

  Widget _lineTile(FinanceState state, ImportSession session, ImportedStatementLine line) {
    final status = session.statusOf(line);
    final title = line.title?.trim().isNotEmpty == true
        ? line.title!.trim()
        : StatementText.cleanTitle(line.description);
    final installment = line.isInstallment ? ' • parcela ${line.installmentNumber}/${line.installmentsTotal}' : '';
    final muted = status == LineStatus.informational || status == LineStatus.ignored;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(fontWeight: FontWeight.w600, color: muted ? Colors.grey : null),
                    ),
                    Text(
                      '${_shortDay.format(line.date)} • ${line.description}$installment',
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                line.amount.format(),
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: muted ? Colors.grey : null),
              ),
              if (status == LineStatus.newLine || status == LineStatus.ignored)
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  tooltip: 'Editar nome e data',
                  onPressed: _busy ? null : () => _editLine(line),
                )
              else
                const SizedBox(width: 8),
            ],
          ),
          const SizedBox(height: 4),
          switch (status) {
            LineStatus.informational => _informationalRow(line),
            LineStatus.linked || LineStatus.needsReview => _matchRow(state, session, line),
            LineStatus.newLine || LineStatus.ignored => _destinationRow(state, session, line),
          },
        ],
      ),
    );
  }

  Widget _informationalRow(ImportedStatementLine line) {
    final label = switch (line.kind) {
      StatementLineKind.payment => 'Pagamento de fatura: não é uma despesa nova',
      StatementLineKind.refund => 'Estorno ou crédito: confira a compra original no app',
      StatementLineKind.income => 'Entrada na conta: não é uma despesa',
      StatementLineKind.purchase => '',
    };
    return Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey));
  }

  Widget _matchRow(FinanceState state, ImportSession session, ImportedStatementLine line) {
    final match = session.matchOf(line.id)!;
    final expense = match.expense;
    final accepted = session.decisionOf(line.id) == MatchDecision.accepted;
    final method = state.paymentMethods.where((p) => p.id == expense.paymentMethodId).firstOrNull;
    final where = method == null || method.id == session.source.id ? '' : ' em ${method.name}';
    final found = '"${expense.title}" de ${_shortDay.format(expense.date)}$where';

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
          text = 'É $found: o valor passa de ${expense.amount.format()} para ${line.amount.format()}.';
        } else {
          text = 'É $found, lançada por ${expense.amount.format()}. Ajuste o valor na própria despesa.';
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
            onPressed: _busy ? null : () => _update(session.withDecision(line.id, MatchDecision.accepted)),
            child: const Text('É a mesma'),
          ),
        TextButton(
          onPressed: _busy ? null : () => _update(session.withDecision(line.id, MatchDecision.rejected)),
          child: const Text('São diferentes'),
        ),
      ],
    );
  }

  Widget _destinationRow(FinanceState state, ImportSession session, ImportedStatementLine line) {
    final rejected = session.matchOf(line.id);
    final debtors = [
      for (final HouseMember member in state.members)
        if (member.id != session.payerMemberId) member,
    ];
    final payerName = _memberName(session.payerMemberId);

    return Wrap(
      spacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        DropdownButton<LineDestination>(
          value: line.destination,
          underline: const SizedBox.shrink(),
          isDense: true,
          onChanged: _busy
              ? null
              : (destination) {
                  if (destination == null) return;
                  _update(
                    session.withLine(
                      line.copyWith(
                        destination: destination,
                        // Com um só outro morador, é ele quem deve
                        assignedMemberId: destination == LineDestination.splitP2P &&
                                line.assignedMemberId == null &&
                                debtors.length == 1
                            ? debtors.first.id
                            : null,
                        clearAssignedMember: destination != LineDestination.splitP2P,
                      ),
                    ),
                  );
                },
          items: [
            const DropdownMenuItem(
              value: LineDestination.house,
              child: Text('Casa', style: TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.bold)),
            ),
            if (debtors.isNotEmpty)
              const DropdownMenuItem(
                value: LineDestination.splitP2P,
                child: Text('Outro morador deve', style: TextStyle(color: AppColors.debtRed, fontSize: 12, fontWeight: FontWeight.bold)),
              ),
            DropdownMenuItem(
              value: LineDestination.cardOwnerPersonal,
              child: Text('Pessoal de $payerName', style: const TextStyle(color: Colors.blueGrey, fontSize: 12)),
            ),
            const DropdownMenuItem(
              value: LineDestination.ignored,
              child: Text('Ignorar', style: TextStyle(color: Colors.grey, fontSize: 12)),
            ),
          ],
        ),
        if (line.destination == LineDestination.house && state.categories.isNotEmpty)
          DropdownButton<String>(
            value: state.categories.any((c) => c.id == line.categoryId) ? line.categoryId : null,
            // Sem sugestão, vale a primeira categoria da casa
            hint: Text(
              '${state.categories.first.name} (padrão)',
              style: const TextStyle(fontSize: 12, color: Colors.grey, fontStyle: FontStyle.italic),
            ),
            underline: const SizedBox.shrink(),
            isDense: true,
            onChanged: _busy ? null : (id) => _update(session.withLine(line.copyWith(categoryId: id))),
            items: [
              for (final category in state.categories)
                DropdownMenuItem(
                  value: category.id,
                  child: Text(category.name, style: const TextStyle(fontSize: 12)),
                ),
            ],
          ),
        if (line.destination == LineDestination.splitP2P)
          DropdownButton<String>(
            value: debtors.any((m) => m.id == line.assignedMemberId) ? line.assignedMemberId : null,
            hint: const Text('Quem deve?', style: TextStyle(fontSize: 12, color: AppColors.debtRed)),
            underline: const SizedBox.shrink(),
            isDense: true,
            onChanged: _busy ? null : (id) => _update(session.withLine(line.copyWith(assignedMemberId: id))),
            items: [
              for (final member in debtors)
                DropdownMenuItem(
                  value: member.id,
                  child: Text(member.name.split(' ').first, style: const TextStyle(fontSize: 12)),
                ),
            ],
          ),
        if (rejected != null)
          TextButton(
            onPressed: _busy ? null : () => _update(session.withDecision(line.id, MatchDecision.accepted)),
            child: Text('Era "${rejected.expense.title}"', style: const TextStyle(fontSize: 12)),
          ),
      ],
    );
  }
}
