import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/domain/value_objects/money.dart';
import '../../../../core/widgets/money_input_field.dart';
import '../../domain/entities/contribution.dart';
import '../cubit/finance_cubit.dart';
import '../cubit/finance_state.dart';

class AddContributionPage extends StatefulWidget {
  const AddContributionPage({super.key});

  @override
  State<AddContributionPage> createState() => _AddContributionPageState();
}

class _AddContributionPageState extends State<AddContributionPage> {
  String? _selectedMemberId;
  int _cents = 0;

  void _submit() {
    if (_cents <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('O valor deve ser maior que zero')),
      );
      return;
    }

    final state = context.read<FinanceCubit>().state;
    final memberId = _selectedMemberId ?? (state.members.isNotEmpty ? state.members.first.id : '');

    final contribution = Contribution(
      id: 'contrib_${DateTime.now().millisecondsSinceEpoch}',
      memberId: memberId,
      amount: Money(_cents),
      date: DateTime.now(),
    );

    context.read<FinanceCubit>().addContribution(contribution);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return BlocBuilder<FinanceCubit, FinanceState>(
      builder: (context, state) {
        if (state.members.isNotEmpty && _selectedMemberId == null) {
          _selectedMemberId = state.members.first.id;
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('Novo Aporte', style: TextStyle(fontWeight: FontWeight.bold)),
            leading: IconButton(
              icon: const Icon(Icons.close_rounded),
              onPressed: () => Navigator.pop(context),
            ),
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
                  child: const Text(
                    'Confirmar Aporte',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
