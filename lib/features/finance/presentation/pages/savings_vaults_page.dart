import '../../domain/repositories/finance_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/domain/value_objects/money.dart';
import '../../../../core/widgets/money_input_field.dart';
import '../../../../core/widgets/privacy_toggle.dart';
import '../../../../core/widgets/responsive_container.dart';
import '../../../../core/di/service_locator.dart';
import '../../../auth/domain/repositories/auth_repository.dart';
import '../../domain/entities/savings_vault.dart';
import '../cubit/finance_cubit.dart';
import '../cubit/finance_state.dart';
import '../../../../core/widgets/save_feedback.dart';
import '../widgets/third_party_receipts_card.dart';
import '../widgets/vault_history_dialog.dart';

class SavingsVaultsPage extends StatefulWidget {
  /// Caixinha cujo histórico abre ao chegar por uma notificação.
  final String? openVaultId;

  const SavingsVaultsPage({super.key, this.openVaultId});

  @override
  State<SavingsVaultsPage> createState() => _SavingsVaultsPageState();
}

class _SavingsVaultsPageState extends State<SavingsVaultsPage> {
  bool _linkHandled = false;

  static String _formatDay(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  IconData _getIconData(String iconName) {
    switch (iconName) {
      case 'shield':
        return Icons.shield_rounded;
      case 'flight':
        return Icons.flight_takeoff_rounded;
      case 'home':
        return Icons.home_rounded;
      case 'directions_car':
        return Icons.directions_car_rounded;
      default:
        return Icons.savings_rounded;
    }
  }

  Color _parseColor(String colorHex) {
    try {
      final hex = colorHex.replaceAll('#', '');
      return Color(int.parse('FF$hex', radix: 16));
    } catch (_) {
      return AppColors.primary;
    }
  }

  void _showVaultFormDialog(BuildContext context, FinanceCubit cubit, {SavingsVault? existing}) {
    final isEdit = existing != null;
    final nameController = TextEditingController(text: existing?.name ?? '');
    int targetCents = existing?.targetAmount.cents ?? 300000; // R$ 3.000,00 padrão
    String selectedIcon = existing?.icon ?? 'savings';
    String selectedColor = existing?.colorHex ?? '#10B981';
    DateTime? targetDate = existing?.targetDate;
    String? nameError;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text(isEdit ? 'Editar Caixinha' : 'Nova Caixinha da Casa', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: nameController,
                    autofocus: !isEdit,
                    onChanged: (_) {
                      if (nameError != null) setDialogState(() => nameError = null);
                    },
                    decoration: InputDecoration(
                      labelText: 'Nome da Meta ou Caixinha',
                      hintText: 'Ex: Férias de Fim de Ano, Geladeira Nova',
                      errorText: nameError,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('Meta em Dinheiro (Opcional):', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                  const SizedBox(height: 6),
                  MoneyInputField(
                    initialValue: Money(targetCents),
                    showKeypad: false,
                    onChanged: (val) {
                      setDialogState(() => targetCents = val.cents);
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: targetCents <= 0
                              ? null
                              : () async {
                                  final now = DateTime.now();
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate: targetDate ?? DateTime(now.year, now.month + 6, now.day),
                                    firstDate: DateTime(now.year, now.month, now.day),
                                    lastDate: DateTime(now.year + 30),
                                    helpText: 'Prazo da meta',
                                  );
                                  if (picked != null) setDialogState(() => targetDate = picked);
                                },
                          icon: const Icon(Icons.event_rounded, size: 16),
                          label: Text(
                            targetCents <= 0
                                ? 'Prazo: defina uma meta antes'
                                : targetDate == null
                                    ? 'Prazo da meta (opcional)'
                                    : 'Prazo: ${_formatDay(targetDate!)}',
                          ),
                        ),
                      ),
                      if (targetDate != null)
                        IconButton(
                          tooltip: 'Tirar o prazo',
                          onPressed: () => setDialogState(() => targetDate = null),
                          icon: const Icon(Icons.close_rounded, size: 18),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text('Ícone da Caixinha:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 10,
                    children: [
                      ('savings', Icons.savings_rounded, '#10B981'),
                      ('shield', Icons.shield_rounded, '#0F766E'),
                      ('flight', Icons.flight_takeoff_rounded, '#3B82F6'),
                      ('home', Icons.home_rounded, '#8B5CF6'),
                      ('directions_car', Icons.directions_car_rounded, '#EC4899'),
                    ].map((item) {
                      final isSelected = selectedIcon == item.$1;
                      return ChoiceChip(
                        avatar: Icon(item.$2, size: 16, color: isSelected ? Colors.white : Colors.grey),
                        label: Text(item.$1 == 'savings' ? 'Poupança' : item.$1 == 'shield' ? 'Reserva' : item.$1 == 'flight' ? 'Viagem' : item.$1 == 'home' ? 'Casa' : 'Carro'),
                        selected: isSelected,
                        labelStyle: TextStyle(
                          color: isSelected
                              ? Colors.white
                              : (Theme.of(dialogCtx).brightness == Brightness.dark
                                  ? Colors.white70
                                  : Colors.black87),
                        ),
                        onSelected: (sel) {
                          if (sel) {
                            setDialogState(() {
                              selectedIcon = item.$1;
                              selectedColor = item.$3;
                            });
                          }
                        },
                      );
                    }).toList(),
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
                onPressed: () async {
                  final name = nameController.text.trim();
                  if (name.isEmpty) {
                    setDialogState(() => nameError = 'Dê um nome à caixinha');
                    return;
                  }
                  // Sem meta não há prazo
                  final deadline = targetCents > 0 ? targetDate : null;

                  final messenger = ScaffoldMessenger.of(context);
                  Navigator.pop(dialogCtx);
                  final bool ok;
                  if (isEdit) {
                    ok = await cubit.updateSavingsVault(existing.copyWith(
                      name: name,
                      targetAmount: Money(targetCents < 0 ? 0 : targetCents),
                      icon: selectedIcon,
                      colorHex: selectedColor,
                      targetDate: deadline,
                      clearTargetDate: deadline == null,
                    ));
                  } else {
                    ok = await cubit.createSavingsVault(SavingsVault(
                      id: 'vault_${DateTime.now().millisecondsSinceEpoch}',
                      name: name,
                      targetAmount: Money(targetCents),
                      icon: selectedIcon,
                      colorHex: selectedColor,
                      createdAt: DateTime.now(),
                      targetDate: deadline,
                    ));
                  }
                  showSaveFeedback(
                    messenger,
                    ok: ok,
                    success: isEdit ? 'Caixinha "$name" atualizada!' : 'Caixinha "$name" criada com sucesso! 🎯',
                    failure: cubit.state.errorMessage,
                  );
                },
                style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                child: Text(isEdit ? 'Salvar' : 'Criar Caixinha'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showDepositDialog(BuildContext context, FinanceCubit cubit, SavingsVault vault, List<dynamic> members) async {
    int depositCents = 10000; // R$ 100,00 padrão
    final authRepo = sl<AuthRepository>();
    final defaultId = authRepo.isDemoMode ? 'member_carlos' : (authRepo.currentUser?.id ?? '');
    // Com sessão real o banco registra quem está logado: não há o que escolher
    String selectedMemberId =
        authRepo.isDemoMode && members.isNotEmpty ? members.first.id as String : defaultId;
    final descController = TextEditingController();
    String? reasonError;
    const quickReasons = ['Aporte mensal', 'Sobra do mês', 'Reforço da meta', 'Presente'];

    // Do Caixa do ciclo em andamento só volta o que as caixinhas devolveram a ele
    final currentCycle = cubit.cycleSchedule.cycleFor(DateTime.now());
    var availableFromCycle = const Money.zero();
    try {
      availableFromCycle = await sl<FinanceRepository>().getVaultReturnsForCycle(currentCycle);
    } catch (_) {}
    var fromCycle = false;
    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text('Guardar em: ${vault.name}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (authRepo.isDemoMode) ...[
                  const Text('Quem está guardando?', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    initialValue: selectedMemberId,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    items: members
                        .map((m) => DropdownMenuItem(value: m.id as String, child: Text(m.name as String)))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) setDialogState(() => selectedMemberId = val);
                    },
                  ),
                  const SizedBox(height: 16),
                  ],
                  if (availableFromCycle.isPositive) ...[
                    const Text('De onde vem o dinheiro?', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                    const SizedBox(height: 6),
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: false, label: Text('De fora')),
                        ButtonSegment(value: true, label: Text('Do Caixa do ciclo')),
                      ],
                      selected: {fromCycle},
                      onSelectionChanged: (s) => setDialogState(() => fromCycle = s.first),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      fromCycle
                          ? 'O valor sai do Caixa do ciclo ${currentCycle.label}. Disponível para voltar: '
                              '${availableFromCycle.format()} (o que as caixinhas devolveram ao ciclo).'
                          : 'Dinheiro novo: o Caixa do ciclo não muda.',
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                  ],
                  const Text('Valor a Guardar:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                  const SizedBox(height: 6),
                  MoneyInputField(
                    initialValue: Money(depositCents),
                    showKeypad: false,
                    quickAddCents: const [5000, 10000, 20000, 50000],
                    onChanged: (val) {
                      setDialogState(() => depositCents = val.cents);
                    },
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: descController,
                    onChanged: (_) {
                      if (reasonError != null) setDialogState(() => reasonError = null);
                    },
                    decoration: InputDecoration(
                      labelText: 'Motivo do depósito',
                      hintText: 'Ex.: sobra do mês',
                      errorText: reasonError,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final reason in quickReasons)
                        ActionChip(
                          label: Text(reason, style: const TextStyle(fontSize: 12)),
                          onPressed: () => setDialogState(() {
                            descController.text = reason;
                            reasonError = null;
                          }),
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
                onPressed: () async {
                  if (depositCents <= 0) return;
                  if (fromCycle && depositCents > availableFromCycle.cents) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Do Caixa do ciclo só podem voltar ${availableFromCycle.format()}.',
                        ),
                      ),
                    );
                    return;
                  }
                  final reason = descController.text.trim();
                  if (reason.isEmpty) {
                    setDialogState(() => reasonError = 'Informe o motivo do depósito');
                    return;
                  }

                  final messenger = ScaffoldMessenger.of(context);
                  Navigator.pop(dialogCtx);
                  final ok = await cubit.depositToVault(
                    vaultId: vault.id,
                    memberId: selectedMemberId,
                    amount: Money(depositCents),
                    description: reason,
                    fromCycleStart: fromCycle ? currentCycle.startDate : null,
                  );
                  showSaveFeedback(
                    messenger,
                    ok: ok,
                    success: fromCycle
                        ? '${Money(depositCents).format()} voltou do Caixa do ciclo para a caixinha! 🔒'
                        : 'Guardado ${Money(depositCents).format()} na caixinha! 🔒',
                    failure: cubit.state.errorMessage,
                  );
                },
                style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                child: const Text('Confirmar e Guardar'),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Extrato da caixinha: quem guardou, resgatou ou transferiu, quanto, quando e por quê.
  void _showHistoryDialog(BuildContext context, SavingsVault vault, FinanceState state) {
    VaultHistoryDialog.show(context, vault: vault, members: state.members, vaults: state.savingsVaults);
  }

  void _showTransferDialog(BuildContext context, FinanceCubit cubit, SavingsVault from, List<SavingsVault> vaults) {
    final others = vaults.where((v) => v.id != from.id).toList();
    if (others.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Crie outra caixinha para transferir o saldo.')),
      );
      return;
    }
    if (!from.currentBalance.isPositive) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Esta caixinha está vazia.')),
      );
      return;
    }
    var toId = others.first.id;
    int amountCents = from.currentBalance.cents;
    final descController = TextEditingController();
    String? reasonError;
    const quickReasons = ['Mudança de prioridade', 'Meta atingida', 'Organizar as caixinhas'];

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text('Transferir de: ${from.name}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Saldo disponível: ${from.currentBalance.format()}',
                      style: const TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue: toId,
                    decoration: InputDecoration(
                      labelText: 'Para a caixinha',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    items: [
                      for (final v in others) DropdownMenuItem(value: v.id, child: Text(v.name)),
                    ],
                    onChanged: (v) {
                      if (v != null) setDialogState(() => toId = v);
                    },
                  ),
                  const SizedBox(height: 16),
                  const Text('Valor a Transferir:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                  const SizedBox(height: 6),
                  MoneyInputField(
                    initialValue: Money(amountCents),
                    showKeypad: false,
                    onChanged: (val) => setDialogState(() => amountCents = val.cents),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: descController,
                    onChanged: (_) {
                      if (reasonError != null) setDialogState(() => reasonError = null);
                    },
                    decoration: InputDecoration(
                      labelText: 'Motivo da transferência',
                      errorText: reasonError,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final reason in quickReasons)
                        ActionChip(
                          label: Text(reason, style: const TextStyle(fontSize: 12)),
                          onPressed: () => setDialogState(() {
                            descController.text = reason;
                            reasonError = null;
                          }),
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
                onPressed: () async {
                  if (amountCents <= 0) return;
                  if (amountCents > from.currentBalance.cents) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('O valor não pode ser maior que o saldo da caixinha!')),
                    );
                    return;
                  }
                  final reason = descController.text.trim();
                  if (reason.isEmpty) {
                    setDialogState(() => reasonError = 'Informe o motivo da transferência');
                    return;
                  }
                  final toName = others.firstWhere((v) => v.id == toId).name;

                  final messenger = ScaffoldMessenger.of(context);
                  Navigator.pop(dialogCtx);
                  final ok = await cubit.transferBetweenVaults(
                    fromVaultId: from.id,
                    toVaultId: toId,
                    amount: Money(amountCents),
                    description: reason,
                  );
                  showSaveFeedback(
                    messenger,
                    ok: ok,
                    success: '${Money(amountCents).format()} transferido para $toName!',
                    failure: cubit.state.errorMessage,
                  );
                },
                style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                child: const Text('Transferir'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, FinanceCubit cubit, SavingsVault vault) async {
    if (vault.currentBalance.cents != 0) {
      await showDialog<void>(
        context: context,
        builder: (dialogCtx) => AlertDialog(
          title: const Text('Caixinha com saldo'),
          content: Text(
            '${vault.name} ainda tem ${vault.currentBalance.format()}. '
            'Resgate ou transfira o saldo para outra caixinha antes de excluir.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Entendi')),
          ],
        ),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Excluir caixinha?'),
        content: Text('${vault.name} sai da lista. Esta ação não pode ser desfeita.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx, false), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.debtRed),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final ok = await cubit.deleteSavingsVault(vault.id);
    showSaveFeedback(
      messenger,
      ok: ok,
      success: 'Caixinha "${vault.name}" excluída.',
      failure: cubit.state.errorMessage,
    );
  }

  /// Abre o histórico da caixinha do link uma vez, quando as caixinhas chegam.
  void _handleLink(BuildContext context, FinanceState state) {
    final id = widget.openVaultId;
    if (_linkHandled || id == null) return;
    if (state.status == FinanceStatus.initial || state.status == FinanceStatus.loading) return;
    _linkHandled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final vault = state.savingsVaults.where((v) => v.id == id).firstOrNull;
      if (vault == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Esta caixinha não existe mais.')),
        );
        return;
      }
      _showHistoryDialog(context, vault, state);
    });
  }

  void _showWithdrawDialog(BuildContext context, FinanceCubit cubit, SavingsVault vault, List<dynamic> members) {
    int withdrawCents = vault.currentBalance.cents > 10000 ? 10000 : vault.currentBalance.cents;
    final authRepo = sl<AuthRepository>();
    // Com sessão real o banco registra quem está logado: não há o que escolher
    String selectedMemberId = authRepo.isDemoMode
        ? (members.isNotEmpty ? members.first.id as String : 'member_carlos')
        : (authRepo.currentUser?.id ?? '');
    final descController = TextEditingController();
    // Ciclo em andamento: só ele pode receber o valor de volta no Caixa
    final currentCycle = cubit.cycleSchedule.cycleFor(DateTime.now());
    var returnToCycle = false;
    String? reasonError;
    const quickReasons = ['Emergência', 'Conserto', 'Despesa da casa', 'Reforçar o Caixa do ciclo'];

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text('Resgatar de: ${vault.name}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Saldo disponível na caixinha: ${vault.currentBalance.format()}',
                      style: const TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 14),
                  if (authRepo.isDemoMode) ...[
                  const Text('Quem está resgatando?', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    initialValue: selectedMemberId,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    items: members
                        .map((m) => DropdownMenuItem(value: m.id as String, child: Text(m.name as String)))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) setDialogState(() => selectedMemberId = val);
                    },
                  ),
                  const SizedBox(height: 16),
                  ],
                  const Text('Valor a Resgatar:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                  const SizedBox(height: 6),
                  MoneyInputField(
                    initialValue: Money(withdrawCents),
                    showKeypad: false,
                    onChanged: (val) {
                      setDialogState(() => withdrawCents = val.cents);
                    },
                  ),
                  const SizedBox(height: 16),
                  const Text('Para onde vai o dinheiro?', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                  const SizedBox(height: 6),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('Só sacar'), icon: Icon(Icons.north_east_rounded)),
                      ButtonSegment(value: true, label: Text('Devolver ao ciclo'), icon: Icon(Icons.account_balance_wallet_outlined)),
                    ],
                    selected: {returnToCycle},
                    onSelectionChanged: (s) => setDialogState(() => returnToCycle = s.first),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    returnToCycle
                        ? 'O valor entra no Caixa do ciclo ${currentCycle.label} para cobrir falta de dinheiro agora. '
                            'Não diminui o que cada morador paga no ciclo: no fechamento, o que sobrar no Caixa '
                            'pode voltar para uma caixinha.'
                        : 'O valor sai da caixinha e não entra no Caixa do ciclo.',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: descController,
                    onChanged: (_) {
                      if (reasonError != null) setDialogState(() => reasonError = null);
                    },
                    decoration: InputDecoration(
                      labelText: 'Motivo do resgate',
                      hintText: 'Ex.: conserto da geladeira',
                      errorText: reasonError,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final reason in quickReasons)
                        ActionChip(
                          label: Text(reason, style: const TextStyle(fontSize: 12)),
                          onPressed: () => setDialogState(() {
                            descController.text = reason;
                            reasonError = null;
                          }),
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
                onPressed: () async {
                  if (withdrawCents <= 0) return;
                  if (withdrawCents > vault.currentBalance.cents) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('O valor de resgate não pode ser maior que o saldo da caixinha!')),
                    );
                    return;
                  }
                  final reason = descController.text.trim();
                  if (reason.isEmpty) {
                    setDialogState(() => reasonError = 'Informe o motivo do resgate');
                    return;
                  }

                  final messenger = ScaffoldMessenger.of(context);
                  Navigator.pop(dialogCtx);
                  final ok = await cubit.withdrawFromVault(
                    vaultId: vault.id,
                    memberId: selectedMemberId,
                    amount: Money(withdrawCents),
                    description: reason,
                    returnToCycleStart: returnToCycle ? currentCycle.startDate : null,
                  );
                  showSaveFeedback(
                    messenger,
                    ok: ok,
                    success: returnToCycle
                        ? '${Money(withdrawCents).format()} devolvido ao Caixa do ciclo! 💸'
                        : 'Resgatado ${Money(withdrawCents).format()} com sucesso! 💸',
                    failure: cubit.state.errorMessage,
                  );
                },
                style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
                child: const Text('Confirmar Resgate'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Caixinhas & Metas da Casa', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: const [
          PrivacyToggleButton(),
        ],
      ),
      body: BlocBuilder<FinanceCubit, FinanceState>(
        builder: (context, state) {
          final cubit = context.read<FinanceCubit>();
          final vaults = state.savingsVaults;
          final totalSavings = state.totalSavings;
          final members = state.members;
          final today = DateTime.now();
          _handleLink(context, state);

          return ResponsiveContainer(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Card de Destaque com o Total Blindado
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [AppColors.primary, AppColors.primary.withValues(alpha: 0.85)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.25),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.shield_outlined, color: Colors.white70, size: 18),
                          SizedBox(width: 6),
                          Text(
                            'Total Guardado na Casa',
                            style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      PrivacySensitiveText(
                        totalSavings.format(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Dinheiro protegido e separado para reservas e metas. Não entra no cálculo do fôlego do mês.',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Cabeçalho da Lista e Botão Nova Caixinha
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Suas Caixinhas (${vaults.length})',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    FilledButton.icon(
                      onPressed: () => _showVaultFormDialog(context, cubit),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Nova Caixinha'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                if (vaults.isEmpty) ...[
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        children: [
                          Icon(Icons.savings_outlined, size: 48, color: Colors.grey.withValues(alpha: 0.5)),
                          const SizedBox(height: 12),
                          const Text(
                            'Nenhuma caixinha criada ainda.',
                            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Crie a primeira meta para juntar dinheiro para a casa!',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  ),
                ] else ...[
                  ...vaults.map((vault) {
                    final color = _parseColor(vault.colorHex);
                    final iconData = _getIconData(vault.icon);
                    final percent = (vault.progressPercent * 100).round();

                    return Card(
                      margin: const EdgeInsets.only(bottom: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: Colors.grey.withValues(alpha: 0.15)),
                      ),
                      elevation: 0,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                CircleAvatar(
                                  backgroundColor: color.withValues(alpha: 0.15),
                                  child: Icon(iconData, color: color, size: 22),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        vault.name,
                                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                      ),
                                      const SizedBox(height: 2),
                                      if (vault.hasGoal)
                                        Row(
                                          children: [
                                            const Text('Meta: ', style: TextStyle(fontSize: 12, color: Colors.grey)),
                                            PrivacySensitiveText(
                                              vault.targetAmount.format(),
                                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey),
                                            ),
                                            if (vault.targetDate != null)
                                              Text(
                                                ' até ${_formatDay(vault.targetDate!)}',
                                                style: const TextStyle(fontSize: 12, color: Colors.grey),
                                              ),
                                          ],
                                        )
                                      else
                                        const Text('Sem meta', style: TextStyle(fontSize: 12, color: Colors.grey)),
                                    ],
                                  ),
                                ),
                                if (vault.hasGoal && vault.isGoalReached) ...[
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.green.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Row(
                                      children: [
                                        Icon(Icons.check_circle_rounded, color: Colors.green, size: 14),
                                        SizedBox(width: 4),
                                        Text('Atingida!', style: TextStyle(color: Colors.green, fontSize: 11, fontWeight: FontWeight.bold)),
                                      ],
                                    ),
                                  ),
                                ],
                                PopupMenuButton<String>(
                                  tooltip: 'Mais ações',
                                  onSelected: (action) {
                                    switch (action) {
                                      case 'edit':
                                        _showVaultFormDialog(context, cubit, existing: vault);
                                      case 'transfer':
                                        _showTransferDialog(context, cubit, vault, vaults);
                                      case 'delete':
                                        _confirmDelete(context, cubit, vault);
                                    }
                                  },
                                  itemBuilder: (_) => const [
                                    PopupMenuItem(
                                      value: 'edit',
                                      child: ListTile(leading: Icon(Icons.edit_rounded), title: Text('Editar'), dense: true),
                                    ),
                                    PopupMenuItem(
                                      value: 'transfer',
                                      child: ListTile(leading: Icon(Icons.swap_horiz_rounded), title: Text('Transferir'), dense: true),
                                    ),
                                    PopupMenuItem(
                                      value: 'delete',
                                      child: ListTile(leading: Icon(Icons.delete_outline_rounded), title: Text('Excluir'), dense: true),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),

                            // Barra de Progresso
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: LinearProgressIndicator(
                                value: vault.progressPercent,
                                minHeight: 8,
                                backgroundColor: color.withValues(alpha: 0.15),
                                valueColor: AlwaysStoppedAnimation<Color>(color),
                              ),
                            ),
                            const SizedBox(height: 8),

                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    const Text('Saldo: ', style: TextStyle(fontSize: 13, color: Colors.grey)),
                                    PrivacySensitiveText(
                                      vault.currentBalance.format(),
                                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color),
                                    ),
                                  ],
                                ),
                                if (vault.hasGoal)
                                  Text('$percent% concluído', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey)),
                              ],
                            ),
                            if (vault.monthlyNeeded(today) case final monthly? when !vault.isGoalReached) ...[
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Icon(
                                    vault.isBehindPace(today) ? Icons.warning_amber_rounded : Icons.event_rounded,
                                    size: 14,
                                    color: vault.isBehindPace(today) ? AppColors.debtRed : Colors.grey,
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: PrivacySensitiveText(
                                      vault.isOverdue(today)
                                          ? 'Prazo vencido: faltam ${vault.remainingToGoal.format()}'
                                          : 'Guardar ${monthly.format()}/mês até ${_formatDay(vault.targetDate!)}'
                                              '${vault.isBehindPace(today) ? ' · ritmo abaixo do necessário' : ''}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: vault.isBehindPace(today) ? AppColors.debtRed : Colors.grey,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            const Divider(height: 24),

                            // Ações Guardar e Resgatar
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () => _showWithdrawDialog(context, cubit, vault, members),
                                    icon: const Icon(Icons.outbox_rounded, size: 16),
                                    label: const Text('Resgatar'),
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(vertical: 10),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: FilledButton.icon(
                                    onPressed: () => _showDepositDialog(context, cubit, vault, members),
                                    icon: const Icon(Icons.savings_rounded, size: 16),
                                    label: const Text('Guardar'),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: color,
                                      padding: const EdgeInsets.symmetric(vertical: 10),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton.icon(
                                onPressed: () => _showHistoryDialog(context, vault, state),
                                icon: const Icon(Icons.history_rounded, size: 16),
                                label: const Text('Histórico de entradas e saídas'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ],

                // Dinheiro de fora guardado para pagar faturas
                const SizedBox(height: 8),
                ThirdPartyReceiptsCard(state: state, cubit: cubit),
              ],
            ),
          );
        },
      ),
    );
  }
}
