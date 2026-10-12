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

class SavingsVaultsPage extends StatelessWidget {
  const SavingsVaultsPage({super.key});

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

  void _showNewVaultDialog(BuildContext context, FinanceCubit cubit) {
    final nameController = TextEditingController();
    int targetCents = 300000; // R$ 3.000,00 padrão
    String selectedIcon = 'savings';
    String selectedColor = '#10B981';

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Nova Caixinha da Casa', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: nameController,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: 'Nome da Meta ou Caixinha',
                      hintText: 'Ex: Férias de Fim de Ano, Geladeira Nova',
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
                onPressed: () {
                  final name = nameController.text.trim();
                  if (name.isEmpty) return;

                  final newVault = SavingsVault(
                    id: 'vault_${DateTime.now().millisecondsSinceEpoch}',
                    name: name,
                    targetAmount: Money(targetCents),
                    icon: selectedIcon,
                    colorHex: selectedColor,
                    createdAt: DateTime.now(),
                  );

                  cubit.createSavingsVault(newVault);
                  Navigator.pop(dialogCtx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Caixinha "$name" criada com sucesso! 🎯')),
                  );
                },
                style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                child: const Text('Criar Caixinha'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showDepositDialog(BuildContext context, FinanceCubit cubit, SavingsVault vault, List<dynamic> members) {
    int depositCents = 10000; // R$ 100,00 padrão
    final authRepo = sl<AuthRepository>();
    final defaultId = authRepo.isDemoMode ? 'member_carlos' : (authRepo.currentUser?.id ?? '');
    String selectedMemberId = members.isNotEmpty ? members.first.id : defaultId;
    final descController = TextEditingController(text: 'Aporte para ${vault.name}');

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
                    decoration: InputDecoration(
                      labelText: 'Descrição ou Motivo',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
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
                onPressed: () {
                  if (depositCents <= 0) return;

                  cubit.depositToVault(
                    vaultId: vault.id,
                    memberId: selectedMemberId,
                    amount: Money(depositCents),
                    description: descController.text.trim(),
                  );
                  Navigator.pop(dialogCtx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Guardado ${Money(depositCents).format()} na caixinha! 🔒')),
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

  void _showWithdrawDialog(BuildContext context, FinanceCubit cubit, SavingsVault vault, List<dynamic> members) {
    int withdrawCents = vault.currentBalance.cents > 10000 ? 10000 : vault.currentBalance.cents;
    String selectedMemberId = members.isNotEmpty ? members.first.id : 'member_carlos';
    final descController = TextEditingController(text: 'Uso de ${vault.name} para despesa');

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
                  TextField(
                    controller: descController,
                    decoration: InputDecoration(
                      labelText: 'Para qual despesa ou uso?',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
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
                onPressed: () {
                  if (withdrawCents <= 0) return;
                  if (withdrawCents > vault.currentBalance.cents) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('O valor de resgate não pode ser maior que o saldo da caixinha!')),
                    );
                    return;
                  }

                  cubit.withdrawFromVault(
                    vaultId: vault.id,
                    memberId: selectedMemberId,
                    amount: Money(withdrawCents),
                    description: descController.text.trim(),
                  );
                  Navigator.pop(dialogCtx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Resgatado ${Money(withdrawCents).format()} com sucesso! 💸')),
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
                      onPressed: () => _showNewVaultDialog(context, cubit),
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
                                      Row(
                                        children: [
                                          const Text('Meta: ', style: TextStyle(fontSize: 12, color: Colors.grey)),
                                          PrivacySensitiveText(
                                            vault.targetAmount.format(),
                                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                if (vault.isGoalReached) ...[
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
                                Text('$percent% concluído', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey)),
                              ],
                            ),
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
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}
