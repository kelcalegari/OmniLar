import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/domain/value_objects/financial_cycle.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/entities/category.dart';
import '../../domain/entities/house_member.dart';
import '../../domain/entities/payment_method.dart';
import '../../domain/value_objects/transaction_filter.dart';

class TransactionsFilterSheet extends StatefulWidget {
  final TransactionFilter initialFilter;
  final List<FinancialCycle> availableCycles;
  final List<ExpenseCategory> categories;
  final List<HouseMember> members;
  final List<PaymentMethod> paymentMethods;
  final Function(TransactionFilter) onApply;

  const TransactionsFilterSheet({
    super.key,
    required this.initialFilter,
    required this.availableCycles,
    required this.categories,
    required this.members,
    required this.paymentMethods,
    required this.onApply,
  });

  static Future<void> show({
    required BuildContext context,
    required TransactionFilter initialFilter,
    required List<FinancialCycle> availableCycles,
    required List<ExpenseCategory> categories,
    required List<HouseMember> members,
    required List<PaymentMethod> paymentMethods,
    required Function(TransactionFilter) onApply,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => TransactionsFilterSheet(
        initialFilter: initialFilter,
        availableCycles: availableCycles,
        categories: categories,
        members: members,
        paymentMethods: paymentMethods,
        onApply: onApply,
      ),
    );
  }

  @override
  State<TransactionsFilterSheet> createState() => _TransactionsFilterSheetState();
}

class _TransactionsFilterSheetState extends State<TransactionsFilterSheet> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late PeriodMode _periodMode;
  FinancialCycle? _selectedCycle;
  DateRangePreset? _datePreset;
  DateTime? _startDate;
  DateTime? _endDate;
  late Set<String> _categoryIds;
  String? _memberId;
  String? _paymentMethodId;
  bool? _onlyPending;

  final _dateFormat = DateFormat('dd/MM/yyyy');

  @override
  void initState() {
    super.initState();
    _periodMode = widget.initialFilter.periodMode;
    _selectedCycle = widget.initialFilter.selectedCycle ?? widget.availableCycles.firstOrNull;
    _datePreset = widget.initialFilter.datePreset;
    _startDate = widget.initialFilter.startDate;
    _endDate = widget.initialFilter.endDate;
    _categoryIds = Set.from(widget.initialFilter.categoryIds);
    _memberId = widget.initialFilter.memberId;
    _paymentMethodId = widget.initialFilter.paymentMethodId;
    _onlyPending = widget.initialFilter.onlyPending;

    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: _periodMode == PeriodMode.cycle ? 0 : 1,
    );
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      setState(() {
        _periodMode = _tabController.index == 0 ? PeriodMode.cycle : PeriodMode.dateRange;
      });
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _applyPreset(DateRangePreset preset) {
    final now = DateTime.now();
    DateTime start;
    DateTime end = now;

    switch (preset) {
      case DateRangePreset.thisMonth:
        start = DateTime(now.year, now.month, 1);
        break;
      case DateRangePreset.last30Days:
        start = now.subtract(const Duration(days: 30));
        break;
      case DateRangePreset.last90Days:
        start = now.subtract(const Duration(days: 90));
        break;
      case DateRangePreset.thisYear:
        start = DateTime(now.year, 1, 1);
        break;
      case DateRangePreset.custom:
        return;
    }

    setState(() {
      _datePreset = preset;
      _startDate = start;
      _endDate = end;
    });
  }

  Future<void> _pickCustomDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2015, 1, 1),
      lastDate: DateTime(now.year + 5, 12, 31),
      initialDateRange: (_startDate != null && _endDate != null)
          ? DateTimeRange(start: _startDate!, end: _endDate!)
          : DateTimeRange(start: now.subtract(const Duration(days: 30)), end: now),
      helpText: 'Selecione o intervalo de datas',
    );

    if (picked != null) {
      setState(() {
        _datePreset = DateRangePreset.custom;
        _startDate = picked.start;
        _endDate = picked.end;
      });
    }
  }

  void _reset() {
    setState(() {
      _periodMode = PeriodMode.cycle;
      _selectedCycle = widget.availableCycles.firstOrNull;
      _datePreset = null;
      _startDate = null;
      _endDate = null;
      _categoryIds.clear();
      _memberId = null;
      _paymentMethodId = null;
      _onlyPending = null;
      _tabController.index = 0;
    });
  }

  void _save() {
    final filter = widget.initialFilter.copyWith(
      periodMode: _periodMode,
      selectedCycle: _periodMode == PeriodMode.cycle ? _selectedCycle : null,
      clearCycle: _periodMode != PeriodMode.cycle,
      datePreset: _periodMode == PeriodMode.dateRange ? _datePreset : null,
      startDate: _periodMode == PeriodMode.dateRange ? _startDate : null,
      endDate: _periodMode == PeriodMode.dateRange ? _endDate : null,
      clearDates: _periodMode != PeriodMode.dateRange,
      categoryIds: _categoryIds,
      memberId: _memberId,
      clearMember: _memberId == null,
      paymentMethodId: _paymentMethodId,
      clearPaymentMethod: _paymentMethodId == null,
      onlyPending: _onlyPending,
      clearOnlyPending: _onlyPending == null,
    );
    widget.onApply(filter);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, bottomInset + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Barra de título do Modal
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Filtros de Transações',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                TextButton(
                  onPressed: _reset,
                  child: const Text('Limpar Tudo'),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Abas de Período: Por Ciclo vs Por Datas
            Container(
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: TabBar(
                controller: _tabController,
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                indicator: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(10),
                ),
                labelColor: Colors.white,
                unselectedLabelColor: isDark ? Colors.grey.shade400 : Colors.grey.shade700,
                tabs: const [
                  Tab(text: 'Por Ciclo'),
                  Tab(text: 'Por Datas'),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Conteúdo da Aba selecionada
            if (_periodMode == PeriodMode.cycle) ...[
              const Text(
                'Selecione o Ciclo Financeiro:',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Container(
                constraints: const BoxConstraints(maxHeight: 180),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: widget.availableCycles.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (ctx, i) {
                    final cycle = widget.availableCycles[i];
                    final isSelected = _selectedCycle?.startDate == cycle.startDate;
                    final isCurrent = i == 0;

                    return ListTile(
                      dense: true,
                      title: Text(
                        cycle.monthName,
                        style: TextStyle(
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          color: isSelected ? AppColors.primary : null,
                        ),
                      ),
                      subtitle: Text(
                        '${_dateFormat.format(cycle.startDate)} até ${_dateFormat.format(cycle.endDate)}',
                        style: const TextStyle(fontSize: 11),
                      ),
                      trailing: isCurrent
                          ? Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text('Atual', style: TextStyle(fontSize: 10, color: AppColors.primary, fontWeight: FontWeight.bold)),
                            )
                          : (isSelected ? const Icon(Icons.check, size: 18, color: AppColors.primary) : null),
                      onTap: () => setState(() => _selectedCycle = cycle),
                    );
                  },
                ),
              ),
            ] else ...[
              const Text(
                'Atalhos de Período:',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final p in [
                    DateRangePreset.thisMonth,
                    DateRangePreset.last30Days,
                    DateRangePreset.last90Days,
                    DateRangePreset.thisYear,
                  ])
                    ChoiceChip(
                      label: Text(p.label, style: const TextStyle(fontSize: 12)),
                      selected: _datePreset == p,
                      onSelected: (_) => _applyPreset(p),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _pickCustomDateRange,
                icon: const Icon(Icons.date_range_outlined, size: 16),
                label: Text(
                  (_startDate != null && _endDate != null)
                      ? '${_dateFormat.format(_startDate!)} — ${_dateFormat.format(_endDate!)}'
                      : 'Selecionar Intervalo Personalizado',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],

            const Divider(height: 28),

            // Seção de Categorias
            const Text(
              'Categorias:',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final cat in widget.categories)
                  FilterChip(
                    label: Text(cat.name, style: const TextStyle(fontSize: 12)),
                    selected: _categoryIds.contains(cat.id),
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          _categoryIds.add(cat.id);
                        } else {
                          _categoryIds.remove(cat.id);
                        }
                      });
                    },
                  ),
              ],
            ),

            const Divider(height: 28),

            // Seção de Morador / Pagador
            if (widget.members.isNotEmpty) ...[
              const Text(
                'Quem Pagou ou Aportou:',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  ChoiceChip(
                    label: const Text('Todos', style: TextStyle(fontSize: 12)),
                    selected: _memberId == null,
                    onSelected: (_) => setState(() => _memberId = null),
                  ),
                  for (final m in widget.members)
                    ChoiceChip(
                      label: Text(m.name.split(' ').first, style: const TextStyle(fontSize: 12)),
                      selected: _memberId == m.id,
                      onSelected: (selected) => setState(() => _memberId = selected ? m.id : null),
                    ),
                ],
              ),
              const Divider(height: 28),
            ],

            // Seção de Formas de Pagamento
            if (widget.paymentMethods.isNotEmpty) ...[
              const Text(
                'Forma de Pagamento:',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  ChoiceChip(
                    label: const Text('Todas', style: TextStyle(fontSize: 12)),
                    selected: _paymentMethodId == null,
                    onSelected: (_) => setState(() => _paymentMethodId = null),
                  ),
                  for (final pm in widget.paymentMethods)
                    ChoiceChip(
                      label: Text(pm.name, style: const TextStyle(fontSize: 12)),
                      selected: _paymentMethodId == pm.id,
                      onSelected: (selected) => setState(() => _paymentMethodId = selected ? pm.id : null),
                    ),
                ],
              ),
              const Divider(height: 28),
            ],

            // Toggle de Apenas Pendentes
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Apenas despesas pendentes', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
              subtitle: const Text('Oculta contas já pagas e baixadas', style: TextStyle(fontSize: 11)),
              value: _onlyPending == true,
              onChanged: (val) => setState(() => _onlyPending = val ? true : null),
            ),
            const SizedBox(height: 16),

            // Botão Aplicar Filtros
            FilledButton(
              onPressed: _save,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Aplicar Filtros', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}
