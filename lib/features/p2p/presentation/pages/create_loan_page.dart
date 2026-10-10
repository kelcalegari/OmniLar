import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/domain/value_objects/money.dart';
import '../../../../core/widgets/money_input_field.dart';
import '../../domain/entities/p2p_loan.dart';
import '../../domain/services/p2p_calculator.dart';
import '../cubit/p2p_cubit.dart';

class CreateLoanPage extends StatefulWidget {
  const CreateLoanPage({super.key});

  @override
  State<CreateLoanPage> createState() => _CreateLoanPageState();
}

class _CreateLoanPageState extends State<CreateLoanPage> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();

  int _cents = 0;
  int _installmentsCount = 1;
  final DateTime _firstDueDate = DateTime.now().add(const Duration(days: 30));
  String _borrowerId = 'member_marina';
  final String _lenderId = 'member_carlos';

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor, informe a descrição do empréstimo')),
      );
      return;
    }

    if (_cents <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('O valor deve ser maior que zero')),
      );
      return;
    }

    final loanId = 'loan_${DateTime.now().millisecondsSinceEpoch}';
    final totalAmount = Money(_cents);

    final installments = P2PCalculator.generateInstallments(
      loanId: loanId,
      totalAmount: totalAmount,
      installmentsCount: _installmentsCount,
      firstDueDate: _firstDueDate,
    );

    final loan = P2PLoan(
      id: loanId,
      title: _titleController.text.trim(),
      description: _descriptionController.text.trim().isNotEmpty ? _descriptionController.text.trim() : null,
      totalAmount: totalAmount,
      lenderMemberId: _lenderId,
      borrowerMemberId: _borrowerId,
      installmentsCount: _installmentsCount,
      createdAt: DateTime.now(),
      firstDueDate: _firstDueDate,
      installments: installments,
    );

    context.read<P2PCubit>().createLoan(loan);
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Empréstimo registrado com sucesso! 🎉')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final installmentAmount = _cents > 0 ? Money(_cents ~/ _installmentsCount).format() : 'R\$ 0,00';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Novo Empréstimo P2P', style: TextStyle(fontWeight: FontWeight.bold)),
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
            label: 'Valor Total do Empréstimo',
            initialValue: Money(_cents),
            primaryColor: AppColors.accent,
            quickAddCents: const [5000, 10000, 20000, 50000], // +50, +100, +200, +500
            onChanged: (money) {
              setState(() {
                _cents = money.cents;
              });
            },
          ),
          const SizedBox(height: 20),

          TextField(
            controller: _titleController,
            decoration: InputDecoration(
              labelText: 'Título do Empréstimo',
              hintText: 'Ex: Camisa Zara, Celular Novo, Conserto',
              prefixIcon: const Icon(Icons.title_rounded),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 20),

          Text('Quem tomou o empréstimo? (Devedor)', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    backgroundColor: _borrowerId == 'member_marina' ? AppColors.accent.withValues(alpha: 0.12) : null,
                    side: BorderSide(
                      color: _borrowerId == 'member_marina' ? AppColors.accent : theme.dividerColor,
                      width: _borrowerId == 'member_marina' ? 2 : 1,
                    ),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: () {
                    setState(() {
                      _borrowerId = 'member_marina';
                    });
                  },
                  child: const Text('Marina', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    backgroundColor: _borrowerId == 'member_carlos' ? AppColors.accent.withValues(alpha: 0.12) : null,
                    side: BorderSide(
                      color: _borrowerId == 'member_carlos' ? AppColors.accent : theme.dividerColor,
                      width: _borrowerId == 'member_carlos' ? 2 : 1,
                    ),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: () {
                    setState(() {
                      _borrowerId = 'member_carlos';
                    });
                  },
                  child: const Text('Carlos', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          Text('Número de Parcelas', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Row(
            children: [1, 2, 3, 4, 6, 12].map((count) {
              final isSelected = _installmentsCount == count;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: ChoiceChip(
                    label: Text('${count}x'),
                    selected: isSelected,
                    selectedColor: AppColors.accent.withValues(alpha: 0.2),
                    onSelected: (selected) {
                      if (selected) {
                        setState(() {
                          _installmentsCount = count;
                        });
                      }
                    },
                  ),
                ),
              );
            }).toList(),
          ),
          if (_installmentsCount > 1) ...[
            const SizedBox(height: 8),
            Text(
              '$_installmentsCount parcelas de aprox. $installmentAmount por mês',
              style: theme.textTheme.bodySmall?.copyWith(color: AppColors.accent),
            ),
          ],
          const SizedBox(height: 32),

          SizedBox(
            height: 52,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 2,
              ),
              onPressed: _submit,
              child: const Text(
                'Confirmar Empréstimo',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
