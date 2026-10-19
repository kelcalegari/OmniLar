part of 'settings_page.dart';

/// Grupos dos Ajustes. No celular cada um abre a própria página; no PC ficam
/// na coluna da esquerda e o conteúdo do escolhido aparece ao lado.
enum _SettingsGroup {
  house(
    'Casa',
    'Moradores, convites, ciclo e chave Pix',
    Icons.home_outlined,
    AppColors.primary,
  ),
  split(
    'Divisão das despesas',
    'Modelo de rateio e categorias',
    Icons.tune_rounded,
    AppColors.accent,
  ),
  payments(
    'Pagamentos e contas',
    'Cartões, contas fixas e faturas',
    Icons.credit_card_rounded,
    Colors.orange,
  ),
  app(
    'Aplicativo',
    'Assistente, aparência e histórico',
    Icons.settings_outlined,
    Colors.blueGrey,
  ),
  account(
    'Conta e segurança',
    'E-mail, senha e meus padrões de lançamento',
    Icons.lock_outline_rounded,
    Colors.teal,
  );

  const _SettingsGroup(this.title, this.description, this.icon, this.color);

  final String title;
  final String description;
  final IconData icon;
  final Color color;
}

const _reminderGroupLabels = {
  'bills': 'Contas a vencer e atrasadas',
  'invoices': 'Faturas do cartão',
  'cycle': 'Ciclo e aportes',
  'loans': 'Parcelas de empréstimo',
  'tasks': 'Tarefas',
  'budget': 'Alertas de orçamento',
};
const _weekdayNames = ['Domingo', 'Segunda', 'Terça', 'Quarta', 'Quinta', 'Sexta', 'Sábado'];

extension _SettingsGroupViews on _SettingsPageState {
  /// Índice dos grupos. Com [selected] (PC) o grupo aberto fica destacado; sem
  /// ele (celular) cada linha leva à página do grupo.
  Widget _groupIndex(
    BuildContext context,
    AuthState authState, {
    required _SettingsGroup? selected,
    required ValueChanged<_SettingsGroup> onSelect,
    required Widget searchField,
    Widget? searchResults,
  }) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _profileCard(context, authState),
        const SizedBox(height: 12),
        searchField,
        const SizedBox(height: 12),
        // Com algo digitado, os resultados tomam o lugar da lista de grupos
        if (searchResults != null)
          searchResults
        else
        Container(
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Material(
            color: Colors.transparent,
            child: Column(
              children: [
                for (final group in _SettingsGroup.values) ...[
                  if (group.index > 0) const Divider(height: 1, indent: 64),
                  ListTile(
                    selected: group == selected,
                    selectedTileColor: AppColors.primary.withValues(alpha: 0.08),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    leading: CircleAvatar(
                      radius: 18,
                      backgroundColor: group.color.withValues(alpha: 0.15),
                      child: Icon(group.icon, size: 18, color: group.color),
                    ),
                    title: Text(
                      group.title,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(group.description, style: const TextStyle(fontSize: 12)),
                    trailing: selected == null
                        ? const Icon(Icons.chevron_right_rounded)
                        : null,
                    onTap: () => onSelect(group),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        _signOutButton(context),
        const SizedBox(height: 32),
      ],
    );
  }

  /// Conteúdo de um grupo: o que está configurado fica à vista e cada bloco
  /// tem o botão que abre a edição.
  Widget _groupContent(
    BuildContext context,
    _SettingsGroup group,
    AuthState authState,
    FinanceState financeState,
  ) {
    final blocks = switch (group) {
      _SettingsGroup.house => _houseBlocks(context, authState, financeState),
      _SettingsGroup.split => _splitBlocks(context, financeState),
      _SettingsGroup.payments => _paymentBlocks(context, financeState),
      _SettingsGroup.app => _appBlocks(context),
      _SettingsGroup.account => <Widget>[
          _LaunchDefaultsBlock(financeState: financeState),
          _ReminderPrefsBlock(financeState: financeState),
          const AccountSecurityPanel(),
        ],
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < blocks.length; i++) ...[
          if (i > 0) const SizedBox(height: 16),
          blocks[i],
        ],
      ],
    );
  }

  // --- Casa ---

  List<Widget> _houseBlocks(
    BuildContext context,
    AuthState authState,
    FinanceState financeState,
  ) {
    final house = authState.house;
    final cycleDay = house?.cycleStartDay ?? 5;

    return [
      _panel(
        context,
        title: 'Membros da Casa e Convites',
        children: [
          _HouseMembersBlock(
            houseId: house?.id ?? '',
            members: financeState.members,
            currentUserId: authState.user?.id,
          ),
        ],
      ),
      _CycleDayBlock(
        house: house,
        cycleDay: cycleDay,
        cycleLabel: financeState.currentCycle.label,
        canChange: _canDo(financeState, HousePermissionAction.changeCycleDay),
      ),
      _HousePixKeyBlock(house: house),
      _PermissionsBlock(financeState: financeState),
      _HouseLabelsBlock(financeState: financeState),
      _shoppingListsPanel(context, financeState),
    ];
  }

  /// Se o morador logado pode fazer [action] (permissões por ação da casa, 0103).
  bool _canDo(FinanceState financeState, HousePermissionAction action) =>
      financeState.canDo(action, sl<AuthRepository>().currentUser?.id);

  /// Categoria e divisão da despesa criada ao fechar a compra de cada lista
  /// (0101). Quem edita listas (qualquer morador) muda.
  Widget _shoppingListsPanel(BuildContext context, FinanceState financeState) {
    final cubit = sl<ShoppingCubit>();
    return BlocBuilder<ShoppingCubit, ShoppingState>(
      bloc: cubit,
      builder: (context, shopping) {
        if (shopping.status == ShoppingCubitStatus.initial) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (cubit.state.status == ShoppingCubitStatus.initial) cubit.loadShoppingData();
          });
        }
        return _panel(
          context,
          title: 'Compras de mercado por lista',
          children: [
            if (shopping.lists.isEmpty)
              _emptyLine('Nenhuma lista de compras ainda.')
            else
              for (final list in shopping.lists)
                _ShoppingListDefaultsTile(
                  key: ValueKey('shopping_list_defaults_${list.id}'),
                  list: list,
                  financeState: financeState,
                  cubit: cubit,
                ),
            if (shopping.lists.isNotEmpty)
              _emptyLine('Ao fechar a compra, a despesa usa a categoria e a divisão da lista.'),
          ],
        );
      },
    );
  }
  // --- Divisão das despesas ---

  List<Widget> _splitBlocks(BuildContext context, FinanceState financeState) {
    final financeCubit = context.read<FinanceCubit>();
    final members = financeState.members;
    final categories = financeState.categories;
    // O editor é recriado (com os valores novos) quando algo que ele mostra muda
    final editorVersion = [
      financeState.splitModel,
      for (final m in members)
        '${m.id}:${m.name}:${m.role}:${m.defaultSplitPercent}:${m.defaultFixedAmountCents}',
      for (final c in categories) '${c.id}:${c.name}:${c.ownerMemberId}:${c.defaultSplit?.toJson()}',
    ].join('|');

    return [
      _panel(
        context,
        title: 'Modelos de Rateio',
        children: [
          _KeptEditor(
            key: ValueKey(editorVersion),
            create: _splitModelsEditor,
          ),
        ],
      ),
      _NewMemberSplitBlock(financeState: financeState),
      _IncomeSplitBlock(financeState: financeState),
      _ApprovalThresholdBlock(financeState: financeState),
      _PlanningSettingsBlock(financeState: financeState),
      _FolegoParamsBlock(financeState: financeState),
      _BudgetAlertBlock(financeState: financeState),
      _ClosingDefaultsBlock(financeState: financeState),
      _InitialBalanceBlock(financeState: financeState),
      _panel(
        context,
        title: 'Categorias de Gastos',
        actionLabel: 'Nova categoria',
        onAction: () => _showCategoryFormDialog(context, financeCubit, members),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'Categoria com dono é 100% dele e sobrepõe o modelo de rateio. Toque em uma categoria para editar.',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ),
          if (categories.isEmpty)
            _emptyLine('Nenhuma categoria cadastrada.')
          else
            for (final cat in categories)
              _categoryLine(context, financeCubit, cat, members, categories.length),
        ],
      ),
    ];
  }
  /// Resumo da divisão padrão da categoria (0097); null quando não tem.
  String? _categorySplitLabel(ExpenseCategory cat, List<HouseMember> members) {
    final rule = cat.defaultSplit?.toRule(members);
    if (rule == null) return null;
    String name(String id) => members.firstWhere((m) => m.id == id).name.split(' ').first;
    String percent(double value) => value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toString();
    if (rule.type == SplitType.categoryOwner) {
      return 'Divisão padrão: ${name(rule.singleResponsibleMemberId!)} responde por tudo';
    }
    return 'Divisão padrão: ${rule.percentages!.entries.map((e) => '${name(e.key)} ${percent(e.value)}%').join(' / ')}';
  }

  Widget _categoryLine(
    BuildContext context,
    FinanceCubit financeCubit,
    ExpenseCategory cat,
    List<HouseMember> members,
    int totalCategories,
  ) {
    final owner = members.where((m) => m.id == cat.ownerMemberId).firstOrNull;
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.only(left: 16, right: 4),
      leading: CircleAvatar(
        radius: 14,
        backgroundColor: AppColors.primary.withValues(alpha: 0.15),
        child: const Icon(Icons.label_outline_rounded, size: 14, color: AppColors.primary),
      ),
      title: Text(cat.name, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
        owner != null
            ? 'Responsável: 100% ${owner.name}'
            : (_categorySplitLabel(cat, members) ?? 'Divisão padrão da casa'),
        style: TextStyle(
          fontSize: 12,
          color: owner != null ? AppColors.accent : Colors.grey,
          fontWeight: owner != null ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      onTap: () => _showCategoryFormDialog(context, financeCubit, members, existing: cat),
      trailing: PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert, size: 20, color: Colors.grey),
        tooltip: 'Opções',
        onSelected: (action) {
          if (action == 'edit') {
            _showCategoryFormDialog(context, financeCubit, members, existing: cat);
          } else if (action == 'delete') {
            _confirmDeleteCategory(context, financeCubit, cat, totalCategories);
          }
        },
        itemBuilder: (context) => const [
          PopupMenuItem(
            value: 'edit',
            child: Row(
              children: [
                Icon(Icons.edit_outlined, size: 18, color: AppColors.primary),
                SizedBox(width: 8),
                Text('Editar'),
              ],
            ),
          ),
          PopupMenuItem(
            value: 'delete',
            child: Row(
              children: [
                Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.debtRed),
                SizedBox(width: 8),
                Text('Excluir', style: TextStyle(color: AppColors.debtRed)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- Pagamentos e contas ---

  List<Widget> _paymentBlocks(BuildContext context, FinanceState financeState) {
    final members = financeState.members;
    String ownerLabel(PaymentMethod pm) =>
        members.where((m) => m.id == pm.ownerMemberId).firstOrNull?.name.split(' ').first ?? 'Casa';
    String detail(PaymentMethod pm) {
      if (pm.isCreditCard && pm.closingDay != null && pm.dueDay != null) {
        final payer = members.where((m) => m.id == pm.usualInvoicePayerId).firstOrNull;
        final payerText = payer == null ? '' : ' • Fatura: ${payer.name.split(' ').first}';
        return 'Fecha dia ${pm.closingDay} • Vence dia ${pm.dueDay}$payerText';
      }
      return switch (pm.type) {
        PaymentMethodType.card => 'Cartão de crédito',
        PaymentMethodType.vr => 'Vale-refeição',
        PaymentMethodType.va => 'Vale-alimentação',
        PaymentMethodType.pix => 'Pix',
        PaymentMethodType.cash => 'Dinheiro',
        _ => 'Conta / débito imediato',
      };
    }

    final financeCubit = context.read<FinanceCubit>();
    final methods = financeState.paymentMethods;

    return [
      _panel(
        context,
        title: 'Cartões e Formas de Pagamento',
        actionLabel: 'Cadastrar Cartão ou VR',
        onAction: () => _showAddPaymentMethodDialog(context, financeCubit, members),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'Cartões de crédito e vales da casa, com fechamento e vencimento da fatura. Toque em uma forma para editar.',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ),
          if (methods.isEmpty)
            _emptyLine('Nenhuma forma de pagamento cadastrada.')
          else
            for (final pm in methods)
              _paymentMethodLine(
                context,
                financeCubit,
                pm,
                members,
                detail: detail(pm),
                ownerLabel: ownerLabel(pm),
                totalMethods: methods.length,
              ),
        ],
      ),
      _ImportParamsBlock(financeState: financeState),
      _panel(
        context,
        title: 'Assinaturas & Contas Fixas',
        children: [_recurringExpensesEditor(context)],
      ),
    ];
  }

  Widget _paymentMethodLine(
    BuildContext context,
    FinanceCubit financeCubit,
    PaymentMethod pm,
    List<HouseMember> members, {
    required String detail,
    required String ownerLabel,
    required int totalMethods,
  }) {
    final (IconData icon, Color color) = pm.isCreditCard
        ? (Icons.credit_card_rounded, Colors.orange)
        : (pm.isBenefit
              ? (Icons.restaurant_rounded, Colors.green)
              : (Icons.account_balance_wallet_rounded, AppColors.primary));

    void edit() => _showPaymentMethodFormDialog(
      context: context,
      financeCubit: financeCubit,
      members: members,
      existingPm: pm,
    );

    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.only(left: 16, right: 4),
      leading: CircleAvatar(
        radius: 14,
        backgroundColor: color.withValues(alpha: 0.15),
        child: Icon(icon, size: 14, color: color),
      ),
      title: Text(pm.name, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(detail, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      onTap: edit,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: (pm.ownerMemberId != null ? AppColors.primary : Colors.grey)
                  .withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              ownerLabel,
              style: TextStyle(
                color: pm.ownerMemberId != null ? AppColors.primary : Colors.grey,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 20, color: Colors.grey),
            tooltip: 'Opções',
            onSelected: (action) {
              if (action == 'import') {
                context.push(Uri(path: '/importar', queryParameters: {'origem': pm.id}).toString());
              } else if (action == 'invoice') {
                showAdaptiveModal(
                  context: context,
                  maxWidth: 480,
                  child: CardInvoicePaymentSheet(
                    card: pm,
                    memberNames: {for (final m in members) m.id: m.name.split(' ').first},
                    repository: sl<FinanceRepository>(),
                    financeCubit: financeCubit,
                    cycleSchedule: financeCubit.cycleSchedule,
                    isCycleClosed: (cycle) async =>
                        (await sl<SettlementRepository>().getSettlementSummary(cycle)).status ==
                        SettlementStatus.settled,
                  ),
                );
              } else if (action == 'edit') {
                edit();
              } else if (action == 'delete') {
                _confirmDeletePaymentMethod(context, financeCubit, pm, totalMethods);
              }
            },
            itemBuilder: (context) => [
              if (pm.type == PaymentMethodType.card || pm.type == PaymentMethodType.account)
                PopupMenuItem(
                  value: 'import',
                  child: Row(
                    children: [
                      const Icon(Icons.upload_file_rounded, size: 18, color: AppColors.primary),
                      const SizedBox(width: 8),
                      Text(pm.type == PaymentMethodType.card ? 'Importar fatura' : 'Importar extrato'),
                    ],
                  ),
                ),
              if (pm.type == PaymentMethodType.card)
                const PopupMenuItem(
                  value: 'invoice',
                  child: Row(
                    children: [
                      Icon(Icons.receipt_long_outlined, size: 18, color: AppColors.primary),
                      SizedBox(width: 8),
                      Text('Registrar pagamento da fatura'),
                    ],
                  ),
                ),
              const PopupMenuItem(
                value: 'edit',
                child: Row(
                  children: [
                    Icon(Icons.edit_outlined, size: 18, color: AppColors.primary),
                    SizedBox(width: 8),
                    Text('Editar'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.debtRed),
                    SizedBox(width: 8),
                    Text('Excluir', style: TextStyle(color: AppColors.debtRed)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --- Aplicativo ---

  List<Widget> _appBlocks(BuildContext context) {
    ThemeCubit? themeCubit;
    try {
      themeCubit = context.watch<ThemeCubit>();
    } catch (_) {}
    final themeMode = themeCubit?.state ?? ThemeMode.system;

    return [
      _panel(
        context,
        title: 'Notificações',
        children: const [PushSettingsBlock(), Divider(height: 1), NotificationPreferencesBlock()],
      ),
      _panel(
        context,
        title: 'Assistente IA',
        children: [
          const AiKeyConfigSheet(embedded: true),
          Container(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
            ),
            child: const Row(
              children: [
                Icon(Icons.shield_outlined, color: AppColors.primary, size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Privacidade: fotos e arquivos vão inteiros para a IA do Google (Gemini) e não ficam guardados; '
                    'nos textos enviados, CPF e número de cartão são mascarados antes. Detalhes na Política de privacidade.',
                    style: TextStyle(fontSize: 12, color: AppColors.primary),
                  ),
                ),
              ],
            ),
          ),
          const AiConsentTile(),
        ],
      ),
      _panel(
        context,
        title: 'Aparência & Tema',
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Escolha a forma como o Omni Lar é exibido.',
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
                const SizedBox(height: 12),
                SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(
                      value: ThemeMode.system,
                      icon: Icon(Icons.brightness_auto_rounded),
                      label: Text('Sistema'),
                    ),
                    ButtonSegment(
                      value: ThemeMode.light,
                      icon: Icon(Icons.light_mode_rounded),
                      label: Text('Claro'),
                    ),
                    ButtonSegment(
                      value: ThemeMode.dark,
                      icon: Icon(Icons.dark_mode_rounded),
                      label: Text('Escuro'),
                    ),
                  ],
                  selected: {themeMode},
                  onSelectionChanged: themeCubit == null
                      ? null
                      : (selection) => themeCubit!.setThemeMode(selection.first),
                ),
              ],
            ),
          ),
        ],
      ),
      _panel(
        context,
        title: 'Auditoria e Histórico da Casa',
        actionLabel: 'Atualizar',
        onAction: _reloadAudit,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'Quem criou, editou ou excluiu cada lançamento da casa.',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ),
          AuditLogView(key: ValueKey(_auditVersion)),
        ],
      ),
    ];
  }

  // --- Peças comuns ---

  BoxDecoration _cardDecoration(BuildContext context) => BoxDecoration(
    color: Theme.of(context).cardColor,
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
  );

  /// Bloco com título, botão de edição e o que está configurado hoje.
  Widget _panel(
    BuildContext context, {
    required String title,
    String? actionLabel,
    VoidCallback? onAction,
    required List<Widget> children,
  }) {
    return Container(
      decoration: _cardDecoration(context),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: onAction,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                    ),
                    if (actionLabel != null)
                      TextButton(onPressed: onAction, child: Text(actionLabel))
                    else
                      const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            const SizedBox(height: 8),
            ...children,
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// Cartão só com opções (sem resumo), separadas por linha.
  Widget _tileCard(BuildContext context, List<Widget> tiles) {
    return Container(
      decoration: _cardDecoration(context),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: Column(
          children: [
            for (var i = 0; i < tiles.length; i++) ...[
              if (i > 0) const Divider(height: 1, indent: 56),
              tiles[i],
            ],
          ],
        ),
      ),
    );
  }

  Widget _emptyLine(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Text(text, style: const TextStyle(color: Colors.grey, fontSize: 13)),
    );
  }
}

/// Bloco inline para exibir e alterar o Dia de Início do Ciclo Financeiro.
class _CycleDayBlock extends StatefulWidget {
  final House? house;
  final int cycleDay;
  final String cycleLabel;
  final bool canChange;

  const _CycleDayBlock({
    required this.house,
    required this.cycleDay,
    required this.cycleLabel,
    required this.canChange,
  });

  @override
  State<_CycleDayBlock> createState() => _CycleDayBlockState();
}

class _CycleDayBlockState extends State<_CycleDayBlock> {
  bool _expanded = false;
  late int _selectedDay;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _selectedDay = widget.cycleDay;
  }

  @override
  void didUpdateWidget(_CycleDayBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cycleDay != widget.cycleDay && !_expanded) {
      _selectedDay = widget.cycleDay;
    }
  }

  String _two(int n) => n.toString().padLeft(2, '0');
  String _formatDate(DateTime d) => '${_two(d.day)}/${_two(d.month)}/${d.year}';

  @override
  Widget build(BuildContext context) {
    final schedule = widget.house?.cycleSchedule ?? CycleSchedule(widget.cycleDay);

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: widget.canChange ? () => setState(() => _expanded = !_expanded) : null,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Ciclo Financeiro',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                    ),
                    if (widget.canChange)
                      TextButton(
                        onPressed: () => setState(() => _expanded = !_expanded),
                        child: Text(_expanded ? 'Fechar' : 'Alterar'),
                      )
                    else
                      const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('Começa todo dia', style: TextStyle(fontSize: 14)),
                  ),
                  Text(
                    '${widget.cycleDay}',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('Ciclo em andamento', style: TextStyle(fontSize: 14)),
                  ),
                  Text(
                    widget.cycleLabel,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            if (_expanded) ...[
              const Divider(height: 16),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Dia de Início do Ciclo',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'O ciclo financeiro da casa agrupa todas as faturas e despesas de um período para calcular o acerto mensal.',
                      style: TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          'Todo dia $_selectedDay',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      key: const ValueKey('cycle_day_dropdown'),
                      initialValue: _selectedDay,
                      decoration: InputDecoration(
                        labelText: 'Selecione o Dia de Início',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      items: List.generate(31, (i) => i + 1)
                          .map(
                            (d) => DropdownMenuItem(
                              value: d,
                              child: Text('Dia $d de cada mês'),
                            ),
                          )
                          .toList(),
                      onChanged: (val) {
                        if (val != null) setState(() => _selectedDay = val);
                      },
                    ),
                    const SizedBox(height: 10),
                    Builder(
                      builder: (_) {
                        if (_selectedDay == widget.cycleDay) {
                          return Text(
                            'Período do ciclo: dia $_selectedDay ao dia ${_selectedDay == 1 ? 31 : _selectedDay - 1} do mês seguinte.',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.teal,
                              fontWeight: FontWeight.w500,
                            ),
                          );
                        }
                        final now = DateTime.now();
                        final after = schedule.withChange(schedule.planChange(now, _selectedDay));
                        final current = after.cycleFor(now);
                        final transition = after.next(current);
                        final regular = after.next(transition);
                        return Text(
                          'O ciclo atual não muda: termina em ${_formatDate(current.endDate)}. '
                          'O seguinte vai de ${_formatDate(transition.startDate)} a ${_formatDate(transition.endDate)}, '
                          'e a partir de ${_formatDate(regular.startDate)} os ciclos começam todo dia $_selectedDay.',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.teal,
                            fontWeight: FontWeight.w500,
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => setState(() {
                            _selectedDay = widget.cycleDay;
                            _expanded = false;
                          }),
                          child: const Text('Cancelar'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: _isSaving || widget.house == null || _selectedDay == widget.cycleDay
                              ? null
                              : () async {
                                  setState(() => _isSaving = true);
                                  final messenger = ScaffoldMessenger.of(context);
                                  final authCubit = context.read<AuthCubit>();
                                  final financeCubit = context.read<FinanceCubit>();
                                  try {
                                    await authCubit.updateHouse(
                                      houseId: widget.house!.id,
                                      cycleStartDay: _selectedDay,
                                    );
                                    if (mounted) {
                                      setState(() {
                                        _isSaving = false;
                                        _expanded = false;
                                      });
                                    }
                                    financeCubit.loadCycleData();
                                    messenger.showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Dia de início alterado para $_selectedDay. Vale a partir do próximo ciclo. 📅',
                                        ),
                                      ),
                                    );
                                  } catch (err) {
                                    if (mounted) setState(() => _isSaving = false);
                                    messenger.showSnackBar(
                                      SnackBar(
                                        backgroundColor: AppColors.debtRed,
                                        content: Text('Não foi possível alterar o dia de início do ciclo: $err'),
                                      ),
                                    );
                                  }
                                },
                          style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                          child: const Text('Salvar'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// Bloco inline para exibir e cadastrar/alterar a Chave Pix da Casa.
class _HousePixKeyBlock extends StatefulWidget {
  final House? house;

  const _HousePixKeyBlock({required this.house});

  @override
  State<_HousePixKeyBlock> createState() => _HousePixKeyBlockState();
}

class _HousePixKeyBlockState extends State<_HousePixKeyBlock> {
  bool _expanded = false;
  late TextEditingController _pixKeyController;
  late TextEditingController _holderNameController;
  late TextEditingController _bankController;
  late String _selectedType;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _initControllers();
  }

  void _initControllers() {
    _pixKeyController = TextEditingController(text: widget.house?.pixKey ?? '');
    _holderNameController = TextEditingController(text: widget.house?.pixKeyHolderName ?? '');
    _bankController = TextEditingController(text: widget.house?.pixKeyBank ?? '');
    _selectedType = widget.house?.pixKeyType ?? 'email';
  }

  @override
  void didUpdateWidget(_HousePixKeyBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.house?.pixKey != widget.house?.pixKey && !_expanded) {
      _initControllers();
    }
  }

  @override
  void dispose() {
    _pixKeyController.dispose();
    _holderNameController.dispose();
    _bankController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final house = widget.house;
    final hasPix = house?.pixKey != null && house!.pixKey!.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Chave Pix da Casa',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                    ),
                    TextButton(
                      onPressed: () => setState(() => _expanded = !_expanded),
                      child: Text(_expanded ? 'Fechar' : (hasPix ? 'Alterar' : 'Cadastrar')),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            const SizedBox(height: 8),
            if (hasPix) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text('Chave', style: TextStyle(fontSize: 14)),
                    ),
                    Flexible(
                      child: Text(
                        house.pixKey!,
                        textAlign: TextAlign.end,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text('Titular', style: TextStyle(fontSize: 14)),
                    ),
                    Flexible(
                      child: Text(
                        house.pixKeyHolderName ?? 'Caixa da Casa',
                        textAlign: TextAlign.end,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ] else
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Text(
                  'Nenhuma chave cadastrada. É ela que recebe os aportes do Caixa da Casa.',
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
              ),
            if (_expanded) ...[
              const Divider(height: 16),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Cadastre a Chave Pix da conta conjunta ou do responsável financeiro da residência. Ela será usada automaticamente em Aportes e liquidações do Super Pix.',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      key: const ValueKey('pix_key_type_dropdown'),
                      value: _selectedType,
                      decoration: InputDecoration(
                        labelText: 'Tipo de Chave Pix',
                        prefixIcon: const Icon(Icons.category_outlined),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'cpf', child: Text('CPF')),
                        DropdownMenuItem(value: 'cnpj', child: Text('CNPJ')),
                        DropdownMenuItem(value: 'email', child: Text('E-mail')),
                        DropdownMenuItem(value: 'phone', child: Text('Telefone / Celular')),
                        DropdownMenuItem(value: 'random', child: Text('Chave Aleatória (EVP)')),
                        DropdownMenuItem(value: 'other', child: Text('Outro')),
                      ],
                      onChanged: (val) {
                        if (val != null) setState(() => _selectedType = val);
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const ValueKey('house_pix_key_field'),
                      controller: _pixKeyController,
                      decoration: InputDecoration(
                        labelText: 'Chave Pix da Residência',
                        hintText: 'Ex: financeiro.casa@gmail.com',
                        prefixIcon: const Icon(Icons.vpn_key_outlined, color: Colors.teal),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const ValueKey('house_pix_holder_field'),
                      controller: _holderNameController,
                      decoration: InputDecoration(
                        labelText: 'Nome do Titular / Favorecido',
                        hintText: 'Ex: Caixa Nossa Casa ou Nome do Gestor',
                        prefixIcon: const Icon(Icons.person_outline_rounded),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const ValueKey('house_pix_bank_field'),
                      controller: _bankController,
                      decoration: InputDecoration(
                        labelText: 'Banco / Instituição (opcional)',
                        hintText: 'Ex: Nubank, Inter, Banco do Brasil',
                        prefixIcon: const Icon(Icons.account_balance_outlined),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => setState(() {
                            _initControllers();
                            _expanded = false;
                          }),
                          child: const Text('Cancelar'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          key: const Key('house_pix_save'),
                          onPressed: _isSaving || house == null
                              ? null
                              : () async {
                                  setState(() => _isSaving = true);
                                  final newPixKey = _pixKeyController.text.trim();
                                  final newHolderName = _holderNameController.text.trim();
                                  final newBank = _bankController.text.trim();
                                  final messenger = ScaffoldMessenger.of(context);

                                  try {
                                    await context.read<AuthCubit>().updateHouse(
                                      houseId: house.id,
                                      pixKey: newPixKey,
                                      pixKeyType: _selectedType,
                                      pixKeyHolderName: newHolderName,
                                      pixKeyBank: newBank,
                                    );
                                    if (mounted) {
                                      setState(() {
                                        _isSaving = false;
                                        _expanded = false;
                                      });
                                    }
                                    messenger.showSnackBar(
                                      const SnackBar(
                                        backgroundColor: AppColors.creditGreen,
                                        content: Text('Chave Pix da Casa salva com sucesso! 🏠✨'),
                                      ),
                                    );
                                  } catch (err) {
                                    if (mounted) setState(() => _isSaving = false);
                                    messenger.showSnackBar(
                                      SnackBar(
                                        backgroundColor: AppColors.debtRed,
                                        content: Text('Erro ao salvar Chave Pix da Casa: $err'),
                                      ),
                                    );
                                  }
                                },
                          style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                          child: const Text('Salvar'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

String _roleLabel(String role) => switch (role) {
  'owner' => 'Dono',
  'admin' => 'Administrador',
  _ => 'Morador',
};

/// Moradores da casa e geração de convite, dentro do grupo "Casa".
/// A lista vem do estado financeiro (atualiza sozinha quando alguém entra); o
/// e-mail de cada um é buscado à parte. O convite só é criado quando pedem.
class _HouseMembersBlock extends StatefulWidget {
  final String houseId;
  final List<HouseMember> members;
  final String? currentUserId;

  const _HouseMembersBlock({
    required this.houseId,
    required this.members,
    required this.currentUserId,
  });

  @override
  State<_HouseMembersBlock> createState() => _HouseMembersBlockState();
}

class _HouseMembersBlockState extends State<_HouseMembersBlock> {
  final _authRepo = sl<AuthRepository>();
  Map<String, String> _emailByMember = const {};
  String? _inviteCode;
  String? _inviteError;
  bool _creatingInvite = false;

  @override
  void initState() {
    super.initState();
    _loadEmails();
  }

  @override
  void didUpdateWidget(_HouseMembersBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    final before = oldWidget.members.map((m) => m.id).join(',');
    final now = widget.members.map((m) => m.id).join(',');
    if (before != now || oldWidget.houseId != widget.houseId) _loadEmails();
  }

  Future<void> _loadEmails() async {
    if (_authRepo.isDemoMode || widget.houseId.isEmpty) return;
    try {
      final infos = await _authRepo.getHouseMembers(widget.houseId);
      if (!mounted) return;
      setState(() {
        _emailByMember = {
          for (final info in infos)
            if ((info.profile?.email ?? '').isNotEmpty) info.userId: info.profile!.email,
        };
      });
    } catch (_) {
      // Sem o e-mail a lista continua útil: nome, papel e Pix vêm do estado
    }
  }

  Future<void> _createInvite() async {
    setState(() {
      _creatingInvite = true;
      _inviteError = null;
    });
    try {
      final code = await _authRepo.createHouseInvite(widget.houseId);
      if (!mounted) return;
      setState(() => _inviteCode = code);
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _inviteError =
            'Não foi possível gerar o convite. Só o dono ou um administrador pode convidar.',
      );
    } finally {
      if (mounted) setState(() => _creatingInvite = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final myRole = widget.members.where((m) => m.id == widget.currentUserId).firstOrNull?.role;
    final canInvite =
        _authRepo.isDemoMode || myRole == null || myRole == 'owner' || myRole == 'admin';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.members.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Text(
              'Nenhum morador carregado.',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
          )
        else
          for (final m in widget.members) _memberTile(m),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: _inviteCard(context, canInvite),
        ),
      ],
    );
  }

  Widget _memberTile(HouseMember m) {
    final color = m.role == 'owner' ? AppColors.primary : AppColors.accent;
    final email = _emailByMember[m.id];
    final hasPix = m.pixKey != null && m.pixKey!.isNotEmpty;
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: color,
        child: Text(
          m.name.isNotEmpty ? m.name[0].toUpperCase() : '?',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
        ),
      ),
      title: Text(m.name, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: (email == null && !hasPix)
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (email != null) Text(email, style: const TextStyle(fontSize: 12)),
                if (hasPix)
                  Text(
                    'Pix: ${m.pixKey}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.creditGreen,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          _roleLabel(m.role),
          style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _inviteCard(BuildContext context, bool canInvite) {
    final code = _inviteCode;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.vpn_key_rounded, color: AppColors.primary, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: code == null
                    ? const Text(
                        'Convidar alguém para a casa',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Código de Convite:',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            code,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 2,
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
              ),
              if (code != null)
                IconButton(
                  icon: const Icon(Icons.copy_rounded, color: AppColors.primary),
                  tooltip: 'Copiar Código',
                  onPressed: () => copyWithFeedback(
                    context,
                    code,
                    onCopied: SnackBar(
                      content: Text('Código $code copiado para a área de transferência!'),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            !canInvite
                ? 'Só o dono ou um administrador da casa pode gerar convites.'
                : (code == null
                      ? 'Gere um código e envie para a pessoa. Cada código vale para uma pessoa só.'
                      : 'Este código vale para uma pessoa só. Para convidar outra, gere um novo.'),
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),
          if (_inviteError != null) ...[
            const SizedBox(height: 6),
            Text(_inviteError!, style: const TextStyle(color: AppColors.debtRed, fontSize: 12)),
          ],
          if (canInvite) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: _creatingInvite ? null : _createInvite,
                style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                icon: _creatingInvite
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.add_link_rounded, size: 18),
                label: Text(code == null ? 'Gerar código de convite' : 'Gerar outro código'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}


/// Um resultado da busca dos Ajustes: leva a um grupo, abre algo direto ou
/// as duas coisas (o grupo e, por cima, a edição do item).
class _SearchEntry {
  final String title;
  final String where;
  final IconData icon;
  final List<String> keywords;
  final _SettingsGroup? group;
  final VoidCallback? action;

  const _SearchEntry({
    required this.title,
    required this.where,
    required this.icon,
    this.keywords = const [],
    this.group,
    this.action,
  });
}

/// Minúsculas e sem acento, para "cartao" achar "Cartão".
String _searchable(String text) {
  const from = 'áàâãäéèêëíìîïóòôõöúùûüçñ';
  const to = 'aaaaaeeeeiiiiooooouuuucn';
  final buffer = StringBuffer();
  for (final char in text.toLowerCase().split('')) {
    final i = from.indexOf(char);
    buffer.write(i >= 0 ? to[i] : char);
  }
  return buffer.toString();
}

extension _SettingsSearch on _SettingsPageState {
  /// Tudo o que a busca encontra: as opções fixas de cada grupo e o que a casa
  /// cadastrou (moradores, categorias, formas de pagamento, contas fixas).
  List<_SearchEntry> _searchEntries(
    BuildContext context,
    AuthState authState,
    FinanceState financeState,
  ) {
    _SearchEntry option(
      _SettingsGroup group,
      String title,
      IconData icon,
      List<String> keywords,
    ) => _SearchEntry(
      title: title,
      where: group.title,
      icon: icon,
      keywords: keywords,
      group: group,
    );

    final financeCubit = context.read<FinanceCubit>();
    return [
      _SearchEntry(
        title: 'Meu perfil',
        where: 'Conta',
        icon: Icons.person_outline_rounded,
        keywords: const ['nome', 'pix pessoal', 'perfil'],
        action: () => _showEditProfileModal(context, authState.user),
      ),
      _SearchEntry(
        title: 'Sair da Conta',
        where: 'Conta',
        icon: Icons.logout_rounded,
        keywords: const ['logout', 'deslogar', 'trocar de conta'],
        action: () => _confirmSignOut(context),
      ),
      option(_SettingsGroup.account, 'E-mail de acesso', Icons.alternate_email_rounded, const [
        'email', 'e-mail', 'trocar email', 'login', 'conta', 'google',
      ]),
      option(_SettingsGroup.account, 'Senha', Icons.password_rounded, const [
        'trocar senha', 'alterar senha', 'seguranca', 'conta',
      ]),
      option(_SettingsGroup.account, 'Meus padrões de lançamento', Icons.bolt_rounded, const [
        'padrao', 'quem paga', 'forma de pagamento', 'categoria', 'lancamento', 'gasto novo',
      ]),
      option(_SettingsGroup.house, 'Membros da Casa e Convites', Icons.people_outline_rounded, const [
        'moradores', 'pessoas', 'convidar', 'codigo', 'convite', 'administrador', 'dono',
      ]),
      option(_SettingsGroup.house, 'Ciclo Financeiro', Icons.calendar_today_outlined, const [
        'dia de inicio', 'fechamento', 'mes', 'periodo',
      ]),
      option(_SettingsGroup.house, 'Chave Pix da Casa', Icons.pix_rounded, const [
        'caixa', 'titular', 'aporte',
      ]),
      option(_SettingsGroup.split, 'Modelos de Rateio', Icons.tune_rounded, const [
        'divisao', 'porcentagem', 'percentual', 'aportes fixos', 'balde', 'por categoria', 'dividir',
      ]),
      option(_SettingsGroup.split, 'Renda e divisão', Icons.account_balance_wallet_outlined, const [
        'renda', 'salario', 'proporcional', 'divisao por renda', 'privacidade', 'quem ve',
      ]),
      option(_SettingsGroup.split, 'Padrões do fechamento', Icons.fact_check_outlined, const [
        'sobra', 'destino da sobra', 'excedente', 'balde', 'pagou menos', 'emprestimo', 'caixinha', 'fechamento',
      ]),
      option(_SettingsGroup.split, 'Saldo inicial da casa', Icons.savings_outlined, const [
        'reserva guardada', 'saldo na conta', 'dinheiro guardado', 'comecar', 'caixa',
      ]),
      option(_SettingsGroup.split, 'Categorias de Gastos', Icons.category_outlined, const [
        'categoria', 'dono', 'responsavel',
      ]),
      option(_SettingsGroup.payments, 'Cartões e Formas de Pagamento', Icons.credit_card_rounded, const [
        'cartao', 'credito', 'vale', 'vr', 'va', 'fatura', 'vencimento', 'dinheiro', 'debito',
      ]),
      option(_SettingsGroup.payments, 'Assinaturas & Contas Fixas', Icons.repeat_rounded, const [
        'recorrente', 'conta fixa', 'mensalidade', 'aluguel', 'internet',
      ]),
      // A importação tem página própria: o resultado leva direto a ela
      _SearchEntry(
        title: 'Importar Fatura e Extratos',
        where: 'Página de importação',
        icon: Icons.upload_file_rounded,
        keywords: const ['importar', 'extrato', 'conciliacao', 'dividir fatura', 'ofx', 'csv'],
        action: () => context.push('/importar'),
      ),
      option(_SettingsGroup.app, 'Notificações', Icons.notifications_rounded, const [
        'push', 'avisos', 'alertas', 'iphone', 'tela de inicio',
      ]),
      option(_SettingsGroup.app, 'Assistente IA', Icons.auto_awesome_rounded, const [
        'inteligencia artificial', 'chave', 'gemini', 'privacidade',
      ]),
      option(_SettingsGroup.app, 'Aparência & Tema', Icons.palette_outlined, const [
        'escuro', 'claro', 'modo noturno', 'cores',
      ]),
      option(_SettingsGroup.app, 'Auditoria e Histórico da Casa', Icons.history_edu_rounded, const [
        'registro', 'quem alterou', 'log',
      ]),
      for (final m in financeState.members)
        _SearchEntry(
          title: m.name,
          where: 'Morador • ${_SettingsGroup.house.title}',
          icon: Icons.person_outline_rounded,
          group: _SettingsGroup.house,
        ),
      // Categoria, forma de pagamento e conta fixa abrem direto a edição
      for (final c in financeState.categories)
        _SearchEntry(
          title: c.name,
          where: 'Categoria • ${_SettingsGroup.split.title}',
          icon: Icons.label_outline_rounded,
          group: _SettingsGroup.split,
          action: () => _showCategoryFormDialog(
            context,
            financeCubit,
            financeState.members,
            existing: c,
          ),
        ),
      for (final pm in financeState.paymentMethods)
        _SearchEntry(
          title: pm.name,
          where: 'Forma de pagamento • ${_SettingsGroup.payments.title}',
          icon: Icons.credit_card_rounded,
          group: _SettingsGroup.payments,
          action: () => _showPaymentMethodFormDialog(
            context: context,
            financeCubit: financeCubit,
            members: financeState.members,
            existingPm: pm,
          ),
        ),
      for (final e in financeState.recurringSeries)
        _SearchEntry(
          title: e.title,
          where: 'Conta fixa • ${_SettingsGroup.payments.title}',
          icon: Icons.repeat_rounded,
          group: _SettingsGroup.payments,
          action: () => showAdaptiveModal(
            context: context,
            maxWidth: 540,
            child: BlocProvider<FinanceCubit>.value(
              value: financeCubit,
              child: AddExpensePage(expenseToEdit: e),
            ),
          ),
        ),
    ];
  }

  /// Resultados da busca; null quando não há nada digitado.
  Widget? _searchResults(
    BuildContext context,
    String query,
    AuthState authState,
    FinanceState financeState, {
    required ValueChanged<_SearchEntry> onPick,
  }) {
    final wanted = _searchable(query.trim());
    if (wanted.isEmpty) return null;

    final matches = _searchEntries(context, authState, financeState).where((entry) {
      if (_searchable(entry.title).contains(wanted)) return true;
      return entry.keywords.any((k) => _searchable(k).contains(wanted));
    }).toList();

    if (matches.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: _cardDecoration(context),
        child: Text(
          'Nada encontrado para "${query.trim()}".',
          style: const TextStyle(color: Colors.grey),
        ),
      );
    }

    return _tileCard(context, [
      for (final entry in matches)
        ListTile(
          dense: true,
          leading: Icon(entry.icon, color: AppColors.primary),
          title: Text(entry.title, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(entry.where, style: const TextStyle(fontSize: 12)),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => onPick(entry),
        ),
    ]);
  }
}

/// Bloco inline para exibir e alterar Meus Padrões de Lançamento.
class _LaunchDefaultsBlock extends StatefulWidget {
  final FinanceState financeState;

  const _LaunchDefaultsBlock({required this.financeState});

  @override
  State<_LaunchDefaultsBlock> createState() => _LaunchDefaultsBlockState();
}

class _LaunchDefaultsBlockState extends State<_LaunchDefaultsBlock> {
  bool _expanded = false;
  late LaunchPayer _payer;
  String? _methodId;
  String? _categoryId;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _initValues();
  }

  void _initValues() {
    final saved = widget.financeState.memberSettings;
    final methods = widget.financeState.paymentMethods;
    final categories = widget.financeState.categories;
    _payer = saved.launchPayer ?? LaunchPayer.me;
    _methodId = methods.any((p) => p.id == saved.launchPaymentMethodId) ? saved.launchPaymentMethodId : null;
    _categoryId = categories.any((c) => c.id == saved.launchCategoryId) ? saved.launchCategoryId : null;
  }

  @override
  void didUpdateWidget(_LaunchDefaultsBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_expanded && oldWidget.financeState.memberSettings != widget.financeState.memberSettings) {
      _initValues();
    }
  }

  static String _launchPayerLabel(LaunchPayer? payer) =>
      payer == LaunchPayer.house ? 'Caixa da casa' : 'Eu';

  @override
  Widget build(BuildContext context) {
    final settings = widget.financeState.memberSettings;
    final methods = widget.financeState.paymentMethods;
    final categories = widget.financeState.categories;
    final method = methods.where((p) => p.id == settings.launchPaymentMethodId).firstOrNull;
    final category = categories.where((c) => c.id == settings.launchCategoryId).firstOrNull;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Meus padrões de lançamento',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                    ),
                    TextButton(
                      onPressed: () => setState(() => _expanded = !_expanded),
                      child: Text(_expanded ? 'Fechar' : 'Alterar'),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  const Expanded(child: Text('Quem paga', style: TextStyle(fontSize: 14))),
                  Text(_launchPayerLabel(settings.launchPayer), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  const Expanded(child: Text('Forma de pagamento', style: TextStyle(fontSize: 14))),
                  Flexible(
                    child: Text(
                      settings.launchPayer == LaunchPayer.house
                          ? 'Conta da casa'
                          : (method?.name ?? 'A última que usei'),
                      textAlign: TextAlign.end,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  const Expanded(child: Text('Categoria', style: TextStyle(fontSize: 14))),
                  Flexible(
                    child: Text(
                      category?.name ?? 'A que mais uso',
                      textAlign: TextAlign.end,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Text(
                'Valem só para você, ao lançar um gasto. Na hora dá para mudar tudo.',
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
            ),
            if (_expanded) ...[
              const Divider(height: 16),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'O gasto novo já abre com estas escolhas. Só para você; os outros moradores têm os deles.',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 12),
                    const Text('Quem paga', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      children: [
                        for (final option in LaunchPayer.values)
                          ChoiceChip(
                            key: ValueKey('launch_payer_${option.name}'),
                            label: Text(_launchPayerLabel(option)),
                            selected: _payer == option,
                            onSelected: (_) => setState(() => _payer = option),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text('Forma de pagamento', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 6),
                    if (_payer == LaunchPayer.house)
                      Text('Pelo Caixa da casa, a forma é a conta da casa.', style: TextStyle(fontSize: 12, color: Colors.grey.shade600))
                    else
                      DropdownButtonFormField<String?>(
                        key: const ValueKey('launch_payment_method'),
                        value: _methodId,
                        isExpanded: true,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                        onChanged: (v) => setState(() => _methodId = v),
                        items: [
                          const DropdownMenuItem(value: null, child: Text('A última que usei')),
                          for (final pm in methods)
                            DropdownMenuItem(value: pm.id, child: Text(pm.name, overflow: TextOverflow.ellipsis)),
                        ],
                      ),
                    const SizedBox(height: 12),
                    const Text('Categoria', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String?>(
                      key: const ValueKey('launch_category'),
                      value: _categoryId,
                      isExpanded: true,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      onChanged: (v) => setState(() => _categoryId = v),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('A que mais uso')),
                        for (final cat in categories)
                          DropdownMenuItem(value: cat.id, child: Text(cat.name, overflow: TextOverflow.ellipsis)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => setState(() {
                            _initValues();
                            _expanded = false;
                          }),
                          child: const Text('Cancelar'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: _isSaving
                              ? null
                              : () async {
                                  setState(() => _isSaving = true);
                                  final messenger = ScaffoldMessenger.of(context);
                                  final next = settings.withLaunchDefaults(
                                    payer: _payer == LaunchPayer.house ? LaunchPayer.house : null,
                                    paymentMethodId: _payer == LaunchPayer.house ? null : _methodId,
                                    categoryId: _categoryId,
                                  );
                                  final ok = next == settings ||
                                      await context.read<FinanceCubit>().updateMemberSettings(next);
                                  if (mounted) {
                                    setState(() {
                                      _isSaving = false;
                                      _expanded = false;
                                    });
                                  }
                                  showSaveFeedback(
                                    messenger,
                                    ok: ok,
                                    success: 'Seus padrões de lançamento foram atualizados.',
                                  );
                                },
                          style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                          child: const Text('Salvar'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// Bloco inline para exibir e alterar Meus Lembretes.
class _ReminderPrefsBlock extends StatefulWidget {
  final FinanceState financeState;

  const _ReminderPrefsBlock({required this.financeState});

  @override
  State<_ReminderPrefsBlock> createState() => _ReminderPrefsBlockState();
}

class _ReminderPrefsBlockState extends State<_ReminderPrefsBlock> {
  bool _expanded = false;
  late int _alertHour;
  late int _weeklyDay;
  late int _weeklyHour;
  late Set<String> _muted;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _initValues();
  }

  void _initValues() {
    final saved = widget.financeState.memberSettings;
    _alertHour = saved.alertHour;
    _weeklyDay = saved.weeklyDay;
    _weeklyHour = saved.weeklyHour;
    _muted = Set<String>.of(saved.mutedReminders);
  }

  @override
  void didUpdateWidget(_ReminderPrefsBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_expanded && oldWidget.financeState.memberSettings != widget.financeState.memberSettings) {
      _initValues();
    }
  }

  static String _hourLabel(int hour) => '${hour.toString().padLeft(2, '0')}h';

  @override
  Widget build(BuildContext context) {
    final settings = widget.financeState.memberSettings;
    final currentMuted = settings.mutedReminders;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Meus lembretes',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                    ),
                    TextButton(
                      onPressed: () => setState(() => _expanded = !_expanded),
                      child: Text(_expanded ? 'Fechar' : 'Alterar'),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  const Expanded(child: Text('Lembretes do dia a partir das', style: TextStyle(fontSize: 14))),
                  Text(_hourLabel(settings.alertHour), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  const Expanded(child: Text('Silenciados', style: TextStyle(fontSize: 14))),
                  Flexible(
                    child: Text(
                      currentMuted.isEmpty
                          ? 'Nenhum'
                          : [for (final g in MemberSettings.reminderGroups) if (currentMuted.contains(g)) _reminderGroupLabels[g]!]
                              .join(', '),
                      textAlign: TextAlign.end,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  const Expanded(child: Text('Resumo semanal', style: TextStyle(fontSize: 14))),
                  Text(
                    '${_weekdayNames[settings.weeklyDay]}, ${_hourLabel(settings.weeklyHour)}',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Text(
                'Valem só para você, no fuso da casa. Avisos essenciais chegam sempre.',
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
            ),
            if (_expanded) ...[
              const Divider(height: 16),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Lembretes do dia a partir das', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<int>(
                      key: const ValueKey('alert_hour'),
                      value: _alertHour,
                      isExpanded: true,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      onChanged: (v) => setState(() => _alertHour = v ?? _alertHour),
                      items: [
                        for (var h = 0; h < 24; h++) DropdownMenuItem(value: h, child: Text(_hourLabel(h))),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const Text('Receber lembretes de', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 4),
                    for (final group in MemberSettings.reminderGroups)
                      SwitchListTile(
                        key: ValueKey('reminder_$group'),
                        contentPadding: EdgeInsets.zero,
                        title: Text(_reminderGroupLabels[group]!, style: const TextStyle(fontSize: 14)),
                        value: !_muted.contains(group),
                        onChanged: (on) => setState(() => on ? _muted.remove(group) : _muted.add(group)),
                      ),
                    const SizedBox(height: 10),
                    const Text('Resumo semanal', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: DropdownButtonFormField<int>(
                            key: const ValueKey('weekly_day'),
                            value: _weeklyDay,
                            isExpanded: true,
                            decoration: InputDecoration(
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            ),
                            onChanged: (v) => setState(() => _weeklyDay = v ?? _weeklyDay),
                            items: [
                              for (var d = 0; d < 7; d++) DropdownMenuItem(value: d, child: Text(_weekdayNames[d])),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: DropdownButtonFormField<int>(
                            key: const ValueKey('weekly_hour'),
                            value: _weeklyHour,
                            isExpanded: true,
                            decoration: InputDecoration(
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            ),
                            onChanged: (v) => setState(() => _weeklyHour = v ?? _weeklyHour),
                            items: [
                              for (var h = 0; h < 24; h++) DropdownMenuItem(value: h, child: Text(_hourLabel(h))),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => setState(() {
                            _initValues();
                            _expanded = false;
                          }),
                          child: const Text('Cancelar'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: _isSaving
                              ? null
                              : () async {
                                  setState(() => _isSaving = true);
                                  final messenger = ScaffoldMessenger.of(context);
                                  final next = settings.withAlertPrefs(
                                    alertHour: _alertHour,
                                    muted: _muted,
                                    weeklyDay: _weeklyDay,
                                    weeklyHour: _weeklyHour,
                                  );
                                  final ok = next == settings ||
                                      await context.read<FinanceCubit>().updateMemberSettings(next);
                                  if (mounted) {
                                    setState(() {
                                      _isSaving = false;
                                      _expanded = false;
                                    });
                                  }
                                  showSaveFeedback(messenger, ok: ok, success: 'Seus lembretes foram atualizados.');
                                },
                          style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                          child: const Text('Salvar'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// Bloco inline para exibir e alterar a política de divisão para novos membros.
class _NewMemberSplitBlock extends StatefulWidget {
  final FinanceState financeState;

  const _NewMemberSplitBlock({required this.financeState});

  @override
  State<_NewMemberSplitBlock> createState() => _NewMemberSplitBlockState();
}

class _NewMemberSplitBlockState extends State<_NewMemberSplitBlock> {
  bool _expanded = false;
  late NewMemberSplitPolicy _choice;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _choice = widget.financeState.houseSettings.newMemberSplitPolicy;
  }

  @override
  void didUpdateWidget(_NewMemberSplitBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_expanded && oldWidget.financeState.houseSettings.newMemberSplitPolicy != widget.financeState.houseSettings.newMemberSplitPolicy) {
      _choice = widget.financeState.houseSettings.newMemberSplitPolicy;
    }
  }

  bool _canEdit() =>
      widget.financeState.canDo(HousePermissionAction.editConfigurations, sl<AuthRepository>().currentUser?.id);

  @override
  Widget build(BuildContext context) {
    final policy = widget.financeState.houseSettings.newMemberSplitPolicy;
    final isAdmin = _canEdit();
    final withoutShare = widget.financeState.members.length > 1
        ? widget.financeState.members.where((m) => m.defaultSplitPercent <= 0).toList()
        : <HouseMember>[];

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: isAdmin ? () => setState(() => _expanded = !_expanded) : null,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Divisão para quem entra',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                    ),
                    if (isAdmin)
                      TextButton(
                        onPressed: () => setState(() => _expanded = !_expanded),
                        child: Text(_expanded ? 'Fechar' : 'Alterar'),
                      )
                    else
                      const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  const Expanded(child: Text('Ao entrar um morador', style: TextStyle(fontSize: 14))),
                  Text(policy.label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            if (policy == NewMemberSplitPolicy.ask && withoutShare.isNotEmpty)
              Padding(
                key: const Key('new_member_split_notice'),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Text(
                  '${withoutShare.map((m) => m.name).join(', ')} ainda não tem parte na divisão. '
                  'Defina os percentuais em Modelos de Rateio.',
                  style: const TextStyle(color: AppColors.folegoWarning, fontSize: 13),
                ),
              ),
            if (!isAdmin)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Text('Só administradores mudam esta escolha.', style: TextStyle(color: Colors.grey, fontSize: 13)),
              ),
            if (_expanded) ...[
              const Divider(height: 16),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final p in NewMemberSplitPolicy.values)
                      ListTile(
                        key: ValueKey('new_member_policy_${p.dbValue}'),
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          _choice == p ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                          color: _choice == p ? AppColors.primary : Colors.grey,
                        ),
                        title: Text(p.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(p.description, style: const TextStyle(fontSize: 12)),
                        onTap: () => setState(() => _choice = p),
                      ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => setState(() {
                            _choice = policy;
                            _expanded = false;
                          }),
                          child: const Text('Cancelar'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: _isSaving
                              ? null
                              : () async {
                                  setState(() => _isSaving = true);
                                  final messenger = ScaffoldMessenger.of(context);
                                  final ok = _choice == policy ||
                                      await context.read<FinanceCubit>().updateHouseSettings(newMemberSplitPolicy: _choice);
                                  if (mounted) {
                                    setState(() {
                                      _isSaving = false;
                                      _expanded = false;
                                    });
                                  }
                                  showSaveFeedback(messenger, ok: ok, success: 'Divisão para quem entra atualizada.');
                                },
                          style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                          child: const Text('Salvar'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// Bloco inline para exibir e alterar renda e critérios de divisão por renda.
class _IncomeSplitBlock extends StatefulWidget {
  final FinanceState financeState;

  const _IncomeSplitBlock({required this.financeState});

  @override
  State<_IncomeSplitBlock> createState() => _IncomeSplitBlockState();
}

class _IncomeSplitBlockState extends State<_IncomeSplitBlock> {
  bool _expanded = false;
  bool _editingMyIncome = false;
  late SplitBasis _basis;
  late IncomeVisibility _visibility;
  late int _myIncomeCents;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _initValues();
  }

  void _initValues() {
    final settings = widget.financeState.houseSettings;
    final currentUserId = sl<AuthRepository>().currentUser?.id;
    final myIncome = widget.financeState.memberIncomes[currentUserId];
    _basis = settings.splitBasis;
    _visibility = settings.incomeVisibility;
    _myIncomeCents = myIncome?.cents ?? 0;
  }

  @override
  void didUpdateWidget(_IncomeSplitBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_expanded && !_editingMyIncome) {
      _initValues();
    }
  }

  bool _canEdit() =>
      widget.financeState.canDo(HousePermissionAction.editConfigurations, sl<AuthRepository>().currentUser?.id);

  @override
  Widget build(BuildContext context) {
    final settings = widget.financeState.houseSettings;
    final currentUserId = sl<AuthRepository>().currentUser?.id;
    final isAdmin = _canEdit();
    final myIncome = widget.financeState.memberIncomes[currentUserId];
    final others = [
      for (final m in widget.financeState.members)
        if (m.id != currentUserId && widget.financeState.memberIncomes.containsKey(m.id)) m,
    ];

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: isAdmin ? () => setState(() => _expanded = !_expanded) : null,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Renda e divisão',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                    ),
                    if (isAdmin)
                      TextButton(
                        onPressed: () => setState(() => _expanded = !_expanded),
                        child: Text(_expanded ? 'Fechar' : 'Alterar'),
                      )
                    else
                      const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  const Expanded(child: Text('Divisão padrão', style: TextStyle(fontSize: 14))),
                  Text(settings.splitBasis.label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  const Expanded(child: Text('Quem vê a renda', style: TextStyle(fontSize: 14))),
                  Text(settings.incomeVisibility.label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  const Expanded(child: Text('Minha renda mensal', style: TextStyle(fontSize: 14))),
                  Text(myIncome?.format() ?? 'Não informada', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            if (!_editingMyIncome)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: TextButton(
                    key: const Key('my_income_button'),
                    onPressed: () => setState(() => _editingMyIncome = true),
                    child: Text(myIncome == null ? 'Informar minha renda' : 'Alterar minha renda'),
                  ),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Usada só para calcular a divisão proporcional à renda. Quem pode ver este valor é escolha da casa.',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 8),
                    MoneyInputField(
                      key: const ValueKey('my_income_field'),
                      initialValue: Money(_myIncomeCents),
                      label: 'Renda mensal',
                      onChanged: (v) => setState(() => _myIncomeCents = v.cents),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (myIncome != null)
                          TextButton(
                            onPressed: _isSaving
                                ? null
                                : () async {
                                    setState(() => _isSaving = true);
                                    final messenger = ScaffoldMessenger.of(context);
                                    final ok = await context.read<FinanceCubit>().setMyIncome(null);
                                    if (mounted) {
                                      setState(() {
                                        _isSaving = false;
                                        _editingMyIncome = false;
                                        _myIncomeCents = 0;
                                      });
                                    }
                                    showSaveFeedback(messenger, ok: ok, success: 'Renda removida.');
                                  },
                            child: const Text('Remover'),
                          ),
                        TextButton(
                          onPressed: () => setState(() {
                            _myIncomeCents = myIncome?.cents ?? 0;
                            _editingMyIncome = false;
                          }),
                          child: const Text('Cancelar'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: _isSaving || _myIncomeCents <= 0
                              ? null
                              : () async {
                                  setState(() => _isSaving = true);
                                  final messenger = ScaffoldMessenger.of(context);
                                  final ok = await context.read<FinanceCubit>().setMyIncome(Money(_myIncomeCents));
                                  if (mounted) {
                                    setState(() {
                                      _isSaving = false;
                                      _editingMyIncome = false;
                                    });
                                  }
                                  showSaveFeedback(messenger, ok: ok, success: 'Renda atualizada.');
                                },
                          style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                          child: const Text('Salvar'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            for (final m in others)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Row(
                  children: [
                    Expanded(child: Text('Renda de ${m.name}', style: const TextStyle(fontSize: 14))),
                    Text(widget.financeState.memberIncomes[m.id]!.format(), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            if (others.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Text('A renda dos outros moradores é privada: só o percentual calculado aparece na divisão.', style: TextStyle(color: Colors.grey, fontSize: 13)),
              ),
            if (settings.splitBasis == SplitBasis.income)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Text('Enquanto algum morador não informar a renda, vale o rateio atual.', style: TextStyle(color: Colors.grey, fontSize: 13)),
              ),
            if (_expanded) ...[
              const Divider(height: 16),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Divisão padrão', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    for (final b in SplitBasis.values)
                      ListTile(
                        key: ValueKey('split_basis_${b.dbValue}'),
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          _basis == b ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                          color: _basis == b ? AppColors.primary : Colors.grey,
                        ),
                        title: Text(b.label),
                        onTap: () => setState(() => _basis = b),
                      ),
                    const Divider(),
                    const Text('Quem vê a renda', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    for (final v in IncomeVisibility.values)
                      ListTile(
                        key: ValueKey('income_visibility_${v.dbValue}'),
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          _visibility == v ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                          color: _visibility == v ? AppColors.primary : Colors.grey,
                        ),
                        title: Text(v.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(v.description, style: const TextStyle(fontSize: 12)),
                        onTap: () => setState(() => _visibility = v),
                      ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => setState(() {
                            _basis = settings.splitBasis;
                            _visibility = settings.incomeVisibility;
                            _expanded = false;
                          }),
                          child: const Text('Cancelar'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: _isSaving
                              ? null
                              : () async {
                                  setState(() => _isSaving = true);
                                  final messenger = ScaffoldMessenger.of(context);
                                  final changed = _basis != settings.splitBasis || _visibility != settings.incomeVisibility;
                                  final ok = !changed ||
                                      await context.read<FinanceCubit>().updateHouseSettings(
                                            splitBasis: _basis != settings.splitBasis ? _basis : null,
                                            incomeVisibility: _visibility != settings.incomeVisibility ? _visibility : null,
                                          );
                                  if (mounted) {
                                    setState(() {
                                      _isSaving = false;
                                      _expanded = false;
                                    });
                                  }
                                  showSaveFeedback(messenger, ok: ok, success: 'Renda e divisão atualizadas.');
                                },
                          style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                          child: const Text('Salvar'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// Bloco inline para exibir e alterar limite de aprovação de empréstimos.
class _ApprovalThresholdBlock extends StatefulWidget {
  final FinanceState financeState;

  const _ApprovalThresholdBlock({required this.financeState});

  @override
  State<_ApprovalThresholdBlock> createState() => _ApprovalThresholdBlockState();
}

class _ApprovalThresholdBlockState extends State<_ApprovalThresholdBlock> {
  bool _expanded = false;
  late int _cents;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _cents = widget.financeState.houseSettings.approvalThresholdCents ?? 0;
  }

  @override
  void didUpdateWidget(_ApprovalThresholdBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_expanded && oldWidget.financeState.houseSettings.approvalThresholdCents != widget.financeState.houseSettings.approvalThresholdCents) {
      _cents = widget.financeState.houseSettings.approvalThresholdCents ?? 0;
    }
  }

  bool _canEdit() =>
      widget.financeState.canDo(HousePermissionAction.editConfigurations, sl<AuthRepository>().currentUser?.id);

  @override
  Widget build(BuildContext context) {
    final threshold = widget.financeState.houseSettings.approvalThresholdCents;
    final canEdit = _canEdit();

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: canEdit ? () => setState(() => _expanded = !_expanded) : null,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Aprovação por valor',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                    ),
                    if (canEdit)
                      TextButton(
                        onPressed: () => setState(() => _expanded = !_expanded),
                        child: Text(_expanded ? 'Fechar' : 'Alterar'),
                      )
                    else
                      const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  const Expanded(child: Text('Empréstimos acima de', style: TextStyle(fontSize: 14))),
                  Text(
                    threshold == null ? 'Sem limite' : Money(threshold).format(),
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Text(
                threshold == null
                    ? 'Hoje nenhum empréstimo pede aprovação por causa do valor.'
                    : 'Acima desse valor, o empréstimo fica fora do fechamento até um administrador aprovar.',
                style: const TextStyle(color: Colors.grey, fontSize: 13),
              ),
            ),
            if (_expanded) ...[
              const Divider(height: 16),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Empréstimo acima deste valor só entra no fechamento do ciclo depois que um administrador aprova.',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 12),
                    MoneyInputField(
                      key: const ValueKey('approval_threshold_field'),
                      initialValue: Money(_cents),
                      label: 'Valor limite',
                      onChanged: (v) => setState(() => _cents = v.cents),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (threshold != null)
                          TextButton(
                            key: const ValueKey('approval_threshold_clear'),
                            onPressed: _isSaving
                                ? null
                                : () async {
                                    setState(() => _isSaving = true);
                                    final messenger = ScaffoldMessenger.of(context);
                                    final ok = await context
                                        .read<FinanceCubit>()
                                        .updateHouseSettings(clearApprovalThreshold: true);
                                    if (mounted) {
                                      setState(() {
                                        _isSaving = false;
                                        _expanded = false;
                                        _cents = 0;
                                      });
                                    }
                                    showSaveFeedback(messenger, ok: ok, success: 'Aprovação por valor desligada.');
                                  },
                            child: const Text('Sem limite'),
                          ),
                        TextButton(
                          onPressed: () => setState(() {
                            _cents = threshold ?? 0;
                            _expanded = false;
                          }),
                          child: const Text('Cancelar'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: _isSaving || _cents <= 0
                              ? null
                              : () async {
                                  setState(() => _isSaving = true);
                                  final messenger = ScaffoldMessenger.of(context);
                                  final ok = await context
                                      .read<FinanceCubit>()
                                      .updateHouseSettings(approvalThresholdCents: _cents);
                                  if (mounted) {
                                    setState(() {
                                      _isSaving = false;
                                      _expanded = false;
                                    });
                                  }
                                  showSaveFeedback(messenger, ok: ok, success: 'Limite de aprovação atualizado.');
                                },
                          style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                          child: const Text('Salvar'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}



/// Bloco inline para exibir e alterar permissões da casa.
class _PermissionsBlock extends StatefulWidget {
  final FinanceState financeState;

  const _PermissionsBlock({required this.financeState});

  @override
  State<_PermissionsBlock> createState() => _PermissionsBlockState();
}

class _PermissionsBlockState extends State<_PermissionsBlock> {
  bool _expanded = false;
  late HousePermissions _draft;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _draft = widget.financeState.houseSettings.permissions;
  }

  @override
  void didUpdateWidget(_PermissionsBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_expanded && oldWidget.financeState.houseSettings.permissions != widget.financeState.houseSettings.permissions) {
      _draft = widget.financeState.houseSettings.permissions;
    }
  }

  bool _isAdmin() {
    final currentUserId = sl<AuthRepository>().currentUser?.id;
    final me = widget.financeState.members.where((m) => m.id == currentUserId).firstOrNull;
    return me?.role == 'owner' || me?.role == 'admin';
  }

  String _permissionSummary(ActionPermission permission) {
    if (permission.level != PermissionLevel.chosen) return permission.level.label;
    final names = [
      for (final m in widget.financeState.members)
        if (permission.members.contains(m.id)) m.name,
    ];
    return names.isEmpty ? 'Só administradores' : 'Admins e ${names.join(', ')}';
  }

  @override
  Widget build(BuildContext context) {
    if (!_isAdmin()) return const SizedBox.shrink();
    final permissions = widget.financeState.houseSettings.permissions;
    final choosable = [
      for (final m in widget.financeState.members)
        if (m.role != 'owner' && m.role != 'admin') m,
    ];

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Permissões',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                    ),
                    TextButton(
                      onPressed: () => setState(() => _expanded = !_expanded),
                      child: Text(_expanded ? 'Fechar' : 'Alterar'),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            const SizedBox(height: 8),
            for (final action in HousePermissionAction.values)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Row(
                  children: [
                    Expanded(child: Text(action.label, style: const TextStyle(fontSize: 14))),
                    Text(_permissionSummary(permissions.of(action)), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            if (_expanded) ...[
              const Divider(height: 16),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Administradores sempre podem tudo. Escolha quem mais pode fazer cada ação.',
                      style: TextStyle(fontSize: 12),
                    ),
                    for (final action in HousePermissionAction.values) ...[
                      const SizedBox(height: 14),
                      Text(action.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text(action.description, style: const TextStyle(fontSize: 11)),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final level in PermissionLevel.values)
                            ChoiceChip(
                              key: ValueKey('perm_${action.dbValue}_${level.dbValue}'),
                              label: Text(level.label),
                              selected: _draft.of(action).level == level,
                              onSelected: (_) => setState(() {
                                _draft = _draft.withAction(
                                  action,
                                  ActionPermission(
                                    level,
                                    members: level == PermissionLevel.chosen ? _draft.of(action).members : const [],
                                  ),
                                );
                              }),
                            ),
                        ],
                      ),
                      if (_draft.of(action).level == PermissionLevel.chosen) ...[
                        const SizedBox(height: 6),
                        if (choosable.isEmpty)
                          const Text('Não há outros moradores além dos administradores.', style: TextStyle(fontSize: 12))
                        else
                          Wrap(
                            spacing: 8,
                            children: [
                              for (final m in choosable)
                                FilterChip(
                                  key: ValueKey('perm_${action.dbValue}_member_${m.id}'),
                                  label: Text(m.name),
                                  selected: _draft.of(action).members.contains(m.id),
                                  onSelected: (on) => setState(() {
                                    final current = _draft.of(action).members;
                                    _draft = _draft.withAction(
                                      action,
                                      ActionPermission(
                                        PermissionLevel.chosen,
                                        members: [
                                          for (final id in current)
                                            if (id != m.id) id,
                                          if (on) m.id,
                                        ],
                                      ),
                                    );
                                  }),
                                ),
                            ],
                          ),
                      ],
                    ],
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => setState(() {
                            _draft = widget.financeState.houseSettings.permissions;
                            _expanded = false;
                          }),
                          child: const Text('Cancelar'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          key: const Key('permissions_save'),
                          onPressed: _isSaving
                              ? null
                              : () async {
                                  if (_draft == permissions) {
                                    setState(() => _expanded = false);
                                    return;
                                  }
                                  setState(() => _isSaving = true);
                                  final messenger = ScaffoldMessenger.of(context);
                                  final ok = await context.read<FinanceCubit>().updateHouseSettings(permissions: _draft);
                                  if (mounted) {
                                    setState(() {
                                      _isSaving = false;
                                      _expanded = false;
                                    });
                                  }
                                  showSaveFeedback(messenger, ok: ok, success: 'Permissões atualizadas.');
                                },
                          style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                          child: const Text('Salvar'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// Bloco inline para exibir e alterar nomes do Caixa e unidades de compra.
class _HouseLabelsBlock extends StatefulWidget {
  final FinanceState financeState;

  const _HouseLabelsBlock({required this.financeState});

  @override
  State<_HouseLabelsBlock> createState() => _HouseLabelsBlockState();
}

class _HouseLabelsBlockState extends State<_HouseLabelsBlock> {
  bool _expanded = false;
  late TextEditingController _cashController;
  late TextEditingController _unitsController;
  String? _error;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final saved = widget.financeState.houseSettings;
    _cashController = TextEditingController(text: saved.cashLabel ?? '');
    _unitsController = TextEditingController(text: saved.shoppingUnits.join(', '));
  }

  @override
  void didUpdateWidget(_HouseLabelsBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_expanded && oldWidget.financeState.houseSettings != widget.financeState.houseSettings) {
      final saved = widget.financeState.houseSettings;
      _cashController.text = saved.cashLabel ?? '';
      _unitsController.text = saved.shoppingUnits.join(', ');
    }
  }

  @override
  void dispose() {
    _cashController.dispose();
    _unitsController.dispose();
    super.dispose();
  }

  bool _canEdit() =>
      widget.financeState.canDo(HousePermissionAction.editConfigurations, sl<AuthRepository>().currentUser?.id);

  @override
  Widget build(BuildContext context) {
    final settings = widget.financeState.houseSettings;
    final isAdmin = _canEdit();

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: isAdmin ? () => setState(() => _expanded = !_expanded) : null,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Nomes e compras',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                    ),
                    if (isAdmin)
                      TextButton(
                        onPressed: () => setState(() => _expanded = !_expanded),
                        child: Text(_expanded ? 'Fechar' : 'Alterar'),
                      )
                    else
                      const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  const Expanded(child: Text('Nome do Caixa nas telas', style: TextStyle(fontSize: 14))),
                  Text(settings.cashName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  const Expanded(child: Text('Unidades de compra', style: TextStyle(fontSize: 14))),
                  Text(settings.shoppingUnits.join(', '), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            if (!isAdmin)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Text('Só administradores mudam estes nomes.', style: TextStyle(color: Colors.grey, fontSize: 13)),
              ),
            if (_expanded) ...[
              const Divider(height: 16),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      key: const ValueKey('cash_label_field'),
                      controller: _cashController,
                      maxLength: 30,
                      decoration: InputDecoration(
                        labelText: 'Nome do Caixa',
                        helperText: 'Vazio volta para "${HouseSettings.defaultCashLabel}".',
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      key: const ValueKey('shopping_units_field'),
                      controller: _unitsController,
                      decoration: const InputDecoration(
                        labelText: 'Unidades de compra',
                        helperText: 'Separadas por vírgula; a primeira é a de um item novo (até 20, de 1 a 8 letras).',
                        helperMaxLines: 3,
                      ),
                    ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          _error!,
                          key: const Key('house_labels_error'),
                          style: const TextStyle(color: AppColors.debtRed, fontSize: 12),
                        ),
                      ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => setState(() {
                            _cashController.text = settings.cashLabel ?? '';
                            _unitsController.text = settings.shoppingUnits.join(', ');
                            _error = null;
                            _expanded = false;
                          }),
                          child: const Text('Cancelar'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: _isSaving
                              ? null
                              : () async {
                                  final cash = _cashController.text.trim();
                                  final units = [
                                    for (final u in _unitsController.text.split(','))
                                      if (u.trim().isNotEmpty) u.trim(),
                                  ];
                                  if (cash.isNotEmpty && !HouseSettings.isValidCashLabel(cash)) {
                                    setState(() => _error = 'O nome do Caixa tem até 30 caracteres.');
                                    return;
                                  }
                                  if (!HouseSettings.areValidShoppingUnits(units)) {
                                    setState(() => _error =
                                        'Informe de 1 a 20 unidades diferentes, de 1 a 8 caracteres cada.');
                                    return;
                                  }
                                  final cashChanged = (cash.isEmpty ? null : cash) != settings.cashLabel;
                                  final unitsChanged = units.join('\u0000') != settings.shoppingUnits.join('\u0000');
                                  setState(() {
                                    _error = null;
                                    _isSaving = true;
                                  });
                                  final messenger = ScaffoldMessenger.of(context);
                                  final ok = (!cashChanged && !unitsChanged) ||
                                      await context.read<FinanceCubit>().updateHouseSettings(
                                            cashLabel: cashChanged && cash.isNotEmpty ? cash : null,
                                            clearCashLabel: cashChanged && cash.isEmpty,
                                            shoppingUnits: unitsChanged ? units : null,
                                          );
                                  if (mounted) {
                                    setState(() {
                                      _isSaving = false;
                                      _expanded = false;
                                    });
                                  }
                                  showSaveFeedback(messenger, ok: ok, success: 'Nomes e compras atualizados.');
                                },
                          style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                          child: const Text('Salvar'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// Bloco inline para exibir e alterar parâmetros do Fôlego e ciclo.
class _FolegoParamsBlock extends StatefulWidget {
  final FinanceState financeState;

  const _FolegoParamsBlock({required this.financeState});

  @override
  State<_FolegoParamsBlock> createState() => _FolegoParamsBlockState();
}

class _FolegoParamsBlockState extends State<_FolegoParamsBlock> {
  bool _expanded = false;
  late Map<String, TextEditingController> _fields;
  String? _error;
  bool _isSaving = false;

  static const _labels = {
    'warning': 'Atenção abaixo de (% dos aportes)',
    'commitment_warning': 'Barra em atenção acima de (%)',
    'commitment_danger': 'Barra crítica acima de (%)',
    'daily': 'Gasto diário confortável (R\$)',
    'horizon': 'Recorrentes à frente (1 a 6 meses)',
    'transition': 'Transição do ciclo (15 a 30 dias)',
  };

  @override
  void initState() {
    super.initState();
    _initFields();
  }

  void _initFields() {
    final saved = widget.financeState.houseSettings.folegoParams;
    _fields = {
      'warning': TextEditingController(text: '${saved.warningPercent}'),
      'commitment_warning': TextEditingController(text: '${saved.commitmentWarningPercent}'),
      'commitment_danger': TextEditingController(text: '${saved.commitmentDangerPercent}'),
      'daily': TextEditingController(text: '${saved.comfortableDailyCents ~/ 100}'),
      'horizon': TextEditingController(text: '${saved.recurringHorizonMonths}'),
      'transition': TextEditingController(text: '${saved.transitionMinDays}'),
    };
  }

  @override
  void didUpdateWidget(_FolegoParamsBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_expanded && oldWidget.financeState.houseSettings.folegoParams != widget.financeState.houseSettings.folegoParams) {
      final saved = widget.financeState.houseSettings.folegoParams;
      _fields['warning']?.text = '${saved.warningPercent}';
      _fields['commitment_warning']?.text = '${saved.commitmentWarningPercent}';
      _fields['commitment_danger']?.text = '${saved.commitmentDangerPercent}';
      _fields['daily']?.text = '${saved.comfortableDailyCents ~/ 100}';
      _fields['horizon']?.text = '${saved.recurringHorizonMonths}';
      _fields['transition']?.text = '${saved.transitionMinDays}';
    }
  }

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  bool _canEdit() =>
      widget.financeState.canDo(HousePermissionAction.editConfigurations, sl<AuthRepository>().currentUser?.id);

  @override
  Widget build(BuildContext context) {
    final params = widget.financeState.houseSettings.folegoParams;
    final isAdmin = _canEdit();

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: isAdmin ? () => setState(() => _expanded = !_expanded) : null,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Fôlego e Ciclo',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                    ),
                    if (isAdmin)
                      TextButton(
                        onPressed: () => setState(() => _expanded = !_expanded),
                        child: Text(_expanded ? 'Fechar' : 'Alterar'),
                      )
                    else
                      const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  const Expanded(child: Text('Fôlego em atenção abaixo de', style: TextStyle(fontSize: 14))),
                  Text('${params.warningPercent}% dos aportes', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  const Expanded(child: Text('Barra de comprometimento', style: TextStyle(fontSize: 14))),
                  Text('atenção acima de ${params.commitmentWarningPercent}%, crítica acima de ${params.commitmentDangerPercent}%', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  const Expanded(child: Text('Gasto diário confortável a partir de', style: TextStyle(fontSize: 14))),
                  Text(Money(params.comfortableDailyCents).format(), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  const Expanded(child: Text('Contas recorrentes geradas até', style: TextStyle(fontSize: 14))),
                  Text('${params.recurringHorizonMonths} meses à frente', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  const Expanded(child: Text('Ciclo de transição (troca do dia)', style: TextStyle(fontSize: 14))),
                  Text('mínimo de ${params.transitionMinDays} dias', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            if (!isAdmin)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Text('Só administradores mudam estes limites.', style: TextStyle(color: Colors.grey, fontSize: 13)),
              ),
            if (_expanded) ...[
              const Divider(height: 16),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final entry in _labels.entries)
                      TextField(
                        key: ValueKey('folego_param_${entry.key}'),
                        controller: _fields[entry.key],
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(labelText: entry.value),
                      ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          _error!,
                          key: const Key('folego_params_error'),
                          style: const TextStyle(color: AppColors.debtRed, fontSize: 12),
                        ),
                      ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => setState(() {
                            final saved = widget.financeState.houseSettings.folegoParams;
                            _fields['warning']?.text = '${saved.warningPercent}';
                            _fields['commitment_warning']?.text = '${saved.commitmentWarningPercent}';
                            _fields['commitment_danger']?.text = '${saved.commitmentDangerPercent}';
                            _fields['daily']?.text = '${saved.comfortableDailyCents ~/ 100}';
                            _fields['horizon']?.text = '${saved.recurringHorizonMonths}';
                            _fields['transition']?.text = '${saved.transitionMinDays}';
                            _error = null;
                            _expanded = false;
                          }),
                          child: const Text('Cancelar'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: _isSaving
                              ? null
                              : () async {
                                  int? read(String key) => int.tryParse(_fields[key]!.text.trim());
                                  final daily = read('daily');
                                  final next = FolegoParams(
                                    warningPercent: read('warning') ?? -1,
                                    commitmentWarningPercent: read('commitment_warning') ?? -1,
                                    commitmentDangerPercent: read('commitment_danger') ?? -1,
                                    comfortableDailyCents: daily == null ? -1 : daily * 100,
                                    recurringHorizonMonths: read('horizon') ?? -1,
                                    transitionMinDays: read('transition') ?? -1,
                                  );
                                  if (!next.isValid) {
                                    setState(() => _error =
                                        'Confira os valores: percentuais de 0 a 100 (atenção da barra abaixo da crítica), '
                                        'recorrentes de 1 a 6 meses e transição de 15 a 30 dias.');
                                    return;
                                  }
                                  setState(() {
                                    _error = null;
                                    _isSaving = true;
                                  });
                                  final messenger = ScaffoldMessenger.of(context);
                                  final ok = next == params ||
                                      await context.read<FinanceCubit>().updateHouseSettings(folegoParams: next);
                                  if (mounted) {
                                    setState(() {
                                      _isSaving = false;
                                      _expanded = false;
                                    });
                                  }
                                  showSaveFeedback(messenger, ok: ok, success: 'Parâmetros do Fôlego atualizados.');
                                },
                          style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                          child: const Text('Salvar'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// Bloco inline para exibir e alterar estágios de alerta de orçamento.
class _BudgetAlertBlock extends StatefulWidget {
  final FinanceState financeState;

  const _BudgetAlertBlock({required this.financeState});

  @override
  State<_BudgetAlertBlock> createState() => _BudgetAlertBlockState();
}

class _BudgetAlertBlockState extends State<_BudgetAlertBlock> {
  bool _expanded = false;
  late TextEditingController _controller;
  String? _error;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.financeState.houseSettings.budgetAlertStages.editText);
  }

  @override
  void didUpdateWidget(_BudgetAlertBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_expanded && oldWidget.financeState.houseSettings.budgetAlertStages != widget.financeState.houseSettings.budgetAlertStages) {
      _controller.text = widget.financeState.houseSettings.budgetAlertStages.editText;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool _canEdit() =>
      widget.financeState.canDo(HousePermissionAction.editConfigurations, sl<AuthRepository>().currentUser?.id);

  @override
  Widget build(BuildContext context) {
    final stages = widget.financeState.houseSettings.budgetAlertStages;
    final isAdmin = _canEdit();
    final custom = widget.financeState.categories.where((c) => c.budgetAlertStages != null).length;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: isAdmin ? () => setState(() => _expanded = !_expanded) : null,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Alertas de orçamento',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                    ),
                    if (isAdmin)
                      TextButton(
                        onPressed: () => setState(() => _expanded = !_expanded),
                        child: Text(_expanded ? 'Fechar' : 'Alterar'),
                      )
                    else
                      const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  const Expanded(child: Text('Avisar ao chegar em', style: TextStyle(fontSize: 14))),
                  Text('${stages.label} da média', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            if (custom > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Row(
                  children: [
                    const Expanded(child: Text('Categorias com estágios próprios', style: TextStyle(fontSize: 14))),
                    Text('$custom', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Text(
                isAdmin
                    ? 'Cada categoria pode ter os seus ao ser editada.'
                    : 'Só administradores mudam os estágios.',
                style: const TextStyle(color: Colors.grey, fontSize: 13),
              ),
            ),
            if (_expanded) ...[
              const Divider(height: 16),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      key: const ValueKey('budget_alert_stages'),
                      controller: _controller,
                      decoration: const InputDecoration(
                        labelText: 'Percentuais da média (ex.: 80, 100)',
                        helperText: 'Abaixo de 100 avisa ao chegar; de 100 em diante, ao passar.',
                        helperMaxLines: 2,
                      ),
                    ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          _error!,
                          key: const Key('budget_alert_error'),
                          style: const TextStyle(color: AppColors.debtRed, fontSize: 12),
                        ),
                      ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => setState(() {
                            _controller.text = stages.editText;
                            _error = null;
                            _expanded = false;
                          }),
                          child: const Text('Cancelar'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: _isSaving
                              ? null
                              : () async {
                                  final next = BudgetAlertStages.parse(_controller.text);
                                  if (next == null) {
                                    setState(() => _error =
                                        'Use de 1 a 4 percentuais crescentes, de 1 a 300 (ex.: 80, 100).');
                                    return;
                                  }
                                  setState(() {
                                    _error = null;
                                    _isSaving = true;
                                  });
                                  final messenger = ScaffoldMessenger.of(context);
                                  final ok = next == stages ||
                                      await context.read<FinanceCubit>().updateHouseSettings(budgetAlertStages: next);
                                  if (mounted) {
                                    setState(() {
                                      _isSaving = false;
                                      _expanded = false;
                                    });
                                  }
                                  showSaveFeedback(messenger, ok: ok, success: 'Alertas de orçamento atualizados.');
                                },
                          style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                          child: const Text('Salvar'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// Bloco inline para exibir e alterar padrões do fechamento.
class _ClosingDefaultsBlock extends StatefulWidget {
  final FinanceState financeState;

  const _ClosingDefaultsBlock({required this.financeState});

  @override
  State<_ClosingDefaultsBlock> createState() => _ClosingDefaultsBlockState();
}

class _ClosingDefaultsBlockState extends State<_ClosingDefaultsBlock> {
  bool _expanded = false;
  late SurplusAction _surplusAction;
  String? _surplusVaultId;
  late DeficitSplit _deficitSplit;
  String? _deficitVaultId;
  late ShortfallAction _shortfallAction;
  bool _isSaving = false;

  static String _surplusActionLabel(SurplusAction action) => switch (action) {
        SurplusAction.toVault => 'Guardar em uma caixinha',
        SurplusAction.rollover => 'Deixar no Caixa',
        SurplusAction.refund => 'Devolver aos moradores',
      };

  static String _deficitSplitLabel(DeficitSplit split) => switch (split) {
        DeficitSplit.proportional => 'Proporcional ao aporte',
        DeficitSplit.equal => 'Partes iguais',
      };

  static String _shortfallActionLabel(ShortfallAction action) => switch (action) {
        ShortfallAction.createP2PLoan => 'Vira empréstimo',
        ShortfallAction.deductFromVault => 'Cobrir com caixinha',
        ShortfallAction.rolloverPending => 'Fica para o próximo ciclo',
        ShortfallAction.forgiveRemainder => 'Perdoar a diferença',
      };

  @override
  void initState() {
    super.initState();
    _initValues();
  }

  void _initValues() {
    final saved = widget.financeState.houseSettings.closingDefaults;
    final vaults = widget.financeState.savingsVaults;
    _surplusAction = saved.surplusAction ?? SurplusAction.toVault;
    _surplusVaultId = saved.surplusVaultIn(vaults);
    _deficitSplit = saved.deficitSplit ?? DeficitSplit.proportional;
    _deficitVaultId = saved.deficitVaultIn(vaults);
    _shortfallAction = saved.shortfallAction ?? ShortfallAction.createP2PLoan;
  }

  @override
  void didUpdateWidget(_ClosingDefaultsBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_expanded && oldWidget.financeState.houseSettings.closingDefaults != widget.financeState.houseSettings.closingDefaults) {
      _initValues();
    }
  }

  bool _canEdit() =>
      widget.financeState.canDo(HousePermissionAction.editConfigurations, sl<AuthRepository>().currentUser?.id);

  @override
  Widget build(BuildContext context) {
    final defaults = widget.financeState.houseSettings.closingDefaults;
    final vaults = widget.financeState.savingsVaults;
    final isAdmin = _canEdit();
    String? vaultName(String? id) => vaults.where((v) => v.id == id).firstOrNull?.name;
    final surplusAction = defaults.surplusAction ?? SurplusAction.toVault;
    final surplusVault = vaultName(defaults.surplusVaultId);

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: isAdmin ? () => setState(() => _expanded = !_expanded) : null,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Padrões do fechamento',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                    ),
                    if (isAdmin)
                      TextButton(
                        onPressed: () => setState(() => _expanded = !_expanded),
                        child: Text(_expanded ? 'Fechar' : 'Alterar'),
                      )
                    else
                      const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  const Expanded(child: Text('Destino da sobra', style: TextStyle(fontSize: 14))),
                  Text(
                    surplusAction == SurplusAction.toVault && surplusVault != null
                        ? 'Caixinha $surplusVault'
                        : _surplusActionLabel(surplusAction),
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Gastos acima do balde', style: TextStyle(fontSize: 14)),
                        if (vaultName(defaults.deficitVaultId) != null)
                          Text(
                            'Antes, usa a caixinha ${vaultName(defaults.deficitVaultId)}',
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                      ],
                    ),
                  ),
                  Text(_deficitSplitLabel(defaults.deficitSplit ?? DeficitSplit.proportional), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  const Expanded(child: Text('Quem pagou menos', style: TextStyle(fontSize: 14))),
                  Text(_shortfallActionLabel(defaults.shortfallAction ?? ShortfallAction.createP2PLoan), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            if (!isAdmin)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Text('O fechamento abre com estas escolhas. Só administradores mudam os padrões.', style: TextStyle(color: Colors.grey, fontSize: 13)),
              ),
            if (_expanded) ...[
              const Divider(height: 16),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'O fechamento já abre com estas escolhas. Quem fecha ainda pode mudar cada uma naquele ciclo.',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                    const Padding(
                      padding: EdgeInsets.only(top: 12, bottom: 4),
                      child: Text('Destino da sobra', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    Wrap(
                      spacing: 6,
                      children: [
                        for (final action in SurplusAction.values)
                          ChoiceChip(
                            label: Text(_surplusActionLabel(action)),
                            selected: _surplusAction == action,
                            onSelected: (_) => setState(() => _surplusAction = action),
                          ),
                      ],
                    ),
                    if (_surplusAction == SurplusAction.toVault && vaults.isNotEmpty)
                      DropdownButton<String?>(
                        key: const ValueKey('closing_surplus_vault'),
                        value: _surplusVaultId,
                        isExpanded: true,
                        style: Theme.of(context).textTheme.bodyMedium,
                        onChanged: (v) => setState(() => _surplusVaultId = v),
                        items: [
                          const DropdownMenuItem(value: null, child: Text('A primeira caixinha da lista')),
                          for (final vault in vaults)
                            DropdownMenuItem(value: vault.id, child: Text(vault.name, overflow: TextOverflow.ellipsis)),
                        ],
                      ),
                    const Padding(
                      padding: EdgeInsets.only(top: 12, bottom: 4),
                      child: Text('Gastos acima do balde', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    Wrap(
                      spacing: 6,
                      children: [
                        for (final split in DeficitSplit.values)
                          ChoiceChip(
                            label: Text(_deficitSplitLabel(split)),
                            selected: _deficitSplit == split,
                            onSelected: (_) => setState(() => _deficitSplit = split),
                          ),
                      ],
                    ),
                    if (vaults.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text('Caixinha que cobre o excedente antes do rateio:', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                      DropdownButton<String?>(
                        key: const ValueKey('closing_deficit_vault'),
                        value: _deficitVaultId,
                        isExpanded: true,
                        style: Theme.of(context).textTheme.bodyMedium,
                        onChanged: (v) => setState(() => _deficitVaultId = v),
                        items: [
                          const DropdownMenuItem(value: null, child: Text('Não usar caixinha')),
                          for (final vault in vaults)
                            DropdownMenuItem(value: vault.id, child: Text(vault.name, overflow: TextOverflow.ellipsis)),
                        ],
                      ),
                    ],
                    const Padding(
                      padding: EdgeInsets.only(top: 12, bottom: 4),
                      child: Text('Quem pagou menos no Super Pix', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    Wrap(
                      spacing: 6,
                      children: [
                        for (final action in ShortfallAction.values)
                          ChoiceChip(
                            label: Text(_shortfallActionLabel(action)),
                            selected: _shortfallAction == action,
                            onSelected: (_) => setState(() => _shortfallAction = action),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => setState(() {
                            _initValues();
                            _expanded = false;
                          }),
                          child: const Text('Cancelar'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: _isSaving
                              ? null
                              : () async {
                                  setState(() => _isSaving = true);
                                  final messenger = ScaffoldMessenger.of(context);
                                  final saved = widget.financeState.houseSettings.closingDefaults;
                                  final surplusBefore = saved.surplusAction ?? SurplusAction.toVault;
                                  final splitBefore = saved.deficitSplit ?? DeficitSplit.proportional;
                                  final shortfallBefore = saved.shortfallAction ?? ShortfallAction.createP2PLoan;
                                  final next = ClosingDefaults(
                                    surplusAction: _surplusAction != surplusBefore ? _surplusAction : saved.surplusAction,
                                    surplusVaultId: _surplusAction == SurplusAction.toVault ? _surplusVaultId : null,
                                    deficitSplit: _deficitSplit != splitBefore ? _deficitSplit : saved.deficitSplit,
                                    deficitVaultId: _deficitVaultId,
                                    shortfallAction: _shortfallAction != shortfallBefore ? _shortfallAction : saved.shortfallAction,
                                  );
                                  final ok = next == saved ||
                                      await context.read<FinanceCubit>().updateHouseSettings(closingDefaults: next);
                                  if (mounted) {
                                    setState(() {
                                      _isSaving = false;
                                      _expanded = false;
                                    });
                                  }
                                  showSaveFeedback(messenger, ok: ok, success: 'Padrões do fechamento atualizados.');
                                },
                          style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                          child: const Text('Salvar'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// Bloco inline para exibir e alterar saldo inicial da casa.
class _InitialBalanceBlock extends StatefulWidget {
  final FinanceState financeState;

  const _InitialBalanceBlock({required this.financeState});

  @override
  State<_InitialBalanceBlock> createState() => _InitialBalanceBlockState();
}

class _InitialBalanceBlockState extends State<_InitialBalanceBlock> {
  bool _expanded = false;
  late Money _reserve;
  late Money _cash;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.financeState.initialBalance;
    _reserve = initial.reserve;
    _cash = initial.cash;
  }

  @override
  void didUpdateWidget(_InitialBalanceBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_expanded && oldWidget.financeState.initialBalance != widget.financeState.initialBalance) {
      final initial = widget.financeState.initialBalance;
      _reserve = initial.reserve;
      _cash = initial.cash;
    }
  }

  bool _canEdit() =>
      widget.financeState.canDo(HousePermissionAction.initialBalance, sl<AuthRepository>().currentUser?.id);

  static String _twoDigits(int n) => n.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final initial = widget.financeState.initialBalance;
    final isAdmin = _canEdit();
    final cashStart = initial.cashCycleStart;
    final actionLabel = isAdmin ? (initial.isEmpty ? 'Informar' : 'Alterar') : null;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: isAdmin ? () => setState(() => _expanded = !_expanded) : null,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Saldo inicial da casa',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                    ),
                    if (actionLabel != null)
                      TextButton(
                        onPressed: () => setState(() => _expanded = !_expanded),
                        child: Text(_expanded ? 'Fechar' : actionLabel),
                      )
                    else
                      const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            const SizedBox(height: 8),
            if (initial.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Text(
                  isAdmin
                      ? 'A casa começou do zero. Se já havia dinheiro guardado ou na conta da casa, informe aqui.'
                      : 'A casa começou do zero. Só administradores informam o saldo inicial.',
                  style: const TextStyle(color: Colors.grey, fontSize: 13),
                ),
              )
            else ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Row(
                  children: [
                    const Expanded(child: Text('Reserva guardada', style: TextStyle(fontSize: 14))),
                    Text(initial.reserve.format(), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Saldo na conta da casa', style: TextStyle(fontSize: 14)),
                          if (cashStart != null)
                            Text(
                              'Sobra do ciclo que começou em ${_twoDigits(cashStart.day)}/${_twoDigits(cashStart.month)}',
                              style: const TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                        ],
                      ),
                    ),
                    Text(initial.cash.format(), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
            if (_expanded) ...[
              const Divider(height: 16),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'O dinheiro que a casa já tinha quando começou a usar o app. Pode deixar em branco o que não houver.',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 16),
                    MoneyTextFormField(
                      key: const ValueKey('initial_reserve_field'),
                      initialValue: _reserve,
                      labelText: 'Reserva guardada',
                      helperText: 'Entra na Reserva da Casa. Não mexe no Caixa do ciclo.',
                      prefixIcon: const Icon(Icons.savings_outlined),
                      onChanged: (m) => _reserve = m,
                    ),
                    const SizedBox(height: 12),
                    MoneyTextFormField(
                      key: const ValueKey('initial_cash_field'),
                      initialValue: _cash,
                      labelText: 'Saldo na conta da casa',
                      helperText: 'Vale como a sobra do primeiro ciclo e segue a regra da sobra.',
                      prefixIcon: const Icon(Icons.account_balance_wallet_outlined),
                      onChanged: (m) => _cash = m,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => setState(() {
                            _reserve = initial.reserve;
                            _cash = initial.cash;
                            _expanded = false;
                          }),
                          child: const Text('Cancelar'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: _isSaving
                              ? null
                              : () async {
                                  setState(() => _isSaving = true);
                                  final messenger = ScaffoldMessenger.of(context);
                                  final error = await context.read<FinanceCubit>().setHouseInitialBalance(
                                        reserve: _reserve,
                                        cash: _cash,
                                      );
                                  if (mounted) {
                                    setState(() {
                                      _isSaving = false;
                                      _expanded = false;
                                    });
                                  }
                                  showSaveFeedback(
                                    messenger,
                                    ok: error == null,
                                    success: 'Saldo inicial atualizado.',
                                    failure: error,
                                  );
                                },
                          style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                          child: const Text('Salvar'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// Bloco inline para exibir e alterar planejamento e fechamento.
class _PlanningSettingsBlock extends StatefulWidget {
  final FinanceState financeState;

  const _PlanningSettingsBlock({required this.financeState});

  @override
  State<_PlanningSettingsBlock> createState() => _PlanningSettingsBlockState();
}

class _PlanningSettingsBlockState extends State<_PlanningSettingsBlock> {
  bool _expanded = false;
  OpeningBalanceRule? _rolledRule;
  OpeningBalanceRule? _loansRule;
  late OpeningBalanceRule _vaultDefault;
  late Map<String, OpeningBalanceRule> _vaultOverrides;
  OpeningBalanceRule? _thirdPartyRule;
  late int _historyCycles;
  late int _adjustPercent;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _initValues();
  }

  void _initValues() {
    final settings = widget.financeState.houseSettings;
    final savedRules = settings.inflowRules;
    _rolledRule = savedRules.rolledSurplusRule(settings.openingBalanceRule);
    _loansRule = savedRules.houseLoansRepaidRule(settings.openingBalanceRule);
    _vaultDefault = savedRules.vaultWithdrawals ?? OpeningBalanceRule.keep;
    _vaultOverrides = Map<String, OpeningBalanceRule>.of(savedRules.vaultOverrides);
    _thirdPartyRule = savedRules.thirdParty;
    _historyCycles = settings.historyCycles;
    _adjustPercent = settings.adjustPercent;
  }

  @override
  void didUpdateWidget(_PlanningSettingsBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_expanded && oldWidget.financeState.houseSettings != widget.financeState.houseSettings) {
      _initValues();
    }
  }

  bool _canEdit() =>
      widget.financeState.canDo(HousePermissionAction.editConfigurations, sl<AuthRepository>().currentUser?.id);

  @override
  Widget build(BuildContext context) {
    final settings = widget.financeState.houseSettings;
    final inflowRules = settings.inflowRules;
    final vaultOverridesCount = inflowRules.vaultOverrides.keys
        .where((id) => widget.financeState.savingsVaults.any((v) => v.id == id))
        .length;
    final currentVaultDefault = inflowRules.vaultWithdrawals ?? OpeningBalanceRule.keep;
    final isAdmin = _canEdit();
    final usesFixed = widget.financeState.members.any((m) => (m.defaultFixedAmountCents ?? 0) > 0);
    final vaults = widget.financeState.savingsVaults;

    final options = [
      OpeningBalanceRule.reduceQuotas,
      if (usesFixed) OpeningBalanceRule.coverExcess,
      OpeningBalanceRule.keep,
    ];

    Widget ruleChoice(
      OpeningBalanceRule? selected,
      ValueChanged<OpeningBalanceRule> onSelected, {
      String? defaultHint,
    }) =>
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 6,
              children: [
                for (final option in options)
                  ChoiceChip(
                    label: Text(option.label),
                    selected: selected == option,
                    onSelected: isAdmin ? (_) => setState(() => onSelected(option)) : null,
                  ),
              ],
            ),
            if (selected != null && options.contains(selected))
              Text(selected.description, style: TextStyle(fontSize: 12, color: Colors.grey.shade600))
            else if (defaultHint != null)
              Text(defaultHint, style: const TextStyle(fontSize: 12, color: Colors.teal)),
          ],
        );

    final defaultHint = usesFixed
        ? 'Hoje (padrão): cobre só o que passar do valor fixo.'
        : 'Hoje (padrão): o planejador abate, mas o fechamento cobra a parte inteira e deixa o dinheiro no Caixa.';
    const vaultWarning = Text(
      'A caixinha diminui e ninguém repõe o que saiu dela.',
      style: TextStyle(fontSize: 12, color: AppColors.accent),
    );
    bool lowersVault(OpeningBalanceRule? r) =>
        r == OpeningBalanceRule.reduceQuotas || r == OpeningBalanceRule.coverExcess;
    Widget kindTitle(String text) => Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 4),
          child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
        );

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Planejamento e Fechamento',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                    ),
                    TextButton(
                      onPressed: () => setState(() => _expanded = !_expanded),
                      child: Text(_expanded ? 'Fechar' : 'Alterar'),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  const Expanded(child: Text('Sobra do ciclo anterior', style: TextStyle(fontSize: 14))),
                  Text(inflowRules.rolledSurplusRule(settings.openingBalanceRule)?.label ?? 'Padrão', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  const Expanded(child: Text('Empréstimo do Caixa pago de volta', style: TextStyle(fontSize: 14))),
                  Text(inflowRules.houseLoansRepaidRule(settings.openingBalanceRule)?.label ?? 'Padrão', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  const Expanded(child: Text('Resgate de caixinha', style: TextStyle(fontSize: 14))),
                  Text(
                    vaultOverridesCount == 0
                        ? currentVaultDefault.label
                        : '${currentVaultDefault.label} (+$vaultOverridesCount com regra própria)',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  const Expanded(child: Text('Entrada de fora', style: TextStyle(fontSize: 14))),
                  Text(inflowRules.thirdParty?.label ?? 'Igual à sobra', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  const Expanded(child: Text('Média dos gastos variáveis', style: TextStyle(fontSize: 14))),
                  Text(settings.historyCycles == 1 ? 'Último ciclo' : 'Últimos ${settings.historyCycles} ciclos', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  const Expanded(child: Text('Modos Econômico e Com folga', style: TextStyle(fontSize: 14))),
                  Text('${settings.adjustPercent}%', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            if (_expanded) ...[
              const Divider(height: 16),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Dinheiro que já está no Caixa', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(
                      'O que o ciclo faz com o saldo da conta antes de cobrar as quotas dos moradores.',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 8),
                    kindTitle('Sobra do ciclo anterior'),
                    ruleChoice(_rolledRule, (r) => _rolledRule = r, defaultHint: defaultHint),
                    kindTitle('Empréstimo do Caixa pago de volta'),
                    ruleChoice(_loansRule, (r) => _loansRule = r, defaultHint: defaultHint),
                    const Divider(height: 24),
                    const Text('Resgate de caixinha no ciclo', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(
                      'Regra geral para quando a casa resgatar dinheiro guardado.',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 8),
                    ruleChoice(_vaultDefault, (r) => _vaultDefault = r),
                    if (lowersVault(_vaultDefault)) vaultWarning,
                    for (final vault in vaults) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              vault.name,
                              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          DropdownButton<OpeningBalanceRule?>(
                            value: _vaultOverrides[vault.id],
                            isDense: true,
                            onChanged: isAdmin
                                ? (r) => setState(() {
                                      if (r == null) {
                                        _vaultOverrides.remove(vault.id);
                                      } else {
                                        _vaultOverrides[vault.id] = r;
                                      }
                                    })
                                : null,
                            items: [
                              const DropdownMenuItem(value: null, child: Text('Igual ao padrão')),
                              for (final option in options)
                                DropdownMenuItem(value: option, child: Text(option.label)),
                            ],
                          ),
                        ],
                      ),
                      if (lowersVault(_vaultOverrides[vault.id]) && !lowersVault(_vaultDefault)) vaultWarning,
                    ],
                    kindTitle('Entrada de fora'),
                    ruleChoice(_thirdPartyRule ?? _rolledRule, (r) => _thirdPartyRule = r),
                    if (_thirdPartyRule == null)
                      const Text(
                        'Sem escolha própria: segue a regra da sobra do ciclo anterior.',
                        style: TextStyle(fontSize: 12, color: Colors.teal),
                      ),
                    const Divider(height: 24),
                    const Text('Média dos gastos variáveis', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(
                      'Quantos ciclos anteriores entram na média de Mercado, Luz e outras categorias variáveis. Os alertas de categoria usam a mesma média.',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      children: [
                        for (final n in HouseSettings.historyCyclesOptions)
                          ChoiceChip(
                            label: Text(n == 1 ? 'Último ciclo' : '$n ciclos'),
                            selected: _historyCycles == n,
                            onSelected: (_) => setState(() => _historyCycles = n),
                          ),
                      ],
                    ),
                    const Divider(height: 24),
                    const Text('Modos Econômico e Com folga', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(
                      'Quanto o planejador tira ou soma da média das categorias variáveis.',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      children: [
                        for (final p in HouseSettings.adjustPercentOptions)
                          ChoiceChip(
                            label: Text('$p%'),
                            selected: _adjustPercent == p,
                            onSelected: (_) => setState(() => _adjustPercent = p),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => setState(() {
                            _initValues();
                            _expanded = false;
                          }),
                          child: const Text('Cancelar'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: _isSaving
                              ? null
                              : () async {
                                  setState(() => _isSaving = true);
                                  final messenger = ScaffoldMessenger.of(context);
                                  final savedRules = settings.inflowRules;
                                  final rolledBefore = savedRules.rolledSurplusRule(settings.openingBalanceRule);
                                  final loansBefore = savedRules.houseLoansRepaidRule(settings.openingBalanceRule);
                                  final rules = OpeningInflowRules(
                                    rolledSurplus: _rolledRule != rolledBefore ? _rolledRule : savedRules.rolledSurplus,
                                    houseLoansRepaid: _loansRule != loansBefore ? _loansRule : savedRules.houseLoansRepaid,
                                    vaultWithdrawals: _vaultDefault != (savedRules.vaultWithdrawals ?? OpeningBalanceRule.keep)
                                        ? _vaultDefault
                                        : savedRules.vaultWithdrawals,
                                    vaultOverrides: _vaultOverrides,
                                    thirdParty: _thirdPartyRule,
                                  );
                                  final ok = await context.read<FinanceCubit>().updateHouseSettings(
                                        inflowRules: isAdmin && rules != savedRules ? rules : null,
                                        historyCycles: _historyCycles != settings.historyCycles ? _historyCycles : null,
                                        adjustPercent: _adjustPercent != settings.adjustPercent ? _adjustPercent : null,
                                      );
                                  if (mounted) {
                                    setState(() {
                                      _isSaving = false;
                                      _expanded = false;
                                    });
                                  }
                                  showSaveFeedback(messenger, ok: ok, success: 'Regras de planejamento atualizadas.');
                                },
                          style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                          child: const Text('Salvar'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// Bloco inline para exibir e alterar parâmetros de importação de extrato.
class _ImportParamsBlock extends StatefulWidget {
  final FinanceState financeState;

  const _ImportParamsBlock({required this.financeState});

  @override
  State<_ImportParamsBlock> createState() => _ImportParamsBlockState();
}

class _ImportParamsBlockState extends State<_ImportParamsBlock> {
  bool _expanded = false;
  late Map<String, TextEditingController> _fields;
  String? _categoryId;
  String? _sourceId;
  late ImportSplitMode _splitMode;
  String? _error;
  bool _isSaving = false;

  static const _labels = {
    'date': 'Dias de diferença aceitos (0 a 10)',
    'other': 'Dias em outra forma de pagamento (até o anterior)',
    'differs': 'Dias com valor diferente (até o primeiro)',
    'drift': 'Valor diferente aceito (% de 0 a 100)',
    'similarity': 'Nome parecido com valor diferente (% de 0 a 100)',
    'invoice': 'Pagamento de fatura até (1 a 120 dias do vencimento)',
  };

  @override
  void initState() {
    super.initState();
    _initFields();
  }

  void _initFields() {
    final saved = widget.financeState.houseSettings.importMatching;
    final savedDefaults = widget.financeState.houseSettings.importDefaults;
    final categories = widget.financeState.categories;
    final sources = widget.financeState.paymentMethods
        .where((p) => p.type == PaymentMethodType.card || p.type == PaymentMethodType.account)
        .toList();

    _fields = {
      'date': TextEditingController(text: '${saved.dateWindowDays}'),
      'other': TextEditingController(text: '${saved.otherMethodWindowDays}'),
      'differs': TextEditingController(text: '${saved.amountDiffersDays}'),
      'drift': TextEditingController(text: '${saved.amountDriftPercent}'),
      'similarity': TextEditingController(text: '${saved.minSimilarityPercent}'),
      'invoice': TextEditingController(text: '${saved.invoiceWindowDays}'),
    };
    _categoryId = categories.any((c) => c.id == savedDefaults.categoryId) ? savedDefaults.categoryId : null;
    _sourceId = sources.any((p) => p.id == savedDefaults.paymentMethodId) ? savedDefaults.paymentMethodId : null;
    _splitMode = savedDefaults.splitMode;
  }

  @override
  void didUpdateWidget(_ImportParamsBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_expanded &&
        (oldWidget.financeState.houseSettings.importMatching != widget.financeState.houseSettings.importMatching ||
            oldWidget.financeState.houseSettings.importDefaults != widget.financeState.houseSettings.importDefaults)) {
      final saved = widget.financeState.houseSettings.importMatching;
      _fields['date']?.text = '${saved.dateWindowDays}';
      _fields['other']?.text = '${saved.otherMethodWindowDays}';
      _fields['differs']?.text = '${saved.amountDiffersDays}';
      _fields['drift']?.text = '${saved.amountDriftPercent}';
      _fields['similarity']?.text = '${saved.minSimilarityPercent}';
      _fields['invoice']?.text = '${saved.invoiceWindowDays}';
      final savedDefaults = widget.financeState.houseSettings.importDefaults;
      _categoryId = widget.financeState.categories.any((c) => c.id == savedDefaults.categoryId) ? savedDefaults.categoryId : null;
      _sourceId = widget.financeState.paymentMethods.any((p) => p.id == savedDefaults.paymentMethodId) ? savedDefaults.paymentMethodId : null;
      _splitMode = savedDefaults.splitMode;
    }
  }

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  bool _canEdit() =>
      widget.financeState.canDo(HousePermissionAction.editConfigurations, sl<AuthRepository>().currentUser?.id);

  @override
  Widget build(BuildContext context) {
    final settings = widget.financeState.houseSettings;
    final matching = settings.importMatching;
    final defaults = settings.importDefaults;
    final isAdmin = _canEdit();
    final category = widget.financeState.categories.where((c) => c.id == defaults.categoryId).firstOrNull;
    final source = widget.financeState.paymentMethods.where((p) => p.id == defaults.paymentMethodId).firstOrNull;
    final categories = widget.financeState.categories;
    final sources = widget.financeState.paymentMethods
        .where((p) => p.type == PaymentMethodType.card || p.type == PaymentMethodType.account)
        .toList();

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: isAdmin ? () => setState(() => _expanded = !_expanded) : null,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Importação de extrato',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                    ),
                    if (isAdmin)
                      TextButton(
                        onPressed: () => setState(() => _expanded = !_expanded),
                        child: Text(_expanded ? 'Fechar' : 'Alterar'),
                      )
                    else
                      const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  const Expanded(child: Text('Mesma compra se a data difere até', style: TextStyle(fontSize: 14))),
                  Text('${matching.dateWindowDays} dias (${matching.otherMethodWindowDays} em outra forma de pagamento)', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  const Expanded(child: Text('Valor diferente (gorjeta, taxa)', style: TextStyle(fontSize: 14))),
                  Text('até ${matching.amountDriftPercent}% em ${matching.amountDiffersDays} dia(s), nome ${matching.minSimilarityPercent}% parecido', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  const Expanded(child: Text('Pagamento de fatura no extrato', style: TextStyle(fontSize: 14))),
                  Text('até ${matching.invoiceWindowDays} dias do vencimento', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  const Expanded(child: Text('Categoria das linhas novas', style: TextStyle(fontSize: 14))),
                  Text(category?.name ?? 'A primeira da casa', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  const Expanded(child: Text('Divisão das linhas novas', style: TextStyle(fontSize: 14))),
                  Text(defaults.splitMode.label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  const Expanded(child: Text('Abre a importação em', style: TextStyle(fontSize: 14))),
                  Text(source?.name ?? 'Sem preferência', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            if (!isAdmin)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Text('Só administradores mudam estes padrões.', style: TextStyle(color: Colors.grey, fontSize: 13)),
              ),
            if (_expanded) ...[
              const Divider(height: 16),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final entry in _labels.entries)
                      TextField(
                        key: ValueKey('import_matching_${entry.key}'),
                        controller: _fields[entry.key],
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(labelText: entry.value),
                      ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String?>(
                      key: const ValueKey('import_default_category'),
                      initialValue: _categoryId,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Categoria das linhas novas'),
                      items: [
                        const DropdownMenuItem<String?>(value: null, child: Text('A primeira da casa')),
                        for (final c in categories) DropdownMenuItem<String?>(value: c.id, child: Text(c.name)),
                      ],
                      onChanged: (value) => setState(() => _categoryId = value),
                    ),
                    DropdownButtonFormField<ImportSplitMode>(
                      key: const ValueKey('import_default_split'),
                      initialValue: _splitMode,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Divisão das linhas novas'),
                      items: [
                        for (final mode in ImportSplitMode.values)
                          DropdownMenuItem(value: mode, child: Text(mode.label)),
                      ],
                      onChanged: (value) => setState(() => _splitMode = value ?? _splitMode),
                    ),
                    DropdownButtonFormField<String?>(
                      key: const ValueKey('import_default_source'),
                      initialValue: _sourceId,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Abrir a importação em'),
                      items: [
                        const DropdownMenuItem<String?>(value: null, child: Text('Sem preferência')),
                        for (final p in sources) DropdownMenuItem<String?>(value: p.id, child: Text(p.name)),
                      ],
                      onChanged: (value) => setState(() => _sourceId = value),
                    ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          _error!,
                          key: const Key('import_params_error'),
                          style: const TextStyle(color: AppColors.debtRed, fontSize: 12),
                        ),
                      ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => setState(() {
                            _initFields();
                            _error = null;
                            _expanded = false;
                          }),
                          child: const Text('Cancelar'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: _isSaving
                              ? null
                              : () async {
                                  int read(String key) => int.tryParse(_fields[key]!.text.trim()) ?? -1;
                                  final next = ImportMatching(
                                    dateWindowDays: read('date'),
                                    otherMethodWindowDays: read('other'),
                                    amountDiffersDays: read('differs'),
                                    amountDriftPercent: read('drift'),
                                    minSimilarityPercent: read('similarity'),
                                    invoiceWindowDays: read('invoice'),
                                  );
                                  if (!next.isValid) {
                                    setState(() => _error =
                                        'Confira os valores: dias de 0 a 10 (os de outra forma de pagamento e de valor '
                                        'diferente não passam dos dias aceitos), percentuais de 0 a 100 e fatura de 1 a 120 dias.');
                                    return;
                                  }
                                  final nextDefaults = ImportDefaults(
                                    categoryId: _categoryId,
                                    splitMode: _splitMode,
                                    paymentMethodId: _sourceId,
                                  );
                                  setState(() {
                                    _error = null;
                                    _isSaving = true;
                                  });
                                  final messenger = ScaffoldMessenger.of(context);
                                  final saved = widget.financeState.houseSettings.importMatching;
                                  final savedDefaults = widget.financeState.houseSettings.importDefaults;
                                  final ok = (next == saved && nextDefaults == savedDefaults) ||
                                      await context.read<FinanceCubit>().updateHouseSettings(
                                            importMatching: next == saved ? null : next,
                                            importDefaults: nextDefaults == savedDefaults ? null : nextDefaults,
                                          );
                                  if (mounted) {
                                    setState(() {
                                      _isSaving = false;
                                      _expanded = false;
                                    });
                                  }
                                  showSaveFeedback(messenger, ok: ok, success: 'Padrões de importação atualizados.');
                                },
                          style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                          child: const Text('Salvar'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// Tile inline expansível para editar categoria e divisão de uma lista de compras.
class _ShoppingListDefaultsTile extends StatefulWidget {
  final ShoppingList list;
  final FinanceState financeState;
  final ShoppingCubit cubit;

  const _ShoppingListDefaultsTile({
    super.key,
    required this.list,
    required this.financeState,
    required this.cubit,
  });

  @override
  State<_ShoppingListDefaultsTile> createState() => _ShoppingListDefaultsTileState();
}

class _ShoppingListDefaultsTileState extends State<_ShoppingListDefaultsTile> {
  bool _expanded = false;
  String? _categoryId;
  late ImportSplitMode _splitMode;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _initValues();
  }

  void _initValues() {
    final categories = widget.financeState.categories;
    _categoryId = categories.any((c) => c.id == widget.list.defaultCategoryId) ? widget.list.defaultCategoryId : null;
    _splitMode = widget.list.defaultSplitMode;
  }

  @override
  void didUpdateWidget(_ShoppingListDefaultsTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_expanded && (oldWidget.list != widget.list || oldWidget.financeState != widget.financeState)) {
      _initValues();
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = widget.financeState.categories;
    final catName = categories.where((c) => c.id == widget.list.defaultCategoryId).firstOrNull?.name ?? 'Categoria de mercado';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.list.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                      Text(widget.list.defaultSplitMode.label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ),
                Text(catName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                const SizedBox(width: 8),
                Icon(_expanded ? Icons.expand_less : Icons.expand_more, size: 20, color: Colors.grey),
              ],
            ),
          ),
        ),
        if (_expanded) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<String?>(
                  key: const ValueKey('list_default_category'),
                  initialValue: _categoryId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Categoria da compra'),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('Categoria de mercado')),
                    for (final c in categories) DropdownMenuItem<String?>(value: c.id, child: Text(c.name)),
                  ],
                  onChanged: (value) => setState(() => _categoryId = value),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<ImportSplitMode>(
                  key: const ValueKey('list_default_split'),
                  initialValue: _splitMode,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Divisão da compra'),
                  items: [
                    for (final mode in ImportSplitMode.values)
                      DropdownMenuItem(value: mode, child: Text(mode.label)),
                  ],
                  onChanged: (value) => setState(() => _splitMode = value ?? _splitMode),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => setState(() {
                        _initValues();
                        _expanded = false;
                      }),
                      child: const Text('Cancelar'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _isSaving
                          ? null
                          : () async {
                              setState(() => _isSaving = true);
                              final messenger = ScaffoldMessenger.of(context);
                              final ok = await widget.cubit.updateListDefaults(
                                widget.list,
                                categoryId: _categoryId,
                                splitMode: _splitMode,
                              );
                              if (mounted) {
                                setState(() {
                                  _isSaving = false;
                                  _expanded = false;
                                });
                              }
                              showSaveFeedback(messenger, ok: ok, success: 'Padrões da lista atualizados.');
                            },
                      style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                      child: const Text('Salvar'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
