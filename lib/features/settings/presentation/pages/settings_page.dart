import '../../../../core/domain/value_objects/cycle_schedule.dart';
import 'package:flutter/material.dart';
import '../../../finance/domain/entities/category_default_split.dart';
import '../../../finance/domain/entities/closing_defaults.dart';
import '../../../finance/domain/entities/split_rule.dart';
import '../../../finance/domain/entities/house_settings.dart';
import '../../../finance/domain/entities/member_settings.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/di/service_locator.dart';
import '../../../admin/domain/entities/account_access.dart';
import '../../../admin/presentation/cubit/account_access_cubit.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/clipboard_helper.dart';
import '../../../../core/utils/responsive.dart';
import '../../../../core/widgets/responsive_container.dart';
import '../../../auth/domain/repositories/auth_repository.dart';
import '../../../auth/domain/entities/user_profile.dart';
import '../../../auth/domain/entities/house.dart';
import '../../../auth/presentation/cubit/auth_cubit.dart';
import '../../../auth/presentation/cubit/auth_state.dart';
import '../../../finance/presentation/cubit/finance_cubit.dart';
import '../../../finance/domain/entities/category.dart';
import '../../../finance/domain/entities/house_member.dart';
import '../../../finance/domain/repositories/finance_repository.dart';
import '../../../finance/presentation/widgets/card_invoice_payment_sheet.dart';
import '../../../settlement/domain/entities/settlement_options.dart';
import '../../../settlement/domain/entities/settlement_summary.dart';
import '../../../settlement/domain/entities/transfer_settlement_resolution.dart';
import '../../../settlement/domain/repositories/settlement_repository.dart';
import '../../../finance/domain/entities/payment_method.dart';
import '../../../finance/presentation/cubit/finance_state.dart';
import '../../../finance/presentation/pages/add_expense_page.dart';
import '../../../finance/presentation/widgets/audit_log_sheet.dart';
import '../../../notifications/presentation/widgets/push_settings_block.dart';
import '../../../notifications/presentation/widgets/notification_preferences_block.dart';
import '../../../../core/domain/value_objects/money.dart';
import '../../../../core/widgets/recurrence_scope_dialog.dart';
import '../../../../core/theme/theme_cubit.dart';
import '../../../../core/widgets/theme_toggle_button.dart';
import '../widgets/ai_key_config_sheet.dart';
import '../widgets/account_security_panel.dart';
import '../../../../core/widgets/money_input_field.dart';
import '../../../../core/widgets/save_feedback.dart';
import '../../../../core/widgets/search_shortcut.dart';
import '../widgets/ai_consent_tile.dart';

part 'settings_groups.dart';

/// Mantém o mesmo widget de editor entre reconstruções da página. O editor do
/// modelo de rateio guarda o que está sendo editado em variáveis do método que
/// o cria; recriá-lo a cada reconstrução apagaria a edição. Trocar a [key]
/// (quando os dados da casa mudam) é o que o recria com os valores novos.
class _KeptEditor extends StatefulWidget {
  final Widget Function(BuildContext context) create;

  const _KeptEditor({super.key, required this.create});

  @override
  State<_KeptEditor> createState() => _KeptEditorState();
}

class _KeptEditorState extends State<_KeptEditor> {
  Widget? _editor;

  @override
  Widget build(BuildContext context) => _editor ??= widget.create(context);
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  /// Grupo aberto na coluna da direita (só no PC).
  _SettingsGroup _selectedGroup = _SettingsGroup.house;

  /// Muda a cada "Atualizar" para o histórico de auditoria ser relido.
  int _auditVersion = 0;

  void _reloadAudit() => setState(() => _auditVersion++);

  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    SearchShortcut.register(_searchFocus);
  }

  @override
  void dispose() {
    SearchShortcut.unregister(_searchFocus);
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() => _searchQuery = '');
  }

  Widget _searchField() {
    return TextField(
      controller: _searchController,
      focusNode: _searchFocus,
      onChanged: (value) => setState(() => _searchQuery = value),
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'Buscar nos ajustes',
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: _searchQuery.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close_rounded),
                tooltip: 'Limpar busca',
                onPressed: _clearSearch,
              ),
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  /// Resultado escolhido: abre o grupo dele e, quando há, a edição do item
  /// por cima (fechando a edição, fica-se no grupo). Limpa a busca.
  void _pickSearchEntry(_SearchEntry entry, ValueChanged<_SettingsGroup> openGroup) {
    _clearSearch();
    FocusManager.instance.primaryFocus?.unfocus();
    final group = entry.group;
    if (group != null) openGroup(group);
    entry.action?.call();
  }

  void _showEditProfileModal(BuildContext context, UserProfile? user) {
    if (user == null) return;
    final nameController = TextEditingController(text: user.fullName);
    final pixKeyController = TextEditingController(text: user.pixKey ?? '');
    final formKey = GlobalKey<FormState>();
    bool isSaving = false;

    showAdaptiveModal(
      context: context,
      maxWidth: 500,
      child: StatefulBuilder(
        builder: (context, setModalState) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.manage_accounts_rounded,
                              color: AppColors.primary,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'Editar Perfil da Conta',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Atualize seu nome de exibição e a Chave Pix para transferências e Super Pix. E-mail e senha ficam em Conta e segurança.',
                        style: TextStyle(color: Colors.grey, fontSize: 13),
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: nameController,
                        decoration: InputDecoration(
                          labelText: 'Nome Completo',
                          prefixIcon: const Icon(Icons.person_outline_rounded),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Informe seu nome completo';
                          }
                          if (value.trim().length < 2) {
                            return 'O nome deve ter pelo menos 2 caracteres';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: pixKeyController,
                        decoration: InputDecoration(
                          labelText: 'Chave Pix (para receber acertos e Super Pix)',
                          hintText: 'Ex: CPF, e-mail, celular ou chave aleatória',
                          prefixIcon: const Icon(
                            Icons.pix_rounded,
                            color: AppColors.creditGreen,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: isSaving
                                  ? null
                                  : () => Navigator.pop(context),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Text('Cancelar'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton(
                              onPressed: isSaving
                                  ? null
                                  : () async {
                                      if (!formKey.currentState!.validate())
                                        return;
                                      setModalState(() => isSaving = true);

                                      final newName = nameController.text
                                          .trim();
                                      final newPixKey = pixKeyController.text
                                          .trim();
                                      final messenger = ScaffoldMessenger.of(
                                        context,
                                      );
                                      final navigator = Navigator.of(context);

                                      try {
                                        await context
                                            .read<AuthCubit>()
                                            .updateProfile(
                                              fullName: newName,
                                              pixKey: newPixKey,
                                            );
                                        navigator.pop();
                                        messenger.showSnackBar(
                                          SnackBar(
                                            content: const Text(
                                              'Perfil atualizado com sucesso! ✨',
                                            ),
                                            backgroundColor: AppColors.primary,
                                          ),
                                        );
                                      } catch (e) {
                                        setModalState(() => isSaving = false);
                                        messenger.showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              'Erro ao atualizar: ${e.toString().replaceAll("AuthFailure:", "").trim()}',
                                            ),
                                            backgroundColor: AppColors.debtRed,
                                          ),
                                        );
                                      }
                                    },
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: isSaving
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text(
                                      'Salvar',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _confirmDeleteCategory(
    BuildContext context,
    FinanceCubit financeCubit,
    ExpenseCategory category,
    int totalCategories,
  ) {
    final messenger = ScaffoldMessenger.of(context);
    if (totalCategories <= 1) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Não é possível excluir a única categoria da casa. Cadastre outra antes de excluir esta.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Os lançamentos da categoria passam para outra, escolhida aqui
    final others = financeCubit.state.categories.where((c) => c.id != category.id).toList();
    if (others.isEmpty) return;
    String targetId = others.first.id;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text(
            'Excluir Categoria',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Excluir a categoria "${category.name}"? Os lançamentos dela, inclusive '
                  'os de ciclos fechados, passam para a categoria escolhida abaixo; o rateio de cada um não muda.'),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                key: const Key('delete_category_target'),
                initialValue: targetId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Mover os lançamentos para',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final c in others) DropdownMenuItem(value: c.id, child: Text(c.name)),
                ],
                onChanged: (value) {
                  if (value != null) setDialogState(() => targetId = value);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.debtRed),
              onPressed: () async {
                Navigator.pop(dialogCtx);
                final target = others.firstWhere((c) => c.id == targetId);
                final error = await financeCubit.deleteCategory(
                  category.id,
                  moveToCategoryId: targetId,
                );
                messenger.showSnackBar(
                  SnackBar(
                    backgroundColor: error == null ? null : AppColors.debtRed,
                    content: Text(error ??
                        'Categoria "${category.name}" excluída; os lançamentos foram para "${target.name}".'),
                  ),
                );
              },
              child: const Text('Excluir e mover'),
            ),
          ],
        ),
      ),
    );
  }

  void _showCategoryFormDialog(
    BuildContext context,
    FinanceCubit financeCubit,
    List<dynamic> members, {
    ExpenseCategory? existing,
  }) {
    final nameController = TextEditingController(text: existing?.name ?? '');
    // Dono que já saiu da casa não está na lista: volta para "Compartilhado"
    String? selectedOwnerId = members.any((m) => m.id == existing?.ownerMemberId)
        ? existing?.ownerMemberId
        : null;
    // Sem escolha anterior, o interruptor abre no que o nome sugere
    bool? variableSpend = existing?.isVariableSpend;
    final messenger = ScaffoldMessenger.of(context);

    // Divisão padrão da categoria (0097): sugestão ao lançar despesa dela
    final savedSplit = existing?.defaultSplit;
    var splitMode = savedSplit == null
        ? 'none'
        : (savedSplit.type == SplitType.categoryOwner ? 'single' : 'percent');
    String? splitMemberId = members.any((m) => m.id == savedSplit?.memberId) ? savedSplit?.memberId : null;
    String percentText(double value) =>
        value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toString();
    final percentControllers = {
      for (final m in members)
        m.id as String: TextEditingController(
          text: percentText(savedSplit?.percentages?[m.id] ?? (m.defaultSplitPercent as double)),
        ),
    };
    String? splitError;
    // Devolve o padrão digitado (null = sem padrão) ou marca o erro no diálogo
    CategoryDefaultSplit? readSplit(void Function(void Function()) setDialogState) {
      if (selectedOwnerId != null || splitMode == 'none') return null;
      if (splitMode == 'single') {
        return splitMemberId == null ? null : CategoryDefaultSplit.singleResponsible(splitMemberId!);
      }
      final values = <String, double>{};
      for (final entry in percentControllers.entries) {
        final value = double.tryParse(entry.value.text.trim().replaceAll(',', '.')) ?? 0;
        if (value < 0 || value > 100) {
          setDialogState(() => splitError = 'Use percentuais de 0 a 100.');
          throw const FormatException();
        }
        if (value > 0) values[entry.key] = value;
      }
      if (!CategoryDefaultSplit.percentagesClose(values.values)) {
        final total = values.values.fold<double>(0, (a, b) => a + b);
        setDialogState(() => splitError = 'Os percentuais somam ${percentText(total)}%. Precisam fechar 100%.');
        throw const FormatException();
      }
      setDialogState(() => splitError = null);
      return CategoryDefaultSplit.percentage(values);
    }

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text(
              existing == null ? 'Nova Categoria de Gastos' : 'Editar Categoria',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: nameController,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'Nome da Categoria',
                    hintText: 'Ex: Farmácia, Academia, Pet Shop',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Dono Responsável (Opcional):',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 6),
                DropdownButtonFormField<String?>(
                  initialValue: selectedOwnerId,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Compartilhado (Divisão da Casa)'),
                    ),
                    ...members.map(
                      (m) => DropdownMenuItem<String?>(
                        value: m.id as String,
                        child: Text('100% ${m.name}'),
                      ),
                    ),
                  ],
                  onChanged: (val) {
                    setDialogState(() {
                      selectedOwnerId = val;
                    });
                  },
                ),
                if (selectedOwnerId == null && members.length > 1) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'Divisão padrão (Opcional):',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey),
                  ),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    key: const Key('category_split_mode'),
                    initialValue: splitMode,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'none', child: Text('Sem padrão (divisão da casa)')),
                      DropdownMenuItem(value: 'percent', child: Text('Percentuais próprios')),
                      DropdownMenuItem(value: 'single', child: Text('Um morador responde por tudo')),
                    ],
                    onChanged: (value) => setDialogState(() {
                      splitMode = value ?? 'none';
                      splitError = null;
                    }),
                  ),
                  if (splitMode == 'percent') ...[
                    const SizedBox(height: 8),
                    for (final m in members)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: TextField(
                          key: ValueKey('category_split_percent_${m.id}'),
                          controller: percentControllers[m.id],
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(
                            labelText: m.name as String,
                            suffixText: '%',
                            isDense: true,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                  ],
                  if (splitMode == 'single')
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final m in members)
                          ChoiceChip(
                            key: ValueKey('category_split_single_${m.id}'),
                            label: Text(m.name as String),
                            selected: splitMemberId == m.id,
                            onSelected: (_) => setDialogState(() => splitMemberId = m.id as String),
                          ),
                      ],
                    ),
                  if (splitError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        splitError!,
                        key: const Key('category_split_error'),
                        style: const TextStyle(color: AppColors.debtRed, fontSize: 12),
                      ),
                    ),
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text(
                      'Ao lançar despesa desta categoria, a divisão já abre assim. Quem lança ainda pode escolher outra.',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                SwitchListTile(
                  key: const Key('category_variable_spend'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Gasto variável', style: TextStyle(fontSize: 14)),
                  subtitle: const Text(
                    'Muda de um ciclo para o outro (mercado, luz, água). O Planejamento de Aportes estima pela média.',
                    style: TextStyle(fontSize: 12),
                  ),
                  value: variableSpend ??
                      ExpenseCategory(id: existing?.id ?? '', name: nameController.text, icon: '', colorHex: '')
                          .looksLikeVariableSpend,
                  onChanged: (value) => setDialogState(() => variableSpend = value),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () async {
                  final name = nameController.text.trim();
                  if (name.isEmpty) return;
                  final CategoryDefaultSplit? defaultSplit;
                  try {
                    defaultSplit = readSplit(setDialogState);
                  } on FormatException {
                    return;
                  }

                  if (existing != null) {
                    Navigator.pop(dialogCtx);
                    final error = await financeCubit.updateCategory(
                      ExpenseCategory(
                        id: existing.id,
                        name: name,
                        icon: existing.icon,
                        colorHex: existing.colorHex,
                        ownerMemberId: selectedOwnerId,
                        isVariableSpend: variableSpend ?? existing.isVariableSpend,
                        defaultSplit: defaultSplit,
                      ),
                    );
                    messenger.showSnackBar(
                      SnackBar(
                        backgroundColor: error == null ? null : AppColors.debtRed,
                        content: Text(error ?? 'Categoria "$name" atualizada.'),
                      ),
                    );
                    return;
                  }

                  final newCat = ExpenseCategory(
                    id: 'cat_${DateTime.now().millisecondsSinceEpoch}',
                    name: name,
                    icon: 'category',
                    colorHex: '#0F766E',
                    ownerMemberId: selectedOwnerId,
                    isVariableSpend: variableSpend,
                    defaultSplit: defaultSplit,
                  );

                  Navigator.pop(dialogCtx);
                  final ok = await financeCubit.addCategory(newCat);
                  showSaveFeedback(
                    messenger,
                    ok: ok,
                    success: 'Categoria "$name" cadastrada com sucesso! 🎉',
                    failure: financeCubit.state.errorMessage,
                  );
                },
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                ),
                child: const Text('Salvar'),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Editor do modelo de rateio, mostrado dentro do grupo "Divisão das despesas".
  /// Os valores em edição vivem nas variáveis abaixo: o widget devolvido precisa
  /// ser criado uma vez e guardado (ver [_KeptEditor]).
  Widget _splitModelsEditor(BuildContext context) {
    final financeCubit = context.read<FinanceCubit>();
    final members = financeCubit.state.members;
    final authRepo = sl<AuthRepository>();
    final isDemo = authRepo.isDemoMode;
    final currentUser = authRepo.currentUser;

    final name1 = isDemo
        ? 'Carlos'
        : (members.isNotEmpty
              ? members[0].name.split(' ').first
              : (currentUser?.fullName.isNotEmpty == true
                    ? currentUser!.fullName.split(' ').first
                    : 'Você'));
    final name2 = isDemo
        ? 'Marina'
        : (members.length > 1
              ? members[1].name.split(' ').first
              : 'Parceiro(a)');

    // O banco só aceita o rateio de dono ou admin. Sem identificar o morador
    // (modo demo), nada é bloqueado.
    final myRole = members.where((m) => m.id == currentUser?.id).firstOrNull?.role;
    final canEditSplit = isDemo || myRole == null || myRole == 'owner' || myRole == 'admin';

    // Modelo ativo: aportes fixos pelos valores dos membros; senão, o gravado na casa
    final hasFixedActive = members.any((m) => (m.defaultFixedAmountCents ?? 0) > 0);
    final categories = financeCubit.state.categories;
    String selectedModel = hasFixedActive
        ? 'fixed'
        : (financeCubit.state.splitModel == 'category' ? 'category' : 'percentage');

    // Morador sozinho na casa fica com 100%: não há o que dividir
    final isSingleMember = !isDemo && members.length == 1;

    double percent1 = isSingleMember
        ? 100.0
        : (members.isNotEmpty ? members[0].defaultSplitPercent : 50.0);
    double percent2 = isSingleMember
        ? 0.0
        : (members.length > 1
              ? members[1].defaultSplitPercent
              : (100.0 - percent1));

    // Com 3 ou mais moradores cada um tem o seu percentual (inteiros que somam 100)
    final isMultiMember = members.length > 2;
    final percentByMember = <String, int>{
      for (final m in members) m.id: m.defaultSplitPercent.round(),
    };
    String firstName(HouseMember m) => m.name.split(' ').first;
    int percentTotal() => percentByMember.values.fold<int>(0, (a, b) => a + b);
    void splitEqually() {
      final base = 100 ~/ members.length;
      final remainder = 100 % members.length;
      for (int i = 0; i < members.length; i++) {
        percentByMember[members[i].id] = base + (i < remainder ? 1 : 0);
      }
    }

    // O arredondamento de 23,33 / 43,34 / 33,33 daria 99: a maior fatia absorve a diferença
    if (isMultiMember && (percentTotal() - 100).abs() <= members.length) {
      final largest = members.reduce(
        (a, b) => percentByMember[b.id]! > percentByMember[a.id]! ? b : a,
      );
      percentByMember[largest.id] = percentByMember[largest.id]! + (100 - percentTotal());
    }

    // Aportes fixos por membro (ex: Balde Comum)
    final fixedAmountsByMember = <String, int>{};
    for (int i = 0; i < members.length; i++) {
      final m = members[i];
      if ((m.defaultFixedAmountCents ?? 0) > 0) {
        fixedAmountsByMember[m.id] = m.defaultFixedAmountCents!;
      } else if (hasFixedActive) {
        // Casa já usa aportes fixos: quem entrou depois aparece sem aporte até alguém definir
        fixedAmountsByMember[m.id] = 0;
      } else if (i == 0) {
        fixedAmountsByMember[m.id] = 70000; // R$ 700,00 padrão
      } else if (i == 1) {
        fixedAmountsByMember[m.id] = 130000; // R$ 1.300,00 padrão
      } else {
        fixedAmountsByMember[m.id] = 100000;
      }
    }

    return StatefulBuilder(
        builder: (context, setModalState) {
          return SizedBox(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Defina como as despesas gerais da casa serão divididas entre os membros.',
                      style: TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                    const SizedBox(height: 8),

                    // 1. Porcentagem Personalizada
                    RadioListTile<String>(
                      title: const Text(
                        'Porcentagem Personalizada',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        isMultiMember
                            ? members
                                  .map((m) => '${percentByMember[m.id]}% ${firstName(m)}')
                                  .join(' / ')
                            : isSingleMember
                            ? '100% $name1'
                            : '${percent1.round()}% $name1 / ${percent2.round()}% $name2',
                      ),
                      value: 'percentage',
                      groupValue: selectedModel,
                      onChanged: (val) =>
                          setModalState(() => selectedModel = val!),
                      contentPadding: EdgeInsets.zero,
                    ),
                    if (selectedModel == 'percentage' && isMultiMember) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Column(
                          children: [
                            for (final m in members)
                              Row(
                                children: [
                                  SizedBox(
                                    width: 110,
                                    child: Text(
                                      '${firstName(m)}: ${percentByMember[m.id]}%',
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Slider(
                                      value: percentByMember[m.id]!.toDouble().clamp(0, 100),
                                      min: 0,
                                      max: 100,
                                      divisions: 100,
                                      activeColor: AppColors.primary,
                                      inactiveColor: AppColors.accent.withValues(
                                        alpha: 0.3,
                                      ),
                                      onChanged: (val) {
                                        setModalState(() {
                                          percentByMember[m.id] = val.round();
                                        });
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  percentTotal() == 100
                                      ? 'Total: 100%'
                                      : percentTotal() < 100
                                      ? 'Total: ${percentTotal()}% (faltam ${100 - percentTotal()}%)'
                                      : 'Total: ${percentTotal()}% (passou ${percentTotal() - 100}%)',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                    color: percentTotal() == 100
                                        ? AppColors.creditGreen
                                        : AppColors.debtRed,
                                  ),
                                ),
                                ActionChip(
                                  label: const Text('Dividir igualmente'),
                                  onPressed: () => setModalState(splitEqually),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ] else if (selectedModel == 'percentage' && isSingleMember) ...[
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        child: Text(
                          'Você é o único morador da casa. Os percentuais poderão ser ajustados quando outra pessoa entrar.',
                          style: TextStyle(color: Colors.grey, fontSize: 13),
                        ),
                      ),
                    ] else if (selectedModel == 'percentage') ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '$name1: ${percent1.round()}%',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                                Text(
                                  '$name2: ${percent2.round()}%',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                            Slider(
                              value: percent1.clamp(10, 90),
                              min: 10,
                              max: 90,
                              divisions: 16,
                              activeColor: AppColors.primary,
                              inactiveColor: AppColors.accent.withValues(
                                alpha: 0.3,
                              ),
                              onChanged: (val) {
                                setModalState(() {
                                  percent1 = val;
                                  percent2 = 100 - val;
                                });
                              },
                            ),
                            Wrap(
                              alignment: WrapAlignment.center,
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                ActionChip(
                                  label: const Text('50% / 50%'),
                                  onPressed: () {
                                    setModalState(() {
                                      percent1 = 50.0;
                                      percent2 = 50.0;
                                    });
                                  },
                                ),
                                ActionChip(
                                  label: const Text('60% / 40%'),
                                  onPressed: () {
                                    setModalState(() {
                                      percent1 = 60.0;
                                      percent2 = 40.0;
                                    });
                                  },
                                ),
                                ActionChip(
                                  label: const Text('70% / 30%'),
                                  onPressed: () {
                                    setModalState(() {
                                      percent1 = 70.0;
                                      percent2 = 30.0;
                                    });
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],

                    const Divider(),

                    // 2. Aportes Fixos (Balde Comum / Orçamento Base)
                    RadioListTile<String>(
                      title: const Text(
                        'Aportes Fixos (Balde Comum)',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: const Text(
                        'Cada membro aporta um valor fixo estipulado. Sobras vão pro cofre e déficit é coberto pela reserva ou rateado.',
                      ),
                      value: 'fixed',
                      groupValue: selectedModel,
                      onChanged: (val) =>
                          setModalState(() => selectedModel = val!),
                      contentPadding: EdgeInsets.zero,
                    ),
                    if (selectedModel == 'fixed') ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 8,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            ...members.map((m) {
                              final currentCents =
                                  fixedAmountsByMember[m.id] ?? 0;
                              return Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).cardColor,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.grey.withValues(alpha: 0.2),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            'Aporte de ${m.name}',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        InkWell(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          onTap: () {
                                            final controller =
                                                TextEditingController(
                                                  text: (currentCents / 100)
                                                      .toStringAsFixed(0),
                                                );
                                            showDialog(
                                              context: context,
                                              builder: (dialogCtx) => AlertDialog(
                                                title: Text(
                                                  'Aporte de ${m.name}',
                                                ),
                                                content: TextField(
                                                  controller: controller,
                                                  keyboardType:
                                                      TextInputType.number,
                                                  autofocus: true,
                                                  decoration:
                                                      const InputDecoration(
                                                        prefixText: 'R\$ ',
                                                        labelText:
                                                            'Valor mensal',
                                                        border:
                                                            OutlineInputBorder(),
                                                      ),
                                                ),
                                                actions: [
                                                  TextButton(
                                                    onPressed: () =>
                                                        Navigator.pop(
                                                          dialogCtx,
                                                        ),
                                                    child: const Text(
                                                      'Cancelar',
                                                    ),
                                                  ),
                                                  FilledButton(
                                                    onPressed: () {
                                                      final val =
                                                          double.tryParse(
                                                            controller.text
                                                                .replaceAll(
                                                                  ',',
                                                                  '.',
                                                                ),
                                                          );
                                                      if (val != null &&
                                                          val >= 0) {
                                                        setModalState(() {
                                                          fixedAmountsByMember[m
                                                              .id] = (val * 100)
                                                              .round();
                                                        });
                                                      }
                                                      Navigator.pop(dialogCtx);
                                                    },
                                                    child: const Text(
                                                      'Confirmar',
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            );
                                          },
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 5,
                                            ),
                                            decoration: BoxDecoration(
                                              color: AppColors.primary
                                                  .withValues(alpha: 0.12),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(
                                                  Money(currentCents).format(),
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    color: AppColors.primary,
                                                    fontSize: 14,
                                                  ),
                                                ),
                                                const SizedBox(width: 4),
                                                const Icon(
                                                  Icons.edit_outlined,
                                                  size: 14,
                                                  color: AppColors.primary,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (currentCents == 0) ...[
                                      const SizedBox(height: 4),
                                      const Text(
                                        'Sem aporte definido: não é cobrado no fechamento.',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: AppColors.debtRed,
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 8),
                                    SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      child: Row(
                                        children:
                                            [
                                              50000,
                                              70000,
                                              100000,
                                              130000,
                                              150000,
                                              200000,
                                            ].map((cents) {
                                              final isSelected =
                                                  currentCents == cents;
                                              return Padding(
                                                padding: const EdgeInsets.only(
                                                  right: 6,
                                                ),
                                                child: ChoiceChip(
                                                  visualDensity:
                                                      VisualDensity.compact,
                                                  label: Text(
                                                    Money(cents).format(),
                                                    style: const TextStyle(
                                                      fontSize: 11,
                                                    ),
                                                  ),
                                                  selected: isSelected,
                                                  selectedColor: AppColors
                                                      .primary
                                                      .withValues(alpha: 0.2),
                                                  onSelected: (sel) {
                                                    if (sel) {
                                                      setModalState(() {
                                                        fixedAmountsByMember[m
                                                                .id] =
                                                            cents;
                                                      });
                                                    }
                                                  },
                                                ),
                                              );
                                            }).toList(),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                            Builder(
                              builder: (ctx) {
                                final totalBalde = fixedAmountsByMember.values
                                    .fold<int>(0, (a, b) => a + b);
                                final proportions = members
                                    .map((m) {
                                      final val =
                                          fixedAmountsByMember[m.id] ?? 0;
                                      final pct = totalBalde > 0
                                          ? (val / totalBalde * 100).round()
                                          : 0;
                                      return '${m.name} ($pct%)';
                                    })
                                    .join(' • ');

                                return Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withValues(
                                      alpha: 0.08,
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: AppColors.primary.withValues(
                                        alpha: 0.25,
                                      ),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          const Expanded(
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  Icons
                                                      .account_balance_wallet_outlined,
                                                  color: AppColors.primary,
                                                  size: 18,
                                                ),
                                                SizedBox(width: 8),
                                                Flexible(
                                                  child: Text(
                                                    'Balde Mensal Previsto:',
                                                    style: TextStyle(
                                                      fontSize: 13,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            Money(totalBalde).format(),
                                            style: const TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.bold,
                                              color: AppColors.primary,
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (proportions.isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          'Proporção calculada: $proportions',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey.shade600,
                                          ),
                                        ),
                                      ],
                                      const Divider(height: 16),
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Icon(
                                            Icons.savings_outlined,
                                            color: Colors.green,
                                            size: 16,
                                          ),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              'Sobra do ciclo: Se os gastos forem menores que o balde, a sobra fica no Cofre da Casa como reserva.',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.grey.shade800,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Icon(
                                            Icons.shield_outlined,
                                            color: Colors.orange,
                                            size: 16,
                                          ),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              'Se faltar (Déficit): A Casa consome primeiro a reserva do cofre. Se o cofre não cobrir, haverá rateio do excedente.',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.grey.shade800,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 10),
                                      const Text(
                                        'Se os gastos passarem do balde, quem fechar o ciclo escolhe como cobrir o excedente.',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ],

                    const Divider(),

                    // 3. Por Categoria com Dono
                    RadioListTile<String>(
                      title: const Text(
                        'Por Categoria de Gasto',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: const Text(
                        'Despesas com dono (ex: Carro) vão 100% para ele; o resto divide igualmente.',
                      ),
                      value: 'category',
                      groupValue: selectedModel,
                      onChanged: (val) =>
                          setModalState(() => selectedModel = val!),
                      contentPadding: EdgeInsets.zero,
                    ),
                    if (selectedModel == 'category')
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Builder(
                          builder: (ctx) {
                            final owned = categories.where((c) => c.hasOwner).toList();
                            String ownerName(ExpenseCategory c) => members
                                .where((m) => m.id == c.ownerMemberId)
                                .map(firstName)
                                .firstOrNull ?? 'morador que saiu';
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (owned.isEmpty)
                                  const Text(
                                    'Nenhuma categoria tem dono ainda. Defina o dono em Ajustes > Categorias; até lá tudo é dividido igualmente.',
                                    style: TextStyle(fontSize: 12, color: AppColors.debtRed),
                                  )
                                else
                                  for (final c in owned)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 2),
                                      child: Text(
                                        '${c.name}: 100% ${ownerName(c)}',
                                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                const SizedBox(height: 4),
                                Text(
                                  members.isEmpty
                                      ? 'Demais categorias: divididas igualmente.'
                                      : 'Demais categorias: divididas igualmente entre os ${members.length} moradores.',
                                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                                ),
                              ],
                            );
                          },
                        ),
                      ),

                    const SizedBox(height: 20),
                    if (!canEditSplit) ...[
                      const Text(
                        'Só o dono ou um administrador da casa pode alterar o modelo de rateio.',
                        style: TextStyle(fontSize: 12, color: AppColors.debtRed),
                      ),
                      const SizedBox(height: 8),
                    ],
                    FilledButton(
                      onPressed:
                          (!canEditSplit ||
                              (selectedModel == 'percentage' &&
                                  isMultiMember &&
                                  percentTotal() != 100) ||
                              (selectedModel == 'fixed' &&
                                  fixedAmountsByMember.values.every((v) => v <= 0)))
                          ? null
                          : () async {
                        // Monta os percentuais e quantias nominais para persistência
                        final percentages = <String, double>{};
                        final fixedAmounts = <String, int>{};

                        if (selectedModel == 'percentage') {
                          if (isMultiMember) {
                            for (final m in members) {
                              percentages[m.id] = percentByMember[m.id]!.toDouble();
                            }
                          } else {
                            if (members.isNotEmpty) percentages[members[0].id] = percent1;
                            if (members.length > 1) percentages[members[1].id] = percent2;
                          }
                          // Reseta valores fixos quando estiver no modelo percentual
                          for (final m in members) {
                            fixedAmounts[m.id] = 0;
                          }
                        } else if (selectedModel == 'fixed') {
                          final totalBalde = fixedAmountsByMember.values.fold<int>(0, (a, b) => a + b);
                          for (final m in members) {
                            final val = fixedAmountsByMember[m.id] ?? 0;
                            fixedAmounts[m.id] = val;
                            percentages[m.id] = totalBalde > 0 ? (val / totalBalde * 100) : (100.0 / members.length);
                          }
                        } else {
                          // Modelo por categoria de gasto: mantém 50/50 como base geral
                          // Partes inteiras que somam 100 (34/33/33), como em "Dividir igualmente"
                          final base = members.isNotEmpty ? 100 ~/ members.length : 0;
                          final remainder = members.isNotEmpty ? 100 % members.length : 0;
                          for (int i = 0; i < members.length; i++) {
                            percentages[members[i].id] = (base + (i < remainder ? 1 : 0)).toDouble();
                            fixedAmounts[members[i].id] = 0;
                          }
                        }

                        // Persiste no Cubit / Banco / Mock
                        final messenger = ScaffoldMessenger.of(context);
                        final saving = financeCubit.updateHouseSplitModel(
                          splitModel: selectedModel,
                          percentages: percentages,
                          fixedAmountsCents: fixedAmounts,
                        );

                        String feedback;
                        if (selectedModel == 'percentage') {
                          feedback = isMultiMember
                              ? 'Rateio atualizado: ${members.map((m) => '${percentByMember[m.id]}% ${firstName(m)}').join(', ')}.'
                              : isSingleMember
                              ? 'Rateio atualizado: 100% $name1.'
                              : 'Rateio atualizado: ${percent1.round()}% $name1 e ${percent2.round()}% $name2.';
                        } else if (selectedModel == 'fixed') {
                          final totalBalde = fixedAmountsByMember.values
                              .fold<int>(0, (a, b) => a + b);
                          final parts = members
                              .map((m) {
                                final val = fixedAmountsByMember[m.id] ?? 0;
                                return '${m.name}: ${Money(val).format()}';
                              })
                              .join(' + ');
                          feedback =
                              'Rateio atualizado: Balde de ${Money(totalBalde).format()} ($parts). Sobras para o cofre da casa.';
                        } else {
                          feedback =
                              'Rateio atualizado para: Por Categoria de Gasto.';
                        }

                        final ok = await saving;
                        showSaveFeedback(
                          messenger,
                          ok: ok,
                          success: feedback,
                          failure: financeCubit.state.errorMessage,
                        );
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('Salvar Modelo de Rateio'),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
    );
  }

  void _confirmDeletePaymentMethod(
    BuildContext context,
    FinanceCubit financeCubit,
    PaymentMethod pm,
    int totalMethods,
  ) {
    if (totalMethods <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Não é possível excluir a única forma de pagamento da casa. Cadastre outra antes de excluir esta.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text(
          'Excluir Forma de Pagamento',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        content: Text(
          'Deseja realmente excluir "${pm.name}"?\n\n'
          'As despesas já registradas permanecerão vinculadas, mas esta forma não aparecerá mais para novos lançamentos.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.debtRed,
            ),
            onPressed: () async {
              Navigator.pop(dialogCtx);
              final ok = await financeCubit.deletePaymentMethod(pm.id);
              if (context.mounted) {
                if (!ok) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        financeCubit.state.errorMessage ??
                            'Não foi possível excluir a forma de pagamento.',
                      ),
                      backgroundColor: Colors.red.shade700,
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Forma de pagamento "${pm.name}" removida com sucesso.',
                      ),
                    ),
                  );
                }
              }
            },
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
  }

  void _showAddPaymentMethodDialog(
    BuildContext context,
    FinanceCubit financeCubit,
    List<dynamic> members,
  ) {
    _showPaymentMethodFormDialog(
      context: context,
      financeCubit: financeCubit,
      members: members,
    );
  }

  void _showPaymentMethodFormDialog({
    required BuildContext context,
    required FinanceCubit financeCubit,
    required List<dynamic> members,
    PaymentMethod? existingPm,
  }) {
    final nameController = TextEditingController(text: existingPm?.name ?? '');
    PaymentMethodType selectedType = existingPm?.type ?? PaymentMethodType.card;
    String? selectedOwnerId = existingPm?.ownerMemberId;
    int closingDay = existingPm?.closingDay ?? 25;
    int dueDay = existingPm?.dueDay ?? 5;
    final isEditing = existingPm != null;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text(
              isEditing ? 'Editar Forma de Pagamento' : 'Nova Forma de Pagamento',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: nameController,
                    autofocus: !isEditing,
                    decoration: InputDecoration(
                      labelText: 'Nome do Cartão ou Carteira',
                      hintText: sl<AuthRepository>().isDemoMode
                          ? 'Ex: Nubank Carlos, VR Alelo, Inter Marina'
                          : 'Ex: Nubank, Cartão Inter, VR Alelo',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Tipo:',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<PaymentMethodType>(
                    initialValue: selectedType,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: PaymentMethodType.card,
                        child: Text('Cartão de Crédito'),
                      ),
                      DropdownMenuItem(
                        value: PaymentMethodType.vr,
                        child: Text('Vale Refeição (VR)'),
                      ),
                      DropdownMenuItem(
                        value: PaymentMethodType.va,
                        child: Text('Vale Alimentação (VA)'),
                      ),
                      DropdownMenuItem(
                        value: PaymentMethodType.pix,
                        child: Text('Pix / Débito em Conta'),
                      ),
                      DropdownMenuItem(
                        value: PaymentMethodType.account,
                        child: Text('Conta Corrente / Caixa da Casa'),
                      ),
                      DropdownMenuItem(
                        value: PaymentMethodType.cash,
                        child: Text('Dinheiro em Espécie'),
                      ),
                      DropdownMenuItem(
                        value: PaymentMethodType.other,
                        child: Text('Outro'),
                      ),
                    ],
                    onChanged: (val) {
                      if (val != null) setDialogState(() => selectedType = val);
                    },
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Titular do Cartão:',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String?>(
                    initialValue: selectedOwnerId,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Compartilhado (Caixa da Casa)'),
                      ),
                      ...members.map(
                        (m) => DropdownMenuItem<String?>(
                          value: m.id as String,
                          child: Text(m.name as String),
                        ),
                      ),
                    ],
                    onChanged: (val) =>
                        setDialogState(() => selectedOwnerId = val),
                  ),
                  if (selectedType == PaymentMethodType.card) ...[
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Fechamento:',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey,
                                ),
                              ),
                              const SizedBox(height: 6),
                              DropdownButtonFormField<int>(
                                initialValue: closingDay,
                                decoration: InputDecoration(
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                ),
                                items: List.generate(31, (i) => i + 1)
                                    .map(
                                      (d) => DropdownMenuItem(
                                        value: d,
                                        child: Text('Dia $d'),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (val) {
                                  if (val != null)
                                    setDialogState(() => closingDay = val);
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Vencimento:',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey,
                                ),
                              ),
                              const SizedBox(height: 6),
                              DropdownButtonFormField<int>(
                                initialValue: dueDay,
                                decoration: InputDecoration(
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                ),
                                items: List.generate(31, (i) => i + 1)
                                    .map(
                                      (d) => DropdownMenuItem(
                                        value: d,
                                        child: Text('Dia $d'),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (val) {
                                  if (val != null)
                                    setDialogState(() => dueDay = val);
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () async {
                  final name = nameController.text.trim();
                  if (name.isEmpty) return;

                  if (isEditing) {
                    final updatedPm = existingPm.copyWith(
                      name: name,
                      type: selectedType,
                      ownerMemberId: selectedOwnerId,
                      clearOwner: selectedOwnerId == null,
                      closingDay: selectedType == PaymentMethodType.card
                          ? closingDay
                          : null,
                      clearClosingDay: selectedType != PaymentMethodType.card,
                      dueDay: selectedType == PaymentMethodType.card
                          ? dueDay
                          : null,
                      clearDueDay: selectedType != PaymentMethodType.card,
                    );

                    final messenger = ScaffoldMessenger.of(context);
                    Navigator.pop(dialogCtx);
                    final ok = await financeCubit.updatePaymentMethod(updatedPm);
                    showSaveFeedback(
                      messenger,
                      ok: ok,
                      success: 'Forma de pagamento "$name" atualizada com sucesso! ✨',
                      failure: financeCubit.state.errorMessage,
                    );
                  } else {
                    final newPm = PaymentMethod(
                      id: 'pm_${DateTime.now().millisecondsSinceEpoch}',
                      name: name,
                      type: selectedType,
                      ownerMemberId: selectedOwnerId,
                      closingDay: selectedType == PaymentMethodType.card
                          ? closingDay
                          : null,
                      dueDay: selectedType == PaymentMethodType.card
                          ? dueDay
                          : null,
                    );

                    final messenger = ScaffoldMessenger.of(context);
                    Navigator.pop(dialogCtx);
                    final ok = await financeCubit.addPaymentMethod(newPm);
                    showSaveFeedback(
                      messenger,
                      ok: ok,
                      success: 'Forma de pagamento "$name" cadastrada com sucesso! 🎉',
                      failure: financeCubit.state.errorMessage,
                    );
                  }
                },
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                ),
                child: Text(isEditing ? 'Salvar Alterações' : 'Salvar'),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Contas fixas da casa, mostradas dentro do grupo "Pagamentos e contas".
  Widget _recurringExpensesEditor(BuildContext context) {
    return SizedBox(
        child: BlocBuilder<FinanceCubit, FinanceState>(
          builder: (context, financeState) {
            final recurring = financeState.recurringSeries;
            final totalCents = recurring.fold(
              0,
              (sum, e) => sum + e.amount.cents,
            );

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: SizedBox(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Compromissos mensais provisionados automaticamente no Fôlego da Casa.',
                      style: TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                    const SizedBox(height: 12),

                    // Card de Resumo do Custo Mensal
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Comprometimento Mensal',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'Total Provisionado',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            Money(totalCents).format(),
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Lista de Despesas Recorrentes
                    if (recurring.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: Text(
                            'Nenhuma despesa recorrente cadastrada ainda.',
                          ),
                        ),
                      )
                    else
                      SizedBox(
                        child: ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: recurring.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final item = recurring[index];
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: Theme.of(context).cardColor,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.grey.withValues(alpha: 0.15),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    item.isVariable
                                        ? Icons.trending_up_rounded
                                        : Icons.lock_clock_rounded,
                                    color: AppColors.primary,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item.title,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                          ),
                                        ),
                                        Text(
                                          '${item.isVariable ? "Consumo Variável" : "Assinatura Fixa"} • Vence dia ${item.dueDay ?? item.dueDate?.day ?? "—"}',
                                          style: const TextStyle(
                                            color: Colors.grey,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        item.amount.format(),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      InkWell(
                                        onTap: () async {
                                          final scope =
                                              await showRecurrenceScopeDialog(
                                                context: context,
                                                itemTitle: item.title,
                                                isDelete: true,
                                                isExpense: true,
                                              );
                                          if (scope != null) {
                                            if (!context.mounted) return;
                                            final cubit = context.read<FinanceCubit>();
                                            final messenger = ScaffoldMessenger.of(context);
                                            final ok = await cubit.deleteExpense(
                                              item.id,
                                              scope: scope,
                                            );
                                            showSaveFeedback(
                                              messenger,
                                              ok: ok,
                                              success: 'Assinatura "${item.title}" excluída.',
                                              failure: cubit.state.errorMessage,
                                            );
                                          }
                                        },
                                        child: const Padding(
                                          padding: EdgeInsets.symmetric(
                                            vertical: 2,
                                            horizontal: 4,
                                          ),
                                          child: Text(
                                            'Excluir',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: AppColors.debtRed,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),

                    const SizedBox(height: 20),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.add_rounded),
                      label: const Text(
                        'Cadastrar Nova Recorrente',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      onPressed: () {
                        showAdaptiveModal(
                          context: context,
                          maxWidth: 540,
                          child: const AddExpensePage(isRecurringDefault: true),
                        );
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        ),
    );
  }

  void _showCycleDayDialog(BuildContext context, int currentDay) {
    int selectedDay = currentDay;
    bool isSaving = false;
    final house = sl<AuthRepository>().currentHouse;
    final schedule = house?.cycleSchedule ?? CycleSchedule(currentDay);
    String two(int n) => n.toString().padLeft(2, '0');
    String formatDate(DateTime d) => '${two(d.day)}/${two(d.month)}/${d.year}';

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text(
              'Dia de Início do Ciclo',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'O ciclo financeiro da casa agrupa todas as faturas e despesas de um período para calcular o acerto mensal.',
                  style: TextStyle(fontSize: 13, color: Colors.grey),
                ),
                const SizedBox(height: 16),
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      'Todo dia $selectedDay',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  initialValue: selectedDay,
                  decoration: InputDecoration(
                    labelText: 'Selecione o Dia',
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
                    if (val != null) setDialogState(() => selectedDay = val);
                  },
                ),
                const SizedBox(height: 12),
                Builder(
                  builder: (_) {
                    if (selectedDay == currentDay) {
                      return Text(
                        'Período do ciclo: dia $selectedDay ao dia ${selectedDay == 1 ? 31 : selectedDay - 1} do mês seguinte.',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.teal,
                          fontWeight: FontWeight.w500,
                        ),
                      );
                    }
                    // A troca não mexe no ciclo em andamento nem nos que já passaram
                    final now = DateTime.now();
                    final after = schedule.withChange(schedule.planChange(now, selectedDay));
                    final current = after.cycleFor(now);
                    final transition = after.next(current);
                    final regular = after.next(transition);
                    return Text(
                      'O ciclo atual não muda: termina em ${formatDate(current.endDate)}. '
                      'O seguinte vai de ${formatDate(transition.startDate)} a ${formatDate(transition.endDate)}, '
                      'e a partir de ${formatDate(regular.startDate)} os ciclos começam todo dia $selectedDay. '
                      'Os ciclos que já passaram continuam como estão.',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.teal,
                        fontWeight: FontWeight.w500,
                      ),
                    );
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: isSaving || house == null || selectedDay == currentDay
                    ? null
                    : () async {
                        setDialogState(() => isSaving = true);
                        final messenger = ScaffoldMessenger.of(context);
                        final navigator = Navigator.of(dialogCtx);
                        final authCubit = context.read<AuthCubit>();
                        final financeCubit = context.read<FinanceCubit>();
                        try {
                          await authCubit.updateHouse(
                            houseId: house.id,
                            cycleStartDay: selectedDay,
                          );
                          navigator.pop();
                          financeCubit.loadCycleData();
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text(
                                'Dia de início alterado para $selectedDay. Vale a partir do próximo ciclo. 📅',
                              ),
                            ),
                          );
                        } catch (err) {
                          setDialogState(() => isSaving = false);
                          messenger.showSnackBar(
                            SnackBar(
                              backgroundColor: AppColors.debtRed,
                              content: Text('Não foi possível alterar o dia de início do ciclo: $err'),
                            ),
                          );
                        }
                      },
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                ),
                child: const Text('Salvar'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showHousePixKeyModal(BuildContext context, House? house) {
    if (house == null) return;
    final pixKeyController = TextEditingController(text: house.pixKey ?? '');
    final holderNameController = TextEditingController(text: house.pixKeyHolderName ?? '');
    final bankController = TextEditingController(text: house.pixKeyBank ?? '');
    String selectedType = house.pixKeyType ?? 'email';
    final formKey = GlobalKey<FormState>();
    bool isSaving = false;

    showAdaptiveModal(
      context: context,
      maxWidth: 520,
      child: StatefulBuilder(
        builder: (context, setModalState) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.teal.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.pix_rounded,
                              color: Colors.teal,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'Chave Pix da Casa',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Cadastre a Chave Pix da conta conjunta ou do responsável financeiro da residência. Ela será usada automaticamente em Aportes e liquidações do Super Pix.',
                        style: TextStyle(color: Colors.grey, fontSize: 13),
                      ),
                      const SizedBox(height: 20),
                      DropdownButtonFormField<String>(
                        value: selectedType,
                        decoration: InputDecoration(
                          labelText: 'Tipo de Chave Pix',
                          prefixIcon: const Icon(Icons.category_outlined),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
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
                          if (val != null) {
                            setModalState(() => selectedType = val);
                          }
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: pixKeyController,
                        decoration: InputDecoration(
                          labelText: 'Chave Pix da Residência',
                          hintText: 'Ex: financeiro.casa@gmail.com',
                          prefixIcon: const Icon(Icons.vpn_key_outlined, color: Colors.teal),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: holderNameController,
                        decoration: InputDecoration(
                          labelText: 'Nome do Titular / Favorecido',
                          hintText: 'Ex: Caixa Nossa Casa ou Nome do Gestor',
                          prefixIcon: const Icon(Icons.person_outline_rounded),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: bankController,
                        decoration: InputDecoration(
                          labelText: 'Banco / Instituição (opcional)',
                          hintText: 'Ex: Nubank, Inter, Banco do Brasil',
                          prefixIcon: const Icon(Icons.account_balance_outlined),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: isSaving ? null : () => Navigator.pop(context),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Text('Cancelar'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton(
                              onPressed: isSaving
                                  ? null
                                  : () async {
                                      setModalState(() => isSaving = true);
                                      final newPixKey = pixKeyController.text.trim();
                                      final newHolderName = holderNameController.text.trim();
                                      final newBank = bankController.text.trim();
                                      final messenger = ScaffoldMessenger.of(context);
                                      final navigator = Navigator.of(context);

                                      try {
                                        await context.read<AuthCubit>().updateHouse(
                                          houseId: house.id,
                                          pixKey: newPixKey,
                                          pixKeyType: selectedType,
                                          pixKeyHolderName: newHolderName,
                                          pixKeyBank: newBank,
                                        );
                                        navigator.pop();
                                        messenger.showSnackBar(
                                          const SnackBar(
                                            backgroundColor: AppColors.creditGreen,
                                            content: Text('Chave Pix da Casa salva com sucesso! 🏠✨'),
                                          ),
                                        );
                                      } catch (err) {
                                        setModalState(() => isSaving = false);
                                        messenger.showSnackBar(
                                          SnackBar(
                                            backgroundColor: AppColors.debtRed,
                                            content: Text('Erro ao salvar Chave Pix da Casa: $err'),
                                          ),
                                        );
                                      }
                                    },
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.teal,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: isSaving
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text('Salvar'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _confirmSignOut(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Sair do Omni Lar?'),
        content: const Text(
          'Você precisará entrar com seu e-mail e senha novamente para acessar os dados da casa.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialogCtx);
              context.read<AuthCubit>().signOut();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.debtRed,
              foregroundColor: Colors.white,
            ),
            child: const Text('Sair da Conta'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Ajustes da Casa',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: const [ThemeToggleButton()],
      ),
      body: BlocBuilder<AuthCubit, AuthState>(
        builder: (context, authState) {
          return BlocBuilder<FinanceCubit, FinanceState>(
            builder: (context, financeState) {
              if (!context.isDesktop) {
                // Celular e tablet: índice dos grupos; cada um abre a própria página
                return SingleChildScrollView(
                  child: ResponsiveContainer(
                    child: _groupIndex(
                      context,
                      authState,
                      selected: null,
                      onSelect: (group) => _openGroupPage(context, group),
                      searchField: _searchField(),
                      searchResults: _searchResults(
                        context,
                        _searchQuery,
                        authState,
                        financeState,
                        onPick: (entry) => _pickSearchEntry(
                          entry,
                          (group) => _openGroupPage(context, group),
                        ),
                      ),
                    ),
                  ),
                );
              }

              // PC: grupos à esquerda, conteúdo do grupo escolhido à direita
              return Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1200),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 340,
                          child: SingleChildScrollView(
                            child: _groupIndex(
                              context,
                              authState,
                              selected: _selectedGroup,
                              onSelect: (group) => setState(() => _selectedGroup = group),
                              searchField: _searchField(),
                              searchResults: _searchResults(
                                context,
                                _searchQuery,
                                authState,
                                financeState,
                                onPick: (entry) => _pickSearchEntry(
                                  entry,
                                  (group) => setState(() => _selectedGroup = group),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 24),
                        Expanded(
                          child: SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(top: 8, bottom: 16, left: 4),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _selectedGroup.title,
                                        style: const TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Text(
                                        _selectedGroup.description,
                                        style: const TextStyle(color: Colors.grey, fontSize: 13),
                                      ),
                                    ],
                                  ),
                                ),
                                _groupContent(context, _selectedGroup, authState, financeState),
                                const SizedBox(height: 32),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  /// Abre a página de um grupo (celular e tablet), levando os mesmos cubits.
  void _openGroupPage(BuildContext context, _SettingsGroup group) {
    ThemeCubit? themeCubit;
    try {
      themeCubit = context.read<ThemeCubit>();
    } catch (_) {}
    final providers = [
      BlocProvider<AuthCubit>.value(value: context.read<AuthCubit>()),
      BlocProvider<FinanceCubit>.value(value: context.read<FinanceCubit>()),
      if (themeCubit != null) BlocProvider<ThemeCubit>.value(value: themeCubit),
    ];

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MultiBlocProvider(
          providers: providers,
          child: Scaffold(
            appBar: AppBar(
              title: Text(
                group.title,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            body: BlocBuilder<AuthCubit, AuthState>(
              builder: (context, authState) {
                return BlocBuilder<FinanceCubit, FinanceState>(
                  builder: (context, financeState) {
                    return SingleChildScrollView(
                      child: ResponsiveContainer(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _groupContent(context, group, authState, financeState),
                            const SizedBox(height: 32),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  /// Cartão do topo: quem está logado e em que casa. Tocar abre o perfil.
  Widget _profileCard(BuildContext context, AuthState authState) {
    final theme = Theme.of(context);
    final user = authState.user;
    final house = authState.house;
    final userName = user?.fullName ?? 'Usuário';
    final userEmail = user?.email ?? 'sem e-mail';
    final houseName = house?.name ?? 'Minha Casa';
    final cycleDay = house?.cycleStartDay ?? 5;

    return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => _showEditProfileModal(context, user),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: theme.cardColor,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.grey.withValues(alpha: 0.2),
                            ),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 26,
                                backgroundColor: AppColors.primary,
                                child: Text(
                                  userName.isNotEmpty
                                      ? userName[0].toUpperCase()
                                      : 'U',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 20,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      userName,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(
                                      userEmail,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: Colors.grey,
                                      ),
                                    ),
                                    if (user?.pixKey != null &&
                                        user!.pixKey!.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Row(
                                        children: [
                                          const Icon(
                                            Icons.pix_rounded,
                                            size: 13,
                                            color: AppColors.creditGreen,
                                          ),
                                          const SizedBox(width: 4),
                                          Expanded(
                                            child: Text(
                                              'Pix: ${user.pixKey}',
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: AppColors.creditGreen,
                                                fontWeight: FontWeight.w600,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        const Icon(
                                          Icons.home_outlined,
                                          size: 14,
                                          color: AppColors.primary,
                                        ),
                                        const SizedBox(width: 4),
                                        Flexible(
                                          child: Text(
                                            '$houseName (Ciclo dia $cycleDay)',
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: AppColors.primary,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.edit_outlined,
                                  color: AppColors.primary,
                                ),
                                tooltip: 'Editar Perfil',
                                onPressed: () =>
                                    _showEditProfileModal(context, user),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
  }

  Widget _signOutButton(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Administração do app: só para quem administra o Omni Lar (migration 0068)
        BlocBuilder<AccountAccessCubit, AccountAccessState>(
          bloc: sl<AccountAccessCubit>(),
          builder: (context, access) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (access.access != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Text(
                    access.access!.plan == AccountPlan.premium && access.access!.planExpiresAt != null
                        ? 'Seu plano: Premium até ${access.access!.planExpiresAt!.day.toString().padLeft(2, '0')}/'
                            '${access.access!.planExpiresAt!.month.toString().padLeft(2, '0')}/${access.access!.planExpiresAt!.year}'
                        : 'Seu plano: ${access.access!.plan.label}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
              if (access.isAdmin)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: FilledButton.tonalIcon(
                    onPressed: () => context.push('/admin'),
                    icon: const Icon(Icons.admin_panel_settings_rounded),
                    label: const Text('Administração do Omni Lar'),
                    style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                  ),
                ),
            ],
          ),
        ),
        _signOutOnlyButton(context),
      ],
    );
  }

  Widget _signOutOnlyButton(BuildContext context) {
    return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: OutlinedButton.icon(
                      onPressed: () => _confirmSignOut(context),
                      icon: const Icon(
                        Icons.logout_rounded,
                        color: AppColors.debtRed,
                      ),
                      label: const Text(
                        'Sair da Conta',
                        style: TextStyle(
                          color: AppColors.debtRed,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: BorderSide(
                          color: AppColors.debtRed.withValues(alpha: 0.4),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  );
  }
}
