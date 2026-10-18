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
    ];
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
      _planningPanel(context, financeState),
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
