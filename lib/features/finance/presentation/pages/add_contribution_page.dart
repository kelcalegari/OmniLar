import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/domain/value_objects/money.dart';
import '../../../../core/widgets/money_input_field.dart';
import '../../domain/entities/contribution.dart';
import '../cubit/finance_cubit.dart';
import '../cubit/finance_state.dart';
import '../../../../core/widgets/save_feedback.dart';

import 'package:intl/intl.dart';

class AddContributionPage extends StatefulWidget {
  final String? initialMemberId;
  final Money? initialAmount;
  final Contribution? editing;

  const AddContributionPage({
    super.key,
    this.initialMemberId,
    this.initialAmount,
    this.editing,
  });

  @override
  State<AddContributionPage> createState() => _AddContributionPageState();
}

class _AddContributionPageState extends State<AddContributionPage> {
  late String? _selectedMemberId = widget.initialMemberId ?? widget.editing?.memberId;
  late int _cents = widget.initialAmount?.cents ?? widget.editing?.amount.cents ?? 0;
  late DateTime _date = widget.editing?.date ?? DateTime.now();

  Future<void> _submit() async {
    if (_cents <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('O valor deve ser maior que zero')),
      );
      return;
    }

    final state = context.read<FinanceCubit>().state;
    final memberId = _selectedMemberId ?? (state.members.isNotEmpty ? state.members.first.id : '');

    final cubit = context.read<FinanceCubit>();
    final messenger = ScaffoldMessenger.of(context);

    if (widget.editing != null) {
      final updated = widget.editing!.copyWith(
        memberId: memberId,
        amount: Money(_cents),
        date: _date,
      );
      final ok = await cubit.updateContribution(updated);
      if (!mounted) return;
      if (ok) {
        Navigator.pop(context);
        showSaveFeedback(
          messenger,
          ok: true,
          success: 'Aporte atualizado com sucesso.',
          failure: '',
        );
      } else {
        showSaveFeedback(
          messenger,
          ok: false,
          success: '',
          failure: cubit.state.errorMessage,
        );
      }
      return;
    }

    final contribution = Contribution(
      id: 'contrib_${DateTime.now().millisecondsSinceEpoch}',
      memberId: memberId,
      amount: Money(_cents),
      date: _date,
    );

    final ok = await cubit.addContribution(contribution);
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context);
      showSaveFeedback(
        messenger,
        ok: true,
        success: 'Aporte registrado com sucesso.',
        failure: '',
      );
    } else {
      showSaveFeedback(
        messenger,
        ok: false,
        success: '',
        failure: cubit.state.errorMessage,
      );
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir Aporte'),
        content: Text('Deseja excluir este aporte de ${widget.editing!.amount.formatted}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.debtRed,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final cubit = context.read<FinanceCubit>();
      final messenger = ScaffoldMessenger.of(context);
      final ok = await cubit.deleteContribution(widget.editing!.id);
      if (!mounted) return;
      if (ok) {
        Navigator.pop(context);
        showSaveFeedback(
          messenger,
          ok: true,
          success: 'Aporte excluído com sucesso.',
          failure: '',
        );
      } else {
        showSaveFeedback(
          messenger,
          ok: false,
          success: '',
          failure: cubit.state.errorMessage,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return BlocBuilder<FinanceCubit, FinanceState>(
      builder: (context, state) {
        if (state.members.isNotEmpty && _selectedMemberId == null) {
          _selectedMemberId = state.members.first.id;
        }

        final isEditing = widget.editing != null;

        return Scaffold(
          appBar: AppBar(
            title: Text(isEditing ? 'Editar Aporte' : 'Novo Aporte', style: const TextStyle(fontWeight: FontWeight.bold)),
            leading: IconButton(
              icon: const Icon(Icons.close_rounded),
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              if (isEditing)
                IconButton(
                  tooltip: 'Excluir Aporte',
                  icon: const Icon(Icons.delete_outline_rounded, color: AppColors.debtRed),
                  onPressed: _confirmDelete,
                ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              MoneyInputField(
                label: 'Abastecer o Caixa da Casa',
                primaryColor: AppColors.creditGreen,
                initialValue: Money(_cents),
                quickAddCents: const [2000, 5000, 10000, 20000],
                onChanged: (val) {
                  setState(() {
                    _cents = val.cents;
                  });
                },
              ),
              const SizedBox(height: 24),

              Text('Quem está aportando?', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Row(
                children: state.members.map((m) {
                  final isSelected = m.id == _selectedMemberId;
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          backgroundColor: isSelected ? AppColors.creditGreen.withValues(alpha: 0.12) : null,
                          side: BorderSide(
                            color: isSelected ? AppColors.creditGreen : theme.dividerColor,
                            width: isSelected ? 2 : 1,
                          ),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onPressed: () {
                          setState(() {
                            _selectedMemberId = m.id;
                          });
                        },
                        child: Text(
                          m.name,
                          style: TextStyle(
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            color: isSelected ? AppColors.creditGreen : null,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),

              // Data do Aporte
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _date,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (picked != null) {
                    setState(() {
                      _date = picked;
                    });
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    border: Border.all(color: theme.dividerColor),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today_rounded, size: 18, color: AppColors.primary),
                      const SizedBox(width: 10),
                      Text('Data do aporte:', style: theme.textTheme.bodyMedium),
                      const Spacer(),
                      Text(
                        DateFormat('dd/MM/yyyy').format(_date),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),

              SizedBox(
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.creditGreen,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 2,
                  ),
                  onPressed: _submit,
                  child: Text(
                    isEditing ? 'Salvar Alterações' : 'Confirmar Aporte',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              if (isEditing) ...[
                const SizedBox(height: 12),
                SizedBox(
                  height: 48,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.debtRed,
                      side: const BorderSide(color: AppColors.debtRed),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    label: const Text(
                      'Excluir Aporte',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    onPressed: _confirmDelete,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
