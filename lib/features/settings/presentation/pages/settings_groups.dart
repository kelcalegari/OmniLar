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
  );

  const _SettingsGroup(this.title, this.description, this.icon, this.color);

  final String title;
  final String description;
  final IconData icon;
  final Color color;
}

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
    final hasPix = house?.pixKey != null && house!.pixKey!.isNotEmpty;

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
      _panel(
        context,
        title: 'Ciclo Financeiro',
        actionLabel: 'Alterar',
        onAction: () => _showCycleDayDialog(context, cycleDay),
        children: [
          _line(title: 'Começa todo dia', value: '$cycleDay'),
          _line(title: 'Ciclo em andamento', value: financeState.currentCycle.label),
        ],
      ),
      _panel(
        context,
        title: 'Chave Pix da Casa',
        actionLabel: hasPix ? 'Alterar' : 'Cadastrar',
        onAction: () => _showHousePixKeyModal(context, house),
        children: [
          if (hasPix) ...[
            _line(title: 'Chave', value: house.pixKey!),
            _line(title: 'Titular', value: house.pixKeyHolderName ?? 'Caixa da Casa'),
          ] else
            _emptyLine('Nenhuma chave cadastrada. É ela que recebe os aportes do Caixa da Casa.'),
        ],
      ),
    ];
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
      for (final c in categories) '${c.id}:${c.name}:${c.ownerMemberId}',
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
        owner != null ? 'Responsável: 100% ${owner.name}' : 'Divisão padrão da casa',
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
        return 'Fecha dia ${pm.closingDay} • Vence dia ${pm.dueDay}';
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
        children: const [PushSettingsBlock()],
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
                    'Privacidade LGPD: seus dados bancários, CPF e números de cartão são mascarados no dispositivo antes de qualquer processamento.',
                    style: TextStyle(fontSize: 12, color: AppColors.primary),
                  ),
                ),
              ],
            ),
          ),
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

  Widget _line({
    Widget? leading,
    required String title,
    String? subtitle,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          if (leading != null) ...[leading, const SizedBox(width: 10)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 14)),
                if (subtitle != null)
                  Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
        ],
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
        keywords: const ['nome', 'email', 'e-mail', 'pix pessoal', 'conta', 'perfil'],
        action: () => _showEditProfileModal(context, authState.user),
      ),
      _SearchEntry(
        title: 'Sair da Conta',
        where: 'Conta',
        icon: Icons.logout_rounded,
        keywords: const ['logout', 'deslogar', 'trocar de conta'],
        action: () => _confirmSignOut(context),
      ),
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
