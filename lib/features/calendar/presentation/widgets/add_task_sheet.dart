import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../../../core/domain/value_objects/money.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/responsive.dart';
import '../../../../core/widgets/money_input_field.dart';
import '../../domain/entities/task_item.dart';
import '../cubit/calendar_cubit.dart';

class AddTaskSheet extends StatefulWidget {
  final String activeMemberId;

  const AddTaskSheet({
    required this.activeMemberId,
    super.key,
  });

  static Future<void> show(BuildContext context, String activeMemberId) {
    return showAdaptiveModal(
      context: context,
      maxWidth: 520,
      child: AddTaskSheet(activeMemberId: activeMemberId),
    );
  }

  @override
  State<AddTaskSheet> createState() => _AddTaskSheetState();
}

class _AddTaskSheetState extends State<AddTaskSheet> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _costController = MoneyTextEditingController(allowEmpty: true);

  DateTime? _dueDate = DateTime.now().add(const Duration(days: 1));
  TaskPriority _priority = TaskPriority.medium;
  String? _assignedMemberId = 'member_carlos';

  final Map<String, String> _members = {
    'member_carlos': 'Carlos',
    'member_marina': 'Marina',
  };

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _costController.dispose();
    super.dispose();
  }

  Future<void> _pickDueDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => _dueDate = picked);
    }
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    Money? cost;
    if (_costController.text.trim().isNotEmpty && _costController.cents > 0) {
      cost = _costController.money;
    }

    final now = DateTime.now();
    final taskId = 'task_${now.millisecondsSinceEpoch}';

    final newTask = TaskItem(
      id: taskId,
      title: _titleController.text.trim(),
      description: _descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim(),
      dueDate: _dueDate,
      priority: _priority,
      assignedToMemberId: _assignedMemberId,
      assignedToMemberName: _assignedMemberId != null ? _members[_assignedMemberId] : null,
      cost: cost,
      createdByMemberId: widget.activeMemberId,
      createdAt: now,
    );

    context.read<CalendarCubit>().addTask(newTask);
    Navigator.pop(context);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Tarefa "${newTask.title}" adicionada com sucesso!'),
        backgroundColor: AppColors.primary,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat("dd/MM/yyyy (EEE)", 'pt_BR');

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        top: 16,
        left: 20,
        right: 20,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
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
              const Row(
                children: [
                  Icon(Icons.checklist_rounded, color: Colors.blue, size: 28),
                  SizedBox(width: 10),
                  Text(
                    'Nova Tarefa do Lar',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Título
              TextFormField(
                controller: _titleController,
                decoration: InputDecoration(
                  labelText: 'O que precisa ser feito? *',
                  hintText: 'Ex: Trocar lâmpada da cozinha, Consertar pia',
                  prefixIcon: const Icon(Icons.check_circle_outline_rounded),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) return 'Informe o título da tarefa';
                  return null;
                },
              ),
              const SizedBox(height: 12),

              // Descrição
              TextFormField(
                controller: _descriptionController,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: 'Detalhes ou instruções (opcional)',
                  prefixIcon: const Icon(Icons.notes_rounded),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 16),

              // Data de Vencimento
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickDueDate,
                      icon: const Icon(Icons.calendar_today_rounded, size: 18),
                      label: Text(
                        _dueDate != null ? 'Vencimento: ${dateFormat.format(_dueDate!)}' : 'Sem data definida',
                      ),
                    ),
                  ),
                  if (_dueDate != null) ...[
                    IconButton(
                      icon: const Icon(Icons.clear_rounded, size: 20, color: Colors.grey),
                      tooltip: 'Remover data',
                      onPressed: () => setState(() => _dueDate = null),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 16),

              // Responsável
              const Text(
                'Responsável pela Tarefa:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ..._members.entries.map((entry) {
                    final isSelected = _assignedMemberId == entry.key;
                    return ChoiceChip(
                      avatar: CircleAvatar(
                        backgroundColor: entry.key == 'member_carlos' ? AppColors.primary : AppColors.accent,
                        child: Text(entry.value[0], style: const TextStyle(color: Colors.white, fontSize: 11)),
                      ),
                      label: Text(entry.value),
                      selected: isSelected,
                      onSelected: (val) {
                        setState(() => _assignedMemberId = val ? entry.key : null);
                      },
                    );
                  }),
                  ChoiceChip(
                    label: const Text('Qualquer um'),
                    selected: _assignedMemberId == null,
                    onSelected: (val) {
                      setState(() => _assignedMemberId = null);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Prioridade
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Prioridade:', style: TextStyle(fontWeight: FontWeight.w600)),
                  Flexible(
                    child: SegmentedButton<TaskPriority>(
                      segments: const [
                        ButtonSegment(value: TaskPriority.low, label: Text('Baixa')),
                        ButtonSegment(value: TaskPriority.medium, label: Text('Média')),
                        ButtonSegment(value: TaskPriority.high, label: Text('Alta')),
                      ],
                      selected: {_priority},
                      onSelectionChanged: (val) => setState(() => _priority = val.first),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Custo Estimado (Opcional - integração com financeiro)
              MoneyTextFormField(
                controller: _costController,
                labelText: 'Custo estimado (opcional)',
                hintText: 'Ex: R\$ 45,00',
                prefixIcon: const Icon(Icons.attach_money_rounded),
                helperText: 'Tarefas com custo podem ser lançadas como Despesa da Casa',
                allowEmpty: true,
              ),
              const SizedBox(height: 24),

              // Botão Criar Tarefa
              ElevatedButton(
                onPressed: _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text(
                  'Salvar Tarefa',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
