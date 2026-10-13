import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../../../core/domain/enums/recurrence.dart';
import '../../../../core/domain/value_objects/money.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/responsive.dart';
import '../../../../core/widgets/money_input_field.dart';
import '../../../../core/di/service_locator.dart';
import '../../../auth/domain/repositories/auth_repository.dart';
import '../../../finance/domain/repositories/finance_repository.dart';
import '../../../finance/presentation/cubit/finance_cubit.dart';
import '../../domain/entities/task_item.dart';
import '../cubit/calendar_cubit.dart';

class AddTaskSheet extends StatefulWidget {
  final String activeMemberId;

  /// Tarefa existente a editar; null para criar uma nova.
  final TaskItem? taskToEdit;

  const AddTaskSheet({
    required this.activeMemberId,
    this.taskToEdit,
    super.key,
  });

  static Future<void> show(BuildContext context, String activeMemberId, {TaskItem? taskToEdit}) {
    return showAdaptiveModal(
      context: context,
      maxWidth: 520,
      child: AddTaskSheet(activeMemberId: activeMemberId, taskToEdit: taskToEdit),
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
  String? _assignedMemberId;

  final Map<String, String> _members = {};

  RecurrenceFrequency _recurrence = RecurrenceFrequency.none;

  @override
  void initState() {
    super.initState();
    _initLocalMembers();
    final edit = widget.taskToEdit;
    if (edit != null) {
      _titleController.text = edit.title;
      _descriptionController.text = edit.description ?? '';
      if (edit.cost != null) _costController.setMoney(edit.cost!);
      _dueDate = edit.dueDate;
      _priority = edit.priority;
      _assignedMemberId = edit.assignedToMemberId;
      if (edit.assignedToMemberId != null && edit.assignedToMemberName != null) {
        _members.putIfAbsent(edit.assignedToMemberId!, () => edit.assignedToMemberName!);
      }
    }
    _loadHouseMembers();
  }

  void _initLocalMembers() {
    final authRepo = sl<AuthRepository>();
    if (authRepo.isDemoMode) {
      _members['member_carlos'] = 'Carlos';
      _members['member_marina'] = 'Marina';
      _assignedMemberId = widget.activeMemberId.isNotEmpty ? widget.activeMemberId : 'member_carlos';
    } else {
      final user = authRepo.currentUser;
      if (user != null) {
        final name = user.fullName.trim();
        final myName = name.isNotEmpty ? name : 'Eu';
        _members[user.id] = myName;
        _assignedMemberId = user.id;
      } else {
        _assignedMemberId = widget.activeMemberId.isNotEmpty ? widget.activeMemberId : null;
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMembersFromFinanceCubit();
  }

  void _syncMembersFromFinanceCubit() {
    final authRepo = sl<AuthRepository>();
    if (authRepo.isDemoMode) return;

    try {
      final financeMembers = context.read<FinanceCubit>().state.members;
      if (financeMembers.isNotEmpty) {
        bool changed = false;
        for (final m in financeMembers) {
          if (m.id.isNotEmpty && (!_members.containsKey(m.id) || _members[m.id] == 'Membro')) {
            _members[m.id] = m.name;
            changed = true;
          }
        }
        if (changed && mounted) {
          setState(() {});
        }
      }
    } catch (_) {}
  }

  Future<void> _loadHouseMembers() async {
    final authRepo = sl<AuthRepository>();
    if (authRepo.isDemoMode) return;

    try {
      final houseId = authRepo.currentHouse?.id;
      final Map<String, String> membersMap = {};

      if (houseId != null) {
        try {
          final houseMembers = await authRepo.getHouseMembers(houseId);
          for (final m in houseMembers) {
            final name = m.profile?.fullName.trim();
            final displayName = (name != null && name.isNotEmpty) ? name : 'Membro';
            membersMap[m.userId] = displayName;
          }
        } catch (e) {
          debugPrint('[AddTaskSheet] Falha ao carregar membros via authRepo: $e');
        }
      }

      if (membersMap.length <= 1 && sl.isRegistered<FinanceRepository>()) {
        try {
          final finMembers = await sl<FinanceRepository>().getMembers();
          for (final m in finMembers) {
            if (m.id.isNotEmpty && m.name.isNotEmpty) {
              membersMap[m.id] = m.name;
            }
          }
        } catch (e) {
          debugPrint('[AddTaskSheet] Falha ao carregar membros via financeRepo: $e');
        }
      }

      final currentUser = authRepo.currentUser;
      if (currentUser != null && !membersMap.containsKey(currentUser.id)) {
        final name = currentUser.fullName.trim();
        membersMap[currentUser.id] = name.isNotEmpty ? name : 'Eu';
      }

      if (mounted && membersMap.isNotEmpty) {
        setState(() {
          for (final entry in membersMap.entries) {
            _members[entry.key] = entry.value;
          }
        });
      }
    } catch (e) {
      debugPrint('[AddTaskSheet] Erro ao carregar membros da casa: $e');
    }
  }

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
    final calendarCubit = context.read<CalendarCubit>();

    final edit = widget.taskToEdit;
    if (edit != null) {
      final description = _descriptionController.text.trim();
      calendarCubit.updateTask(
        TaskItem(
          id: edit.id,
          title: _titleController.text.trim(),
          description: description.isEmpty ? null : description,
          dueDate: _dueDate,
          priority: _priority,
          assignedToMemberId: _assignedMemberId,
          assignedToMemberName: _assignedMemberId != null ? _members[_assignedMemberId] : null,
          cost: cost,
          isCompleted: edit.isCompleted,
          completedAt: edit.completedAt,
          completedByMemberId: edit.completedByMemberId,
          createdByMemberId: edit.createdByMemberId,
          createdAt: edit.createdAt,
        ),
      );
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Tarefa "${_titleController.text.trim()}" atualizada!'),
          backgroundColor: AppColors.primary,
        ),
      );
      return;
    }

    final baseDueDate = _dueDate ?? now;

    // Se houver repetição, cria a primeira e as próximas ocorrências programadas
    int repeatCount = 1;
    Duration stepDuration = Duration.zero;
    if (_recurrence == RecurrenceFrequency.daily) {
      repeatCount = 7; // Próximos 7 dias
      stepDuration = const Duration(days: 1);
    } else if (_recurrence == RecurrenceFrequency.weekly) {
      repeatCount = 4; // Próximas 4 semanas
      stepDuration = const Duration(days: 7);
    } else if (_recurrence == RecurrenceFrequency.biweekly) {
      repeatCount = 3; // Próximas 3 quinzenas
      stepDuration = const Duration(days: 14);
    } else if (_recurrence == RecurrenceFrequency.monthly) {
      repeatCount = 3; // Próximos 3 meses
    }

    for (int i = 0; i < repeatCount; i++) {
      DateTime occurrenceDate;
      if (_recurrence == RecurrenceFrequency.monthly) {
        occurrenceDate = DateTime(baseDueDate.year, baseDueDate.month + i, baseDueDate.day);
      } else {
        occurrenceDate = baseDueDate.add(stepDuration * i);
      }

      final taskId = 'task_${now.millisecondsSinceEpoch}_$i';
      final taskTitle = _titleController.text.trim();

      final newTask = TaskItem(
        id: taskId,
        title: taskTitle,
        description: _descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim(),
        dueDate: occurrenceDate,
        priority: _priority,
        assignedToMemberId: _assignedMemberId,
        assignedToMemberName: _assignedMemberId != null ? _members[_assignedMemberId] : null,
        cost: cost,
        createdByMemberId: widget.activeMemberId,
        createdAt: now,
      );

      calendarCubit.addTask(newTask);
    }

    Navigator.pop(context);

    final title = _titleController.text.trim();
    final message = _recurrence != RecurrenceFrequency.none
        ? 'Tarefa "$title" criada com repetição (${_recurrence.shortLabel})!'
        : 'Tarefa "$title" adicionada com sucesso!';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
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
              Row(
                children: [
                  const Icon(Icons.checklist_rounded, color: Colors.blue, size: 28),
                  const SizedBox(width: 10),
                  Text(
                    widget.taskToEdit != null ? 'Editar Tarefa' : 'Nova Tarefa do Lar',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
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

              // Repetição / Recorrência da Tarefa (só ao criar: cada ocorrência é uma tarefa própria)
              if (widget.taskToEdit == null) ...[
              const Text(
                'Repetição da Tarefa:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Única'),
                    selected: _recurrence == RecurrenceFrequency.none,
                    onSelected: (val) {
                      if (val) setState(() => _recurrence = RecurrenceFrequency.none);
                    },
                  ),
                  ChoiceChip(
                    label: const Text('Diária'),
                    selected: _recurrence == RecurrenceFrequency.daily,
                    onSelected: (val) {
                      if (val) setState(() => _recurrence = RecurrenceFrequency.daily);
                    },
                  ),
                  ChoiceChip(
                    label: const Text('Semanal'),
                    selected: _recurrence == RecurrenceFrequency.weekly,
                    onSelected: (val) {
                      if (val) setState(() => _recurrence = RecurrenceFrequency.weekly);
                    },
                  ),
                  ChoiceChip(
                    label: const Text('Quinzenal'),
                    selected: _recurrence == RecurrenceFrequency.biweekly,
                    onSelected: (val) {
                      if (val) setState(() => _recurrence = RecurrenceFrequency.biweekly);
                    },
                  ),
                  ChoiceChip(
                    label: const Text('Mensal'),
                    selected: _recurrence == RecurrenceFrequency.monthly,
                    onSelected: (val) {
                      if (val) setState(() => _recurrence = RecurrenceFrequency.monthly);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ],

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
                  ...(() {
                    final sortedEntries = _members.entries.toList()
                      ..sort((a, b) {
                        if (a.key == widget.activeMemberId) return -1;
                        if (b.key == widget.activeMemberId) return 1;
                        return a.value.toLowerCase().compareTo(b.value.toLowerCase());
                      });

                    return sortedEntries.map((entry) {
                      final isSelected = _assignedMemberId == entry.key;
                      final memberName = entry.value;
                      final initial = memberName.isNotEmpty ? memberName[0].toUpperCase() : '?';
                      final isPrimary = entry.key == widget.activeMemberId || entry.key == 'member_carlos';

                      return ChoiceChip(
                        avatar: CircleAvatar(
                          backgroundColor: isPrimary ? AppColors.primary : AppColors.accent,
                          child: Text(initial, style: const TextStyle(color: Colors.white, fontSize: 11)),
                        ),
                        label: Text(memberName),
                        selected: isSelected,
                        onSelected: (val) {
                          setState(() => _assignedMemberId = val ? entry.key : null);
                        },
                      );
                    });
                  })(),
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
