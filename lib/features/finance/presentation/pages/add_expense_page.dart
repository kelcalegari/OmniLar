import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/domain/value_objects/money.dart';
import '../../../../core/widgets/money_input_field.dart';
import '../../domain/entities/house_expense.dart';
import '../../domain/entities/split_rule.dart';
import '../../domain/entities/category.dart';
import '../cubit/finance_cubit.dart';
import '../cubit/finance_state.dart';

class AddExpensePage extends StatefulWidget {
  const AddExpensePage({super.key});

  @override
  State<AddExpensePage> createState() => _AddExpensePageState();
}

class _AddExpensePageState extends State<AddExpensePage> {
  final _titleController = TextEditingController();

  String? _selectedCategoryId;
  String? _selectedPaidByMemberId;
  String? _selectedPaymentMethodId;
  final SplitType _selectedSplitType = SplitType.percentage;
  final DateTime _selectedDate = DateTime.now();
  final bool _isRecurring = false;

  int _cents = 0;

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor, digite o nome da despesa')),
      );
      return;
    }

    if (_cents <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('O valor deve ser maior que zero')),
      );
      return;
    }

    final state = context.read<FinanceCubit>().state;
    final catId = _selectedCategoryId ?? (state.categories.isNotEmpty ? state.categories.first.id : '');
    final paidById = _selectedPaidByMemberId ?? (state.members.isNotEmpty ? state.members.first.id : '');
    final pmId = _selectedPaymentMethodId ?? (state.paymentMethods.isNotEmpty ? state.paymentMethods.first.id : '');

    // Determina a regra de rateio
    final category = state.categories.firstWhere((c) => c.id == catId, orElse: () => state.categories.first);
    SplitRule rule;
    if (category.hasOwner || _selectedSplitType == SplitType.categoryOwner) {
      rule = SplitRule.singleResponsible(category.ownerMemberId ?? paidById);
    } else {
      rule = const SplitRule.percentage({'member_carlos': 60.0, 'member_marina': 40.0});
    }

    final expense = HouseExpense(
      id: 'exp_${DateTime.now().millisecondsSinceEpoch}',
      title: _titleController.text.trim(),
      amount: Money(_cents),
      date: _selectedDate,
      categoryId: catId,
      paidByMemberId: paidById,
      paymentMethodId: pmId,
      splitRule: rule,
      isRecurring: _isRecurring,
    );

    context.read<FinanceCubit>().addExpense(expense);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return BlocBuilder<FinanceCubit, FinanceState>(
      builder: (context, state) {
        if (state.members.isNotEmpty && _selectedPaidByMemberId == null) {
          _selectedPaidByMemberId = state.members.first.id;
        }
        if (state.categories.isNotEmpty && _selectedCategoryId == null) {
          _selectedCategoryId = state.categories.first.id;
        }
        if (state.paymentMethods.isNotEmpty && _selectedPaymentMethodId == null) {
          _selectedPaymentMethodId = state.paymentMethods.first.id;
        }

        final selectedCategory = state.categories.firstWhere(
          (c) => c.id == _selectedCategoryId,
          orElse: () => state.categories.isNotEmpty
              ? state.categories.first
              : const ExpenseCategory(id: '', name: '', icon: '', colorHex: ''),
        );

        return Scaffold(
          appBar: AppBar(
            title: const Text('Gasto da Casa', style: TextStyle(fontWeight: FontWeight.bold)),
            leading: IconButton(
              icon: const Icon(Icons.close_rounded),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              // Campo ATM Contínuo de Valor
              MoneyInputField(
                label: 'Valor da Despesa',
                initialValue: Money(_cents),
                primaryColor: AppColors.primary,
                quickAddCents: const [1000, 2000, 5000, 10000], // +10, +20, +50, +100
                onChanged: (money) {
                  setState(() {
                    _cents = money.cents;
                  });
                },
              ),
              const SizedBox(height: 20),

              // Input de Nome / Descrição
              TextField(
                controller: _titleController,
                decoration: InputDecoration(
                  labelText: 'O que foi pago?',
                  hintText: 'Ex: Supermercado, Aluguel, Luz',
                  prefixIcon: const Icon(Icons.receipt_long_outlined),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 20),

              // Seletor de Categoria
              Text('Categoria', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: state.categories.map((cat) {
                  final isSelected = cat.id == _selectedCategoryId;
                  return ChoiceChip(
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(cat.name),
                        if (cat.hasOwner) ...[
                          const SizedBox(width: 4),
                          const Icon(Icons.person_rounded, size: 14),
                        ],
                      ],
                    ),
                    selected: isSelected,
                    selectedColor: AppColors.primary.withValues(alpha: 0.15),
                    onSelected: (selected) {
                      if (selected) {
                        setState(() {
                          _selectedCategoryId = cat.id;
                        });
                      }
                    },
                  );
                }).toList(),
              ),
              if (selectedCategory.hasOwner) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline_rounded, color: AppColors.accent, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Categoria com Responsável: Alocado 100% para o dono da categoria.',
                          style: theme.textTheme.bodySmall?.copyWith(color: AppColors.accent),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),

              // Quem Pagou
              Text('Quem Pagou?', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Row(
                children: state.members.map((m) {
                  final isSelected = m.id == _selectedPaidByMemberId;
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          backgroundColor: isSelected ? AppColors.primary.withValues(alpha: 0.12) : null,
                          side: BorderSide(
                            color: isSelected ? AppColors.primary : theme.dividerColor,
                            width: isSelected ? 2 : 1,
                          ),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onPressed: () {
                          setState(() {
                            _selectedPaidByMemberId = m.id;
                          });
                        },
                        child: Text(
                          m.name,
                          style: TextStyle(
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            color: isSelected ? AppColors.primary : null,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),

              // Forma de Pagamento
              Text('Forma de Pagamento', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _selectedPaymentMethodId,
                decoration: InputDecoration(
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  prefixIcon: const Icon(Icons.credit_card_rounded),
                ),
                items: state.paymentMethods.map((pm) {
                  return DropdownMenuItem(
                    value: pm.id,
                    child: Text(pm.name),
                  );
                }).toList(),
                onChanged: (val) {
                  setState(() {
                    _selectedPaymentMethodId = val;
                  });
                },
              ),
              const SizedBox(height: 32),

              // Botão de Lançar
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 2,
                  ),
                  onPressed: _submit,
                  child: const Text(
                    'Lançar Gasto da Casa',
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
