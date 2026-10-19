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
          _launchDefaultsPanel(context, financeState),
          _reminderPrefsPanel(context, financeState),
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
      _houseLabelsPanel(context, financeState),
      _shoppingListsPanel(context, financeState),
    ];
  }

  bool _isHouseAdmin(FinanceState financeState) {
    final currentUserId = sl<AuthRepository>().currentUser?.id;
    final me = financeState.members.where((m) => m.id == currentUserId).firstOrNull;
    return me?.role == 'owner' || me?.role == 'admin';
  }

  /// Nome do Caixa nas telas e unidades de compra da casa (0101). Só
  /// administradores mudam.
  Widget _houseLabelsPanel(BuildContext context, FinanceState financeState) {
    final settings = financeState.houseSettings;
    final isAdmin = _isHouseAdmin(financeState);
    return _panel(
      context,
      title: 'Nomes e compras',
      actionLabel: isAdmin ? 'Alterar' : null,
      onAction: isAdmin ? () => _showHouseLabelsDialog(context, financeState) : null,
      children: [
        _line(title: 'Nome do Caixa nas telas', value: settings.cashName),
        _line(title: 'Unidades de compra', value: settings.shoppingUnits.join(', ')),
        if (!isAdmin) _emptyLine('Só administradores mudam estes nomes.'),
      ],
    );
  }

  void _showHouseLabelsDialog(BuildContext context, FinanceState financeState) {
    final saved = financeState.houseSettings;
    final cashController = TextEditingController(text: saved.cashLabel ?? '');
    final unitsController = TextEditingController(text: saved.shoppingUnits.join(', '));
    String? error;
    bool isSaving = false;
    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Nomes e compras', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  key: const ValueKey('cash_label_field'),
                  controller: cashController,
                  maxLength: 30,
                  decoration: InputDecoration(
                    labelText: 'Nome do Caixa',
                    helperText: 'Vazio volta para "${HouseSettings.defaultCashLabel}".',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  key: const ValueKey('shopping_units_field'),
                  controller: unitsController,
                  decoration: const InputDecoration(
                    labelText: 'Unidades de compra',
                    helperText: 'Separadas por vírgula; a primeira é a de um item novo (até 20, de 1 a 8 letras).',
                    helperMaxLines: 3,
                  ),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      error!,
                      key: const Key('house_labels_error'),
                      style: const TextStyle(color: AppColors.debtRed, fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Cancelar')),
            FilledButton(
              onPressed: isSaving
                  ? null
                  : () async {
                      final cash = cashController.text.trim();
                      final units = [
                        for (final u in unitsController.text.split(','))
                          if (u.trim().isNotEmpty) u.trim(),
                      ];
                      if (cash.isNotEmpty && !HouseSettings.isValidCashLabel(cash)) {
                        setDialogState(() => error = 'O nome do Caixa tem até 30 caracteres.');
                        return;
                      }
                      if (!HouseSettings.areValidShoppingUnits(units)) {
                        setDialogState(() => error =
                            'Informe de 1 a 20 unidades diferentes, de 1 a 8 caracteres cada.');
                        return;
                      }
                      final cashChanged = (cash.isEmpty ? null : cash) != saved.cashLabel;
                      final unitsChanged = units.join('\u0000') != saved.shoppingUnits.join('\u0000');
                      setDialogState(() {
                        error = null;
                        isSaving = true;
                      });
                      final messenger = ScaffoldMessenger.of(context);
                      final navigator = Navigator.of(dialogCtx);
                      final ok = (!cashChanged && !unitsChanged) ||
                          await context.read<FinanceCubit>().updateHouseSettings(
                                cashLabel: cashChanged && cash.isNotEmpty ? cash : null,
                                clearCashLabel: cashChanged && cash.isEmpty,
                                shoppingUnits: unitsChanged ? units : null,
                              );
                      if (ok) navigator.pop();
                      setDialogState(() => isSaving = false);
                      showSaveFeedback(messenger, ok: ok, success: 'Nomes da casa atualizados.');
                    },
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
  }

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
                InkWell(
                  key: ValueKey('shopping_list_defaults_${list.id}'),
                  onTap: () => _showShoppingListDefaultsDialog(context, financeState, cubit, list),
                  child: _line(
                    title: list.name,
                    subtitle: list.defaultSplitMode.label,
                    value: financeState.categories.where((c) => c.id == list.defaultCategoryId).firstOrNull?.name ??
                        'Categoria de mercado',
                  ),
                ),
            if (shopping.lists.isNotEmpty)
              _emptyLine('Ao fechar a compra, a despesa usa a categoria e a divisão da lista.'),
          ],
        );
      },
    );
  }

  void _showShoppingListDefaultsDialog(
    BuildContext context,
    FinanceState financeState,
    ShoppingCubit cubit,
    ShoppingList list,
  ) {
    final categories = financeState.categories;
    String? categoryId = categories.any((c) => c.id == list.defaultCategoryId) ? list.defaultCategoryId : null;
    var splitMode = list.defaultSplitMode;
    bool isSaving = false;
    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(list.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<String?>(
                  key: const ValueKey('list_default_category'),
                  initialValue: categoryId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Categoria da compra'),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('Categoria de mercado')),
                    for (final c in categories) DropdownMenuItem<String?>(value: c.id, child: Text(c.name)),
                  ],
                  onChanged: (value) => setDialogState(() => categoryId = value),
                ),
                DropdownButtonFormField<ImportSplitMode>(
                  key: const ValueKey('list_default_split'),
                  initialValue: splitMode,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Divisão da compra'),
                  items: [
                    for (final mode in ImportSplitMode.values)
                      DropdownMenuItem(value: mode, child: Text(mode.label)),
                  ],
                  onChanged: (value) => setDialogState(() => splitMode = value ?? splitMode),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Cancelar')),
            FilledButton(
              onPressed: isSaving
                  ? null
                  : () async {
                      setDialogState(() => isSaving = true);
                      final messenger = ScaffoldMessenger.of(context);
                      final navigator = Navigator.of(dialogCtx);
                      final ok = await cubit.updateListDefaults(list, categoryId: categoryId, splitMode: splitMode);
                      if (ok) navigator.pop();
                      setDialogState(() => isSaving = false);
                      showSaveFeedback(messenger, ok: ok, success: 'Padrões da lista atualizados.');
                    },
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
  }

  // --- Conta: meus padrões de lançamento ---

  static String _launchPayerLabel(LaunchPayer? payer) =>
      payer == LaunchPayer.house ? 'Caixa da casa' : 'Eu';

  /// O que a despesa nova já abre marcada para este morador (0095). Cada um
  /// vê e muda só os próprios.
  Widget _launchDefaultsPanel(BuildContext context, FinanceState financeState) {
    final settings = financeState.memberSettings;
    final method = financeState.paymentMethods
        .where((p) => p.id == settings.launchPaymentMethodId)
        .firstOrNull;
    final category = financeState.categories.where((c) => c.id == settings.launchCategoryId).firstOrNull;
    return _panel(
      context,
      title: 'Meus padrões de lançamento',
      actionLabel: 'Alterar',
      onAction: () => _showLaunchDefaultsDialog(context, financeState),
      children: [
        _line(title: 'Quem paga', value: _launchPayerLabel(settings.launchPayer)),
        _line(
          title: 'Forma de pagamento',
          value: settings.launchPayer == LaunchPayer.house
              ? 'Conta da casa'
              : (method?.name ?? 'A última que usei'),
        ),
        _line(title: 'Categoria', value: category?.name ?? 'A que mais uso'),
        _emptyLine('Valem só para você, ao lançar um gasto. Na hora dá para mudar tudo.'),
      ],
    );
  }

  void _showLaunchDefaultsDialog(BuildContext context, FinanceState financeState) {
    final saved = financeState.memberSettings;
    final methods = financeState.paymentMethods;
    final categories = financeState.categories;
    var payer = saved.launchPayer ?? LaunchPayer.me;
    // Forma ou categoria apagada depois de escolhida volta ao automático
    String? methodId = methods.any((p) => p.id == saved.launchPaymentMethodId) ? saved.launchPaymentMethodId : null;
    String? categoryId = categories.any((c) => c.id == saved.launchCategoryId) ? saved.launchCategoryId : null;
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) {
          Widget title(String text) => Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 4),
                child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold)),
              );
          Widget hint(String text) => Text(text, style: TextStyle(fontSize: 12, color: Colors.grey.shade600));

          return AlertDialog(
            title: const Text(
              'Meus padrões de lançamento',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  hint('O gasto novo já abre com estas escolhas. Só para você; os outros moradores têm os deles.'),
                  title('Quem paga'),
                  Wrap(
                    spacing: 6,
                    children: [
                      for (final option in LaunchPayer.values)
                        ChoiceChip(
                          key: ValueKey('launch_payer_${option.name}'),
                          label: Text(_launchPayerLabel(option)),
                          selected: payer == option,
                          onSelected: (_) => setDialogState(() => payer = option),
                        ),
                    ],
                  ),
                  title('Forma de pagamento'),
                  if (payer == LaunchPayer.house)
                    hint('Pelo Caixa da casa, a forma é a conta da casa.')
                  else
                    DropdownButton<String?>(
                      key: const ValueKey('launch_payment_method'),
                      value: methodId,
                      isExpanded: true,
                      style: Theme.of(context).textTheme.bodyMedium,
                      onChanged: (v) => setDialogState(() => methodId = v),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('A última que usei')),
                        for (final pm in methods)
                          DropdownMenuItem(value: pm.id, child: Text(pm.name, overflow: TextOverflow.ellipsis)),
                      ],
                    ),
                  title('Categoria'),
                  DropdownButton<String?>(
                    key: const ValueKey('launch_category'),
                    value: categoryId,
                    isExpanded: true,
                    style: Theme.of(context).textTheme.bodyMedium,
                    onChanged: (v) => setDialogState(() => categoryId = v),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('A que mais uso')),
                      for (final cat in categories)
                        DropdownMenuItem(value: cat.id, child: Text(cat.name, overflow: TextOverflow.ellipsis)),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: isSaving
                    ? null
                    : () async {
                        setDialogState(() => isSaving = true);
                        final messenger = ScaffoldMessenger.of(context);
                        final navigator = Navigator.of(dialogCtx);
                        // "Eu" é o automático: não precisa ficar gravado
                        final next = saved.withLaunchDefaults(
                          payer: payer == LaunchPayer.house ? LaunchPayer.house : null,
                          paymentMethodId: payer == LaunchPayer.house ? null : methodId,
                          categoryId: categoryId,
                        );
                        final ok = next == saved ||
                            await context.read<FinanceCubit>().updateMemberSettings(next);
                        if (ok) navigator.pop();
                        setDialogState(() => isSaving = false);
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
          );
        },
      ),
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
      _newMemberSplitPanel(context, financeState),
      _incomeSplitPanel(context, financeState),
      _planningPanel(context, financeState),
      _folegoParamsPanel(context, financeState),
      _budgetAlertPanel(context, financeState),
      _closingDefaultsPanel(context, financeState),
      _initialBalancePanel(context, financeState),
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

  /// O que acontece com o rateio padrão quando entra um morador (0097). Só
  /// administradores mudam; com a política "perguntar", avisa enquanto houver
  /// morador sem parte na divisão.
  Widget _newMemberSplitPanel(BuildContext context, FinanceState financeState) {
    final policy = financeState.houseSettings.newMemberSplitPolicy;
    final currentUserId = sl<AuthRepository>().currentUser?.id;
    final me = financeState.members.where((m) => m.id == currentUserId).firstOrNull;
    final isAdmin = me?.role == 'owner' || me?.role == 'admin';
    final withoutShare = financeState.members.length > 1
        ? financeState.members.where((m) => m.defaultSplitPercent <= 0).toList()
        : <HouseMember>[];
    return _panel(
      context,
      title: 'Divisão para quem entra',
      actionLabel: isAdmin ? 'Alterar' : null,
      onAction: isAdmin ? () => _showNewMemberSplitDialog(context, financeState) : null,
      children: [
        _line(title: 'Ao entrar um morador', value: policy.label),
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
        if (!isAdmin) _emptyLine('Só administradores mudam esta escolha.'),
      ],
    );
  }

  /// Renda de cada morador e divisão padrão "proporcional à renda" (0102). A
  /// renda é privada por padrão: só aparece a dos outros se a casa permitir, e
  /// quem manda no que chega ao app é o banco (RLS), não esta tela.
  Widget _incomeSplitPanel(BuildContext context, FinanceState financeState) {
    final settings = financeState.houseSettings;
    final currentUserId = sl<AuthRepository>().currentUser?.id;
    final isAdmin = _isHouseAdmin(financeState);
    final myIncome = financeState.memberIncomes[currentUserId];
    final others = [
      for (final m in financeState.members)
        if (m.id != currentUserId && financeState.memberIncomes.containsKey(m.id)) m,
    ];
    return _panel(
      context,
      title: 'Renda e divisão',
      actionLabel: isAdmin ? 'Alterar' : null,
      onAction: isAdmin ? () => _showIncomeSplitDialog(context, financeState) : null,
      children: [
        _line(title: 'Divisão padrão', value: settings.splitBasis.label),
        _line(title: 'Quem vê a renda', value: settings.incomeVisibility.label),
        _line(title: 'Minha renda mensal', value: myIncome?.format() ?? 'Não informada'),
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: TextButton(
              key: const Key('my_income_button'),
              onPressed: () => _showMyIncomeDialog(context, myIncome),
              child: Text(myIncome == null ? 'Informar minha renda' : 'Alterar minha renda'),
            ),
          ),
        ),
        for (final m in others) _line(title: 'Renda de ${m.name}', value: financeState.memberIncomes[m.id]!.format()),
        if (others.isEmpty)
          _emptyLine('A renda dos outros moradores é privada: só o percentual calculado aparece na divisão.'),
        if (settings.splitBasis == SplitBasis.income)
          _emptyLine(
            'Enquanto algum morador não informar a renda, vale o rateio atual.',
          ),
      ],
    );
  }

  void _showMyIncomeDialog(BuildContext context, Money? current) {
    var cents = current?.cents ?? 0;
    bool isSaving = false;
    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Minha renda mensal', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Usada só para calcular a divisão proporcional à renda. Quem pode ver este valor é escolha da casa.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 12),
                MoneyInputField(
                  key: const ValueKey('my_income_field'),
                  initialValue: Money(cents),
                  label: 'Renda mensal',
                  onChanged: (v) => setDialogState(() => cents = v.cents),
                ),
              ],
            ),
          ),
          actions: [
            if (current != null)
              TextButton(
                onPressed: isSaving
                    ? null
                    : () async {
                        setDialogState(() => isSaving = true);
                        final messenger = ScaffoldMessenger.of(context);
                        final navigator = Navigator.of(dialogCtx);
                        final ok = await context.read<FinanceCubit>().setMyIncome(null);
                        if (ok) navigator.pop();
                        setDialogState(() => isSaving = false);
                        showSaveFeedback(messenger, ok: ok, success: 'Renda removida.');
                      },
                child: const Text('Remover'),
              ),
            TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Cancelar')),
            FilledButton(
              onPressed: isSaving || cents <= 0
                  ? null
                  : () async {
                      setDialogState(() => isSaving = true);
                      final messenger = ScaffoldMessenger.of(context);
                      final navigator = Navigator.of(dialogCtx);
                      final ok = await context.read<FinanceCubit>().setMyIncome(Money(cents));
                      if (ok) navigator.pop();
                      setDialogState(() => isSaving = false);
                      showSaveFeedback(messenger, ok: ok, success: 'Renda atualizada.');
                    },
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
  }

  void _showIncomeSplitDialog(BuildContext context, FinanceState financeState) {
    final saved = financeState.houseSettings;
    var basis = saved.splitBasis;
    var visibility = saved.incomeVisibility;
    bool isSaving = false;
    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Renda e divisão', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Divisão padrão', style: TextStyle(fontWeight: FontWeight.bold)),
                for (final b in SplitBasis.values)
                  ListTile(
                    key: ValueKey('split_basis_${b.dbValue}'),
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      basis == b ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                      color: basis == b ? AppColors.primary : Colors.grey,
                    ),
                    title: Text(b.label),
                    onTap: () => setDialogState(() => basis = b),
                  ),
                const Divider(),
                const Text('Quem vê a renda', style: TextStyle(fontWeight: FontWeight.bold)),
                for (final v in IncomeVisibility.values)
                  ListTile(
                    key: ValueKey('income_visibility_${v.dbValue}'),
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      visibility == v ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                      color: visibility == v ? AppColors.primary : Colors.grey,
                    ),
                    title: Text(v.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(v.description, style: const TextStyle(fontSize: 12)),
                    onTap: () => setDialogState(() => visibility = v),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Cancelar')),
            FilledButton(
              onPressed: isSaving
                  ? null
                  : () async {
                      setDialogState(() => isSaving = true);
                      final messenger = ScaffoldMessenger.of(context);
                      final navigator = Navigator.of(dialogCtx);
                      final changed = basis != saved.splitBasis || visibility != saved.incomeVisibility;
                      final ok = !changed ||
                          await context.read<FinanceCubit>().updateHouseSettings(
                                splitBasis: basis != saved.splitBasis ? basis : null,
                                incomeVisibility: visibility != saved.incomeVisibility ? visibility : null,
                              );
                      if (ok) navigator.pop();
                      setDialogState(() => isSaving = false);
                      showSaveFeedback(messenger, ok: ok, success: 'Renda e divisão atualizadas.');
                    },
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
  }

  void _showNewMemberSplitDialog(BuildContext context, FinanceState financeState) {
    final saved = financeState.houseSettings.newMemberSplitPolicy;
    var choice = saved;
    bool isSaving = false;
    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text(
            'Divisão para quem entra',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final policy in NewMemberSplitPolicy.values)
                  ListTile(
                    key: ValueKey('new_member_policy_${policy.dbValue}'),
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      choice == policy ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                      color: choice == policy ? AppColors.primary : Colors.grey,
                    ),
                    title: Text(policy.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(policy.description, style: const TextStyle(fontSize: 12)),
                    onTap: () => setDialogState(() => choice = policy),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: isSaving
                  ? null
                  : () async {
                      setDialogState(() => isSaving = true);
                      final messenger = ScaffoldMessenger.of(context);
                      final navigator = Navigator.of(dialogCtx);
                      final ok = choice == saved ||
                          await context.read<FinanceCubit>().updateHouseSettings(newMemberSplitPolicy: choice);
                      if (ok) navigator.pop();
                      setDialogState(() => isSaving = false);
                      showSaveFeedback(messenger, ok: ok, success: 'Divisão para quem entra atualizada.');
                    },
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
  }

  /// Limites do Fôlego, horizonte das recorrentes e transição do dia do ciclo
  /// (0098). Só administradores mudam.
  Widget _folegoParamsPanel(BuildContext context, FinanceState financeState) {
    final params = financeState.houseSettings.folegoParams;
    final currentUserId = sl<AuthRepository>().currentUser?.id;
    final me = financeState.members.where((m) => m.id == currentUserId).firstOrNull;
    final isAdmin = me?.role == 'owner' || me?.role == 'admin';
    return _panel(
      context,
      title: 'Fôlego e Ciclo',
      actionLabel: isAdmin ? 'Alterar' : null,
      onAction: isAdmin ? () => _showFolegoParamsDialog(context, financeState) : null,
      children: [
        _line(title: 'Fôlego em atenção abaixo de', value: '${params.warningPercent}% dos aportes'),
        _line(
          title: 'Barra de comprometimento',
          value: 'atenção acima de ${params.commitmentWarningPercent}%, crítica acima de ${params.commitmentDangerPercent}%',
        ),
        _line(
          title: 'Gasto diário confortável a partir de',
          value: Money(params.comfortableDailyCents).format(),
        ),
        _line(title: 'Contas recorrentes geradas até', value: '${params.recurringHorizonMonths} meses à frente'),
        _line(title: 'Ciclo de transição (troca do dia)', value: 'mínimo de ${params.transitionMinDays} dias'),
        if (!isAdmin) _emptyLine('Só administradores mudam estes limites.'),
      ],
    );
  }

  void _showFolegoParamsDialog(BuildContext context, FinanceState financeState) {
    final saved = financeState.houseSettings.folegoParams;
    final fields = <String, TextEditingController>{
      'warning': TextEditingController(text: '${saved.warningPercent}'),
      'commitment_warning': TextEditingController(text: '${saved.commitmentWarningPercent}'),
      'commitment_danger': TextEditingController(text: '${saved.commitmentDangerPercent}'),
      'daily': TextEditingController(text: '${saved.comfortableDailyCents ~/ 100}'),
      'horizon': TextEditingController(text: '${saved.recurringHorizonMonths}'),
      'transition': TextEditingController(text: '${saved.transitionMinDays}'),
    };
    const labels = {
      'warning': 'Atenção abaixo de (% dos aportes)',
      'commitment_warning': 'Barra em atenção acima de (%)',
      'commitment_danger': 'Barra crítica acima de (%)',
      'daily': 'Gasto diário confortável (R\$)',
      'horizon': 'Recorrentes à frente (1 a 6 meses)',
      'transition': 'Transição do ciclo (15 a 30 dias)',
    };
    String? error;
    bool isSaving = false;
    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Fôlego e Ciclo', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final entry in labels.entries)
                  TextField(
                    key: ValueKey('folego_param_${entry.key}'),
                    controller: fields[entry.key],
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: entry.value),
                  ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      error!,
                      key: const Key('folego_params_error'),
                      style: const TextStyle(color: AppColors.debtRed, fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Cancelar')),
            FilledButton(
              onPressed: isSaving
                  ? null
                  : () async {
                      int? read(String key) => int.tryParse(fields[key]!.text.trim());
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
                        setDialogState(() => error =
                            'Confira os valores: percentuais de 0 a 100 (atenção da barra abaixo da crítica), '
                            'recorrentes de 1 a 6 meses e transição de 15 a 30 dias.');
                        return;
                      }
                      setDialogState(() {
                        error = null;
                        isSaving = true;
                      });
                      final messenger = ScaffoldMessenger.of(context);
                      final navigator = Navigator.of(dialogCtx);
                      final ok = next == saved ||
                          await context.read<FinanceCubit>().updateHouseSettings(folegoParams: next);
                      if (ok) navigator.pop();
                      setDialogState(() => isSaving = false);
                      showSaveFeedback(messenger, ok: ok, success: 'Parâmetros do Fôlego atualizados.');
                    },
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
  }

  /// Estágios do alerta de orçamento das categorias (0099). Só administradores
  /// mudam; cada categoria pode ter os seus ao ser editada.
  Widget _budgetAlertPanel(BuildContext context, FinanceState financeState) {
    final stages = financeState.houseSettings.budgetAlertStages;
    final currentUserId = sl<AuthRepository>().currentUser?.id;
    final me = financeState.members.where((m) => m.id == currentUserId).firstOrNull;
    final isAdmin = me?.role == 'owner' || me?.role == 'admin';
    final custom = financeState.categories.where((c) => c.budgetAlertStages != null).length;
    return _panel(
      context,
      title: 'Alertas de orçamento',
      actionLabel: isAdmin ? 'Alterar' : null,
      onAction: isAdmin ? () => _showBudgetAlertDialog(context, financeState) : null,
      children: [
        _line(title: 'Avisar ao chegar em', value: '${stages.label} da média'),
        if (custom > 0) _line(title: 'Categorias com estágios próprios', value: '$custom'),
        _emptyLine(isAdmin
            ? 'Cada categoria pode ter os seus ao ser editada.'
            : 'Só administradores mudam os estágios.'),
      ],
    );
  }

  void _showBudgetAlertDialog(BuildContext context, FinanceState financeState) {
    final saved = financeState.houseSettings.budgetAlertStages;
    final controller = TextEditingController(text: saved.editText);
    String? error;
    bool isSaving = false;
    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Alertas de orçamento', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const ValueKey('budget_alert_stages'),
                controller: controller,
                decoration: const InputDecoration(
                  labelText: 'Percentuais da média (ex.: 80, 100)',
                  helperText: 'Abaixo de 100 avisa ao chegar; de 100 em diante, ao passar.',
                  helperMaxLines: 2,
                ),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    error!,
                    key: const Key('budget_alert_error'),
                    style: const TextStyle(color: AppColors.debtRed, fontSize: 12),
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Cancelar')),
            FilledButton(
              onPressed: isSaving
                  ? null
                  : () async {
                      final next = BudgetAlertStages.parse(controller.text);
                      if (next == null) {
                        setDialogState(() => error =
                            'Use de 1 a 4 percentuais crescentes, de 1 a 300 (ex.: 80, 100).');
                        return;
                      }
                      setDialogState(() {
                        error = null;
                        isSaving = true;
                      });
                      final messenger = ScaffoldMessenger.of(context);
                      final navigator = Navigator.of(dialogCtx);
                      final ok = next == saved ||
                          await context.read<FinanceCubit>().updateHouseSettings(budgetAlertStages: next);
                      if (ok) navigator.pop();
                      setDialogState(() => isSaving = false);
                      showSaveFeedback(messenger, ok: ok, success: 'Alertas de orçamento atualizados.');
                    },
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
  }

  static const _reminderGroupLabels = {
    'bills': 'Contas a vencer e atrasadas',
    'invoices': 'Faturas do cartão',
    'cycle': 'Ciclo e aportes',
    'loans': 'Parcelas de empréstimo',
    'tasks': 'Tarefas',
    'budget': 'Alertas de orçamento',
  };
  static const _weekdayNames = ['Domingo', 'Segunda', 'Terça', 'Quarta', 'Quinta', 'Sexta', 'Sábado'];

  static String _hourLabel(int hour) => '${hour.toString().padLeft(2, '0')}h';

  /// Horário dos lembretes do dia, grupos silenciados e dia do resumo semanal
  /// de cada morador (0099). Cada um vê e muda só os seus.
  Widget _reminderPrefsPanel(BuildContext context, FinanceState financeState) {
    final settings = financeState.memberSettings;
    final muted = settings.mutedReminders;
    return _panel(
      context,
      title: 'Meus lembretes',
      actionLabel: 'Alterar',
      onAction: () => _showReminderPrefsDialog(context, financeState),
      children: [
        _line(title: 'Lembretes do dia a partir das', value: _hourLabel(settings.alertHour)),
        _line(
          title: 'Silenciados',
          value: muted.isEmpty
              ? 'Nenhum'
              : [for (final g in MemberSettings.reminderGroups) if (muted.contains(g)) _reminderGroupLabels[g]!]
                  .join(', '),
        ),
        _line(
          title: 'Resumo semanal',
          value: '${_weekdayNames[settings.weeklyDay]}, ${_hourLabel(settings.weeklyHour)}',
        ),
        _emptyLine('Valem só para você, no fuso da casa. Avisos essenciais chegam sempre.'),
      ],
    );
  }

  void _showReminderPrefsDialog(BuildContext context, FinanceState financeState) {
    final saved = financeState.memberSettings;
    var alertHour = saved.alertHour;
    var weeklyDay = saved.weeklyDay;
    var weeklyHour = saved.weeklyHour;
    final muted = Set<String>.of(saved.mutedReminders);
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) {
          Widget title(String text) => Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 4),
                child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold)),
              );
          Widget hourPicker(Key key, int value, ValueChanged<int> onChanged) => DropdownButton<int>(
                key: key,
                value: value,
                isExpanded: true,
                style: Theme.of(context).textTheme.bodyMedium,
                onChanged: (v) => setDialogState(() => onChanged(v ?? value)),
                items: [
                  for (var h = 0; h < 24; h++) DropdownMenuItem(value: h, child: Text(_hourLabel(h))),
                ],
              );

          return AlertDialog(
            title: const Text('Meus lembretes', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  title('Lembretes do dia a partir das'),
                  hourPicker(const ValueKey('alert_hour'), alertHour, (v) => alertHour = v),
                  title('Receber lembretes de'),
                  for (final group in MemberSettings.reminderGroups)
                    SwitchListTile(
                      key: ValueKey('reminder_$group'),
                      contentPadding: EdgeInsets.zero,
                      title: Text(_reminderGroupLabels[group]!, style: const TextStyle(fontSize: 14)),
                      value: !muted.contains(group),
                      onChanged: (on) => setDialogState(() => on ? muted.remove(group) : muted.add(group)),
                    ),
                  title('Resumo semanal'),
                  DropdownButton<int>(
                    key: const ValueKey('weekly_day'),
                    value: weeklyDay,
                    isExpanded: true,
                    style: Theme.of(context).textTheme.bodyMedium,
                    onChanged: (v) => setDialogState(() => weeklyDay = v ?? weeklyDay),
                    items: [
                      for (var d = 0; d < 7; d++) DropdownMenuItem(value: d, child: Text(_weekdayNames[d])),
                    ],
                  ),
                  hourPicker(const ValueKey('weekly_hour'), weeklyHour, (v) => weeklyHour = v),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Cancelar')),
              FilledButton(
                onPressed: isSaving
                    ? null
                    : () async {
                        setDialogState(() => isSaving = true);
                        final messenger = ScaffoldMessenger.of(context);
                        final navigator = Navigator.of(dialogCtx);
                        final next = saved.withAlertPrefs(
                          alertHour: alertHour,
                          muted: muted,
                          weeklyDay: weeklyDay,
                          weeklyHour: weeklyHour,
                        );
                        final ok = next == saved ||
                            await context.read<FinanceCubit>().updateMemberSettings(next);
                        if (ok) navigator.pop();
                        setDialogState(() => isSaving = false);
                        showSaveFeedback(messenger, ok: ok, success: 'Seus lembretes foram atualizados.');
                      },
                style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                child: const Text('Salvar'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _planningPanel(BuildContext context, FinanceState financeState) {
    final settings = financeState.houseSettings;
    final inflowRules = settings.inflowRules;
    final vaultOverrides = inflowRules.vaultOverrides.keys
        .where((id) => financeState.savingsVaults.any((v) => v.id == id))
        .length;
    final vaultDefault = inflowRules.vaultWithdrawals ?? OpeningBalanceRule.keep;
    return _panel(
      context,
      title: 'Planejamento e Fechamento',
      actionLabel: 'Alterar',
      onAction: () => _showPlanningSettingsDialog(context, financeState),
      children: [
        _line(
          title: 'Sobra do ciclo anterior',
          value: inflowRules.rolledSurplusRule(settings.openingBalanceRule)?.label ?? 'Padrão',
        ),
        _line(
          title: 'Empréstimo do Caixa pago de volta',
          value: inflowRules.houseLoansRepaidRule(settings.openingBalanceRule)?.label ?? 'Padrão',
        ),
        _line(
          title: 'Resgate de caixinha',
          value: vaultOverrides == 0
              ? vaultDefault.label
              : '${vaultDefault.label} (+$vaultOverrides com regra própria)',
        ),
        _line(
          title: 'Entrada de fora',
          value: inflowRules.thirdParty?.label ?? 'Igual à sobra',
        ),
        _line(
          title: 'Média dos gastos variáveis',
          value: settings.historyCycles == 1 ? 'Último ciclo' : 'Últimos ${settings.historyCycles} ciclos',
        ),
        _line(
          title: 'Modos Econômico e Com folga',
          value: '${settings.adjustPercent}%',
        ),
      ],
    );
  }

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

  /// Escolhas que o fechamento já abre marcadas (0094). Caixinha apagada
  /// depois de escolhida vale como sem escolha.
  Widget _closingDefaultsPanel(BuildContext context, FinanceState financeState) {
    final defaults = financeState.houseSettings.closingDefaults;
    final vaults = financeState.savingsVaults;
    final currentUserId = sl<AuthRepository>().currentUser?.id;
    final me = financeState.members.where((m) => m.id == currentUserId).firstOrNull;
    final isAdmin = me?.role == 'owner' || me?.role == 'admin';
    String? vaultName(String? id) => vaults.where((v) => v.id == id).firstOrNull?.name;
    final surplusAction = defaults.surplusAction ?? SurplusAction.toVault;
    final surplusVault = vaultName(defaults.surplusVaultId);
    return _panel(
      context,
      title: 'Padrões do fechamento',
      actionLabel: isAdmin ? 'Alterar' : null,
      onAction: isAdmin ? () => _showClosingDefaultsDialog(context, financeState) : null,
      children: [
        _line(
          title: 'Destino da sobra',
          value: surplusAction == SurplusAction.toVault && surplusVault != null
              ? 'Caixinha $surplusVault'
              : _surplusActionLabel(surplusAction),
        ),
        _line(
          title: 'Gastos acima do balde',
          subtitle: vaultName(defaults.deficitVaultId) == null
              ? null
              : 'Antes, usa a caixinha ${vaultName(defaults.deficitVaultId)}',
          value: _deficitSplitLabel(defaults.deficitSplit ?? DeficitSplit.proportional),
        ),
        _line(
          title: 'Quem pagou menos',
          value: _shortfallActionLabel(defaults.shortfallAction ?? ShortfallAction.createP2PLoan),
        ),
        if (!isAdmin)
          _emptyLine('O fechamento abre com estas escolhas. Só administradores mudam os padrões.'),
      ],
    );
  }

  void _showClosingDefaultsDialog(BuildContext context, FinanceState financeState) {
    final saved = financeState.houseSettings.closingDefaults;
    final vaults = financeState.savingsVaults;
    // Começa pelo que vale hoje: o padrão guardado ou, sem ele, o de sempre
    final surplusBefore = saved.surplusAction ?? SurplusAction.toVault;
    final splitBefore = saved.deficitSplit ?? DeficitSplit.proportional;
    final shortfallBefore = saved.shortfallAction ?? ShortfallAction.createP2PLoan;
    var surplusAction = surplusBefore;
    String? surplusVaultId = saved.surplusVaultIn(vaults);
    var deficitSplit = splitBefore;
    String? deficitVaultId = saved.deficitVaultIn(vaults);
    var shortfallAction = shortfallBefore;
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) {
          Widget title(String text) => Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 4),
                child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold)),
              );
          Widget hint(String text) => Text(text, style: TextStyle(fontSize: 12, color: Colors.grey.shade600));
          Widget vaultDropdown({
            required Key key,
            required String? value,
            required String emptyLabel,
            required ValueChanged<String?> onChanged,
          }) =>
              DropdownButton<String?>(
                key: key,
                value: value,
                isExpanded: true,
                style: Theme.of(context).textTheme.bodyMedium,
                onChanged: (v) => setDialogState(() => onChanged(v)),
                items: [
                  DropdownMenuItem(value: null, child: Text(emptyLabel)),
                  for (final vault in vaults)
                    DropdownMenuItem(value: vault.id, child: Text(vault.name, overflow: TextOverflow.ellipsis)),
                ],
              );

          return AlertDialog(
            title: const Text(
              'Padrões do fechamento',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  hint('O fechamento já abre com estas escolhas. Quem fecha ainda pode mudar cada uma naquele ciclo.'),
                  title('Destino da sobra'),
                  Wrap(
                    spacing: 6,
                    children: [
                      for (final action in SurplusAction.values)
                        ChoiceChip(
                          label: Text(_surplusActionLabel(action)),
                          selected: surplusAction == action,
                          onSelected: (_) => setDialogState(() => surplusAction = action),
                        ),
                    ],
                  ),
                  if (surplusAction == SurplusAction.toVault && vaults.isNotEmpty)
                    vaultDropdown(
                      key: const ValueKey('closing_surplus_vault'),
                      value: surplusVaultId,
                      emptyLabel: 'A primeira caixinha da lista',
                      onChanged: (v) => surplusVaultId = v,
                    ),
                  title('Gastos acima do balde'),
                  Wrap(
                    spacing: 6,
                    children: [
                      for (final split in DeficitSplit.values)
                        ChoiceChip(
                          label: Text(_deficitSplitLabel(split)),
                          selected: deficitSplit == split,
                          onSelected: (_) => setDialogState(() => deficitSplit = split),
                        ),
                    ],
                  ),
                  if (vaults.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    hint('Caixinha que cobre o excedente antes do rateio:'),
                    vaultDropdown(
                      key: const ValueKey('closing_deficit_vault'),
                      value: deficitVaultId,
                      emptyLabel: 'Não usar caixinha',
                      onChanged: (v) => deficitVaultId = v,
                    ),
                  ],
                  title('Quem pagou menos no Super Pix'),
                  Wrap(
                    spacing: 6,
                    children: [
                      for (final action in ShortfallAction.values)
                        ChoiceChip(
                          label: Text(_shortfallActionLabel(action)),
                          selected: shortfallAction == action,
                          onSelected: (_) => setDialogState(() => shortfallAction = action),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: isSaving
                    ? null
                    : () async {
                        setDialogState(() => isSaving = true);
                        final messenger = ScaffoldMessenger.of(context);
                        final navigator = Navigator.of(dialogCtx);
                        // Só o que mudou ganha escolha própria; o resto segue como estava
                        final defaults = ClosingDefaults(
                          surplusAction: surplusAction != surplusBefore ? surplusAction : saved.surplusAction,
                          surplusVaultId: surplusAction == SurplusAction.toVault ? surplusVaultId : null,
                          deficitSplit: deficitSplit != splitBefore ? deficitSplit : saved.deficitSplit,
                          deficitVaultId: deficitVaultId,
                          shortfallAction:
                              shortfallAction != shortfallBefore ? shortfallAction : saved.shortfallAction,
                        );
                        final ok = defaults == saved ||
                            await context.read<FinanceCubit>().updateHouseSettings(closingDefaults: defaults);
                        if (ok) navigator.pop();
                        setDialogState(() => isSaving = false);
                        showSaveFeedback(
                          messenger,
                          ok: ok,
                          success: 'Padrões do fechamento atualizados.',
                        );
                      },
                style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                child: const Text('Salvar'),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Dinheiro que a casa já tinha ao começar a usar o app (0093).
  Widget _initialBalancePanel(BuildContext context, FinanceState financeState) {
    final initial = financeState.initialBalance;
    final currentUserId = sl<AuthRepository>().currentUser?.id;
    final me = financeState.members.where((m) => m.id == currentUserId).firstOrNull;
    final isAdmin = me?.role == 'owner' || me?.role == 'admin';
    final cashStart = initial.cashCycleStart;
    return _panel(
      context,
      title: 'Saldo inicial da casa',
      actionLabel: isAdmin ? (initial.isEmpty ? 'Informar' : 'Alterar') : null,
      onAction: isAdmin ? () => _showInitialBalanceDialog(context, financeState) : null,
      children: [
        if (initial.isEmpty)
          _emptyLine(
            isAdmin
                ? 'A casa começou do zero. Se já havia dinheiro guardado ou na conta da casa, informe aqui.'
                : 'A casa começou do zero. Só administradores informam o saldo inicial.',
          )
        else ...[
          _line(title: 'Reserva guardada', value: initial.reserve.format()),
          _line(
            title: 'Saldo na conta da casa',
            subtitle: cashStart == null
                ? null
                : 'Sobra do ciclo que começou em ${_twoDigits(cashStart.day)}/${_twoDigits(cashStart.month)}',
            value: initial.cash.format(),
          ),
        ],
      ],
    );
  }

  static String _twoDigits(int n) => n.toString().padLeft(2, '0');

  void _showInitialBalanceDialog(BuildContext context, FinanceState financeState) {
    final initial = financeState.initialBalance;
    var reserve = initial.reserve;
    var cash = initial.cash;
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text(
            'Saldo inicial da casa',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'O dinheiro que a casa já tinha quando começou a usar o app. Pode deixar em branco o que não houver.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 16),
                MoneyTextFormField(
                  key: const ValueKey('initial_reserve_field'),
                  initialValue: reserve,
                  labelText: 'Reserva guardada',
                  helperText: 'Entra na Reserva da Casa. Não mexe no Caixa do ciclo.',
                  prefixIcon: const Icon(Icons.savings_outlined),
                  onChanged: (m) => reserve = m,
                ),
                const SizedBox(height: 12),
                MoneyTextFormField(
                  key: const ValueKey('initial_cash_field'),
                  initialValue: cash,
                  labelText: 'Saldo na conta da casa',
                  helperText: 'Vale como a sobra do primeiro ciclo e segue a regra da sobra.',
                  prefixIcon: const Icon(Icons.account_balance_wallet_outlined),
                  onChanged: (m) => cash = m,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: isSaving
                  ? null
                  : () async {
                      setDialogState(() => isSaving = true);
                      final messenger = ScaffoldMessenger.of(context);
                      final navigator = Navigator.of(dialogCtx);
                      final error = await context.read<FinanceCubit>().setHouseInitialBalance(
                            reserve: reserve,
                            cash: cash,
                          );
                      if (error == null) navigator.pop();
                      setDialogState(() => isSaving = false);
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
      ),
    );
  }

  void _showPlanningSettingsDialog(BuildContext context, FinanceState financeState) {
    final settings = financeState.houseSettings;
    final currentUserId = sl<AuthRepository>().currentUser?.id;
    final me = financeState.members.where((m) => m.id == currentUserId).firstOrNull;
    final isAdmin = me?.role == 'owner' || me?.role == 'admin';
    final usesFixed = financeState.members.any((m) => (m.defaultFixedAmountCents ?? 0) > 0);
    // Cada tipo de entrada no Caixa com a sua regra (0092). Sem escolha
    // própria, sobra e empréstimo seguem a regra única de antes.
    final savedRules = settings.inflowRules;
    final rolledBefore = savedRules.rolledSurplusRule(settings.openingBalanceRule);
    final loansBefore = savedRules.houseLoansRepaidRule(settings.openingBalanceRule);
    OpeningBalanceRule? rolledRule = rolledBefore;
    OpeningBalanceRule? loansRule = loansBefore;
    OpeningBalanceRule vaultDefault = savedRules.vaultWithdrawals ?? OpeningBalanceRule.keep;
    final vaults = financeState.savingsVaults;
    final vaultOverrides = Map<String, OpeningBalanceRule>.of(savedRules.vaultOverrides);
    // Entrada de fora (0096): sem escolha própria, segue a sobra
    OpeningBalanceRule? thirdPartyRule = savedRules.thirdParty;
    int historyCycles = settings.historyCycles;
    int adjustPercent = settings.adjustPercent;
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final options = [
            OpeningBalanceRule.reduceQuotas,
            if (usesFixed) OpeningBalanceRule.coverExcess,
            OpeningBalanceRule.keep,
          ];
          // Escolha de uma regra: chips e, embaixo, o que a escolhida faz
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
                          onSelected: isAdmin ? (_) => setDialogState(() => onSelected(option)) : null,
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

          return AlertDialog(
            title: const Text(
              'Planejamento e Fechamento',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Dinheiro que já está no Caixa',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'O que cada tipo de dinheiro que entrou no Caixa sem ser aporte faz no aporte de cada morador. Vale no planejador e no fechamento.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  if (!isAdmin)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text(
                        'Só administradores mudam estas regras.',
                        style: TextStyle(fontSize: 12, color: AppColors.accent),
                      ),
                    ),
                  kindTitle('Sobra do ciclo anterior'),
                  ruleChoice(rolledRule, (r) => rolledRule = r, defaultHint: defaultHint),
                  kindTitle('Empréstimo do Caixa pago de volta'),
                  ruleChoice(loansRule, (r) => loansRule = r, defaultHint: defaultHint),
                  kindTitle('Resgate de caixinha'),
                  ruleChoice(vaultDefault, (r) => vaultDefault = r),
                  if (lowersVault(vaultDefault)) vaultWarning,
                  for (final vault in vaults) ...[
                    Row(
                      children: [
                        Expanded(
                          child: Text(vault.name, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis),
                        ),
                        DropdownButton<OpeningBalanceRule?>(
                          value: options.contains(vaultOverrides[vault.id]) ? vaultOverrides[vault.id] : null,
                          isDense: true,
                          // Sem regra própria o botão mostra a dica
                          hint: const Text('Igual ao padrão'),
                          disabledHint: Text(vaultOverrides[vault.id]?.label ?? 'Igual ao padrão'),
                          style: Theme.of(context).textTheme.bodyMedium,
                          onChanged: isAdmin
                              ? (r) => setDialogState(() {
                                    if (r == null) {
                                      vaultOverrides.remove(vault.id);
                                    } else {
                                      vaultOverrides[vault.id] = r;
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
                    if (lowersVault(vaultOverrides[vault.id]) && !lowersVault(vaultDefault)) vaultWarning,
                  ],
                  kindTitle('Entrada de fora'),
                  ruleChoice(thirdPartyRule ?? rolledRule, (r) => thirdPartyRule = r),
                  if (thirdPartyRule == null)
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
                          selected: historyCycles == n,
                          onSelected: (_) => setDialogState(() => historyCycles = n),
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
                          selected: adjustPercent == p,
                          onSelected: (_) => setDialogState(() => adjustPercent = p),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: isSaving
                    ? null
                    : () async {
                        setDialogState(() => isSaving = true);
                        final messenger = ScaffoldMessenger.of(context);
                        final navigator = Navigator.of(dialogCtx);
                        // Só o que mudou ganha escolha própria; o resto segue como estava
                        final rules = OpeningInflowRules(
                          rolledSurplus: rolledRule != rolledBefore ? rolledRule : savedRules.rolledSurplus,
                          houseLoansRepaid: loansRule != loansBefore ? loansRule : savedRules.houseLoansRepaid,
                          vaultWithdrawals: vaultDefault != (savedRules.vaultWithdrawals ?? OpeningBalanceRule.keep)
                              ? vaultDefault
                              : savedRules.vaultWithdrawals,
                          vaultOverrides: vaultOverrides,
                          thirdParty: thirdPartyRule,
                        );
                        final ok = await context.read<FinanceCubit>().updateHouseSettings(
                              inflowRules: isAdmin && rules != savedRules ? rules : null,
                              historyCycles: historyCycles != settings.historyCycles ? historyCycles : null,
                              adjustPercent: adjustPercent != settings.adjustPercent ? adjustPercent : null,
                            );
                        if (ok) navigator.pop();
                        setDialogState(() => isSaving = false);
                        showSaveFeedback(
                          messenger,
                          ok: ok,
                          success: 'Planejamento e fechamento atualizados.',
                        );
                      },
                style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                child: const Text('Salvar'),
              ),
            ],
          );
        },
      ),
    );
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
      _importParamsPanel(context, financeState),
      _panel(
        context,
        title: 'Assinaturas & Contas Fixas',
        children: [_recurringExpensesEditor(context)],
      ),
    ];
  }

  /// Janelas do casamento de linhas e destino padrão das linhas novas da
  /// importação de extrato (0100). Só administradores mudam.
  Widget _importParamsPanel(BuildContext context, FinanceState financeState) {
    final settings = financeState.houseSettings;
    final matching = settings.importMatching;
    final defaults = settings.importDefaults;
    final currentUserId = sl<AuthRepository>().currentUser?.id;
    final me = financeState.members.where((m) => m.id == currentUserId).firstOrNull;
    final isAdmin = me?.role == 'owner' || me?.role == 'admin';
    final category = financeState.categories.where((c) => c.id == defaults.categoryId).firstOrNull;
    final source = financeState.paymentMethods.where((p) => p.id == defaults.paymentMethodId).firstOrNull;
    return _panel(
      context,
      title: 'Importação de extrato',
      actionLabel: isAdmin ? 'Alterar' : null,
      onAction: isAdmin ? () => _showImportParamsDialog(context, financeState) : null,
      children: [
        _line(
          title: 'Mesma compra se a data difere até',
          value: '${matching.dateWindowDays} dias (${matching.otherMethodWindowDays} em outra forma de pagamento)',
        ),
        _line(
          title: 'Valor diferente (gorjeta, taxa)',
          value: 'até ${matching.amountDriftPercent}% em ${matching.amountDiffersDays} dia(s), nome ${matching.minSimilarityPercent}% parecido',
        ),
        _line(title: 'Pagamento de fatura no extrato', value: 'até ${matching.invoiceWindowDays} dias do vencimento'),
        _line(title: 'Categoria das linhas novas', value: category?.name ?? 'A primeira da casa'),
        _line(title: 'Divisão das linhas novas', value: defaults.splitMode.label),
        _line(title: 'Abre a importação em', value: source?.name ?? 'Sem preferência'),
        if (!isAdmin) _emptyLine('Só administradores mudam estes padrões.'),
      ],
    );
  }

  void _showImportParamsDialog(BuildContext context, FinanceState financeState) {
    final saved = financeState.houseSettings.importMatching;
    final savedDefaults = financeState.houseSettings.importDefaults;
    final fields = <String, TextEditingController>{
      'date': TextEditingController(text: '${saved.dateWindowDays}'),
      'other': TextEditingController(text: '${saved.otherMethodWindowDays}'),
      'differs': TextEditingController(text: '${saved.amountDiffersDays}'),
      'drift': TextEditingController(text: '${saved.amountDriftPercent}'),
      'similarity': TextEditingController(text: '${saved.minSimilarityPercent}'),
      'invoice': TextEditingController(text: '${saved.invoiceWindowDays}'),
    };
    const labels = {
      'date': 'Dias de diferença aceitos (0 a 10)',
      'other': 'Dias em outra forma de pagamento (até o anterior)',
      'differs': 'Dias com valor diferente (até o primeiro)',
      'drift': 'Valor diferente aceito (% de 0 a 100)',
      'similarity': 'Nome parecido com valor diferente (% de 0 a 100)',
      'invoice': 'Pagamento de fatura até (1 a 120 dias do vencimento)',
    };
    final categories = financeState.categories;
    final sources = financeState.paymentMethods
        .where((p) => p.type == PaymentMethodType.card || p.type == PaymentMethodType.account)
        .toList();
    String? categoryId = categories.any((c) => c.id == savedDefaults.categoryId) ? savedDefaults.categoryId : null;
    String? sourceId = sources.any((p) => p.id == savedDefaults.paymentMethodId) ? savedDefaults.paymentMethodId : null;
    var splitMode = savedDefaults.splitMode;
    String? error;
    bool isSaving = false;
    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Importação de extrato', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final entry in labels.entries)
                  TextField(
                    key: ValueKey('import_matching_${entry.key}'),
                    controller: fields[entry.key],
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: entry.value),
                  ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  key: const ValueKey('import_default_category'),
                  initialValue: categoryId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Categoria das linhas novas'),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('A primeira da casa')),
                    for (final c in categories) DropdownMenuItem<String?>(value: c.id, child: Text(c.name)),
                  ],
                  onChanged: (value) => setDialogState(() => categoryId = value),
                ),
                DropdownButtonFormField<ImportSplitMode>(
                  key: const ValueKey('import_default_split'),
                  initialValue: splitMode,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Divisão das linhas novas'),
                  items: [
                    for (final mode in ImportSplitMode.values)
                      DropdownMenuItem(value: mode, child: Text(mode.label)),
                  ],
                  onChanged: (value) => setDialogState(() => splitMode = value ?? splitMode),
                ),
                DropdownButtonFormField<String?>(
                  key: const ValueKey('import_default_source'),
                  initialValue: sourceId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Abrir a importação em'),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('Sem preferência')),
                    for (final p in sources) DropdownMenuItem<String?>(value: p.id, child: Text(p.name)),
                  ],
                  onChanged: (value) => setDialogState(() => sourceId = value),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      error!,
                      key: const Key('import_params_error'),
                      style: const TextStyle(color: AppColors.debtRed, fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Cancelar')),
            FilledButton(
              onPressed: isSaving
                  ? null
                  : () async {
                      int read(String key) => int.tryParse(fields[key]!.text.trim()) ?? -1;
                      final next = ImportMatching(
                        dateWindowDays: read('date'),
                        otherMethodWindowDays: read('other'),
                        amountDiffersDays: read('differs'),
                        amountDriftPercent: read('drift'),
                        minSimilarityPercent: read('similarity'),
                        invoiceWindowDays: read('invoice'),
                      );
                      if (!next.isValid) {
                        setDialogState(() => error =
                            'Confira os valores: dias de 0 a 10 (os de outra forma de pagamento e de valor '
                            'diferente não passam dos dias aceitos), percentuais de 0 a 100 e fatura de 1 a 120 dias.');
                        return;
                      }
                      final nextDefaults = ImportDefaults(
                        categoryId: categoryId,
                        splitMode: splitMode,
                        paymentMethodId: sourceId,
                      );
                      setDialogState(() {
                        error = null;
                        isSaving = true;
                      });
                      final messenger = ScaffoldMessenger.of(context);
                      final navigator = Navigator.of(dialogCtx);
                      final ok = (next == saved && nextDefaults == savedDefaults) ||
                          await context.read<FinanceCubit>().updateHouseSettings(
                                importMatching: next == saved ? null : next,
                                importDefaults: nextDefaults == savedDefaults ? null : nextDefaults,
                              );
                      if (ok) navigator.pop();
                      setDialogState(() => isSaving = false);
                      showSaveFeedback(messenger, ok: ok, success: 'Parâmetros da importação atualizados.');
                    },
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
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
