import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/responsive.dart';
import '../../domain/entities/calendar_event.dart';
import '../../domain/entities/event_participant.dart';
import '../cubit/calendar_cubit.dart';

class AddEventSheet extends StatefulWidget {
  final String activeMemberId;

  const AddEventSheet({
    required this.activeMemberId,
    super.key,
  });

  static Future<void> show(BuildContext context, String activeMemberId) {
    return showAdaptiveModal(
      context: context,
      maxWidth: 560,
      child: AddEventSheet(activeMemberId: activeMemberId),
    );
  }

  @override
  State<AddEventSheet> createState() => _AddEventSheetState();
}

class _AddEventSheetState extends State<AddEventSheet> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _locationController = TextEditingController();
  final _descriptionController = TextEditingController();

  DateTime _startDate = DateTime.now().add(const Duration(hours: 1));
  TimeOfDay _startTime = TimeOfDay.fromDateTime(DateTime.now().add(const Duration(hours: 1)));
  DateTime _endDate = DateTime.now().add(const Duration(hours: 2));
  TimeOfDay _endTime = TimeOfDay.fromDateTime(DateTime.now().add(const Duration(hours: 2)));
  bool _isAllDay = false;
  EventVisibility _visibility = EventVisibility.house;

  // Participantes e seus papéis selecionados
  // null = não convidado
  final Map<String, ParticipantRole?> _selectedRoles = {
    'member_carlos': ParticipantRole.required,
    'member_marina': ParticipantRole.required,
  };

  final Map<String, String> _memberNames = {
    'member_carlos': 'Carlos',
    'member_marina': 'Marina',
  };

  @override
  void dispose() {
    _titleController.dispose();
    _locationController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickDate(bool isStart) async {
    final initialDate = isStart ? _startDate : _endDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
          if (_endDate.isBefore(_startDate)) {
            _endDate = _startDate;
          }
        } else {
          _endDate = picked;
        }
      });
    }
  }

  Future<void> _pickTime(bool isStart) async {
    final initialTime = isStart ? _startTime : _endTime;
    final picked = await showTimePicker(
      context: context,
      initialTime: initialTime,
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startTime = picked;
        } else {
          _endTime = picked;
        }
      });
    }
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    final startDateTime = _isAllDay
        ? DateTime(_startDate.year, _startDate.month, _startDate.day, 0, 0)
        : DateTime(_startDate.year, _startDate.month, _startDate.day, _startTime.hour, _startTime.minute);

    final endDateTime = _isAllDay
        ? DateTime(_endDate.year, _endDate.month, _endDate.day, 23, 59)
        : DateTime(_endDate.year, _endDate.month, _endDate.day, _endTime.hour, _endTime.minute);

    final eventId = 'event_${DateTime.now().millisecondsSinceEpoch}';

    // Monta a lista de participantes
    final participants = <EventParticipant>[];
    _selectedRoles.forEach((memberId, role) {
      if (role != null) {
        final isCreator = memberId == widget.activeMemberId;
        participants.add(
          EventParticipant(
            id: 'part_${eventId}_$memberId',
            eventId: eventId,
            memberId: memberId,
            memberName: _memberNames[memberId] ?? 'Membro',
            role: role,
            // O criador já aceita automaticamente, os demais começam como pending
            rsvpStatus: isCreator ? RsvpStatus.accepted : RsvpStatus.pending,
            respondedAt: isCreator ? DateTime.now() : null,
          ),
        );
      }
    });

    final newEvent = CalendarEvent(
      id: eventId,
      title: _titleController.text.trim(),
      description: _descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim(),
      location: _locationController.text.trim().isEmpty ? null : _locationController.text.trim(),
      startTime: startDateTime,
      endTime: endDateTime,
      isAllDay: _isAllDay,
      createdByMemberId: widget.activeMemberId,
      visibility: _visibility,
      participants: participants,
    );

    context.read<CalendarCubit>().addEvent(newEvent);
    Navigator.pop(context);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Evento "${newEvent.title}" criado com sucesso!'),
        backgroundColor: AppColors.primary,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
                  Icon(Icons.event_available_rounded, color: AppColors.primary, size: 28),
                  SizedBox(width: 10),
                  Text(
                    'Novo Compromisso',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Título
              TextFormField(
                controller: _titleController,
                decoration: InputDecoration(
                  labelText: 'Título do Evento *',
                  hintText: 'Ex: Jantar de Aniversário, Consulta Médica',
                  prefixIcon: const Icon(Icons.edit_outlined),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) return 'Informe o título do compromisso';
                  return null;
                },
              ),
              const SizedBox(height: 12),

              // Local
              TextFormField(
                controller: _locationController,
                decoration: InputDecoration(
                  labelText: 'Local (opcional)',
                  hintText: 'Ex: Restaurante do Parque, Em Casa',
                  prefixIcon: const Icon(Icons.place_outlined),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 12),

              // Descrição
              TextFormField(
                controller: _descriptionController,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: 'Descrição ou notas (opcional)',
                  prefixIcon: const Icon(Icons.notes_rounded),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 16),

              // Dia Inteiro
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Dia Inteiro', style: TextStyle(fontWeight: FontWeight.w600)),
                value: _isAllDay,
                activeThumbColor: AppColors.primary,
                onChanged: (val) => setState(() => _isAllDay = val),
              ),
              const Divider(),

              // Data e Hora de Início
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: OutlinedButton.icon(
                      onPressed: () => _pickDate(true),
                      icon: const Icon(Icons.calendar_month_outlined, size: 18),
                      label: Text(dateFormat.format(_startDate)),
                    ),
                  ),
                  if (!_isAllDay) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: OutlinedButton.icon(
                        onPressed: () => _pickTime(true),
                        icon: const Icon(Icons.access_time_rounded, size: 18),
                        label: Text(_startTime.format(context)),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),

              // Data e Hora de Fim
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: OutlinedButton.icon(
                      onPressed: () => _pickDate(false),
                      icon: const Icon(Icons.calendar_month_outlined, size: 18),
                      label: Text('Até: ${dateFormat.format(_endDate)}'),
                    ),
                  ),
                  if (!_isAllDay) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: OutlinedButton.icon(
                        onPressed: () => _pickTime(false),
                        icon: const Icon(Icons.access_time_rounded, size: 18),
                        label: Text(_endTime.format(context)),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 20),

              // Participantes e Papel (RN01 e RN02)
              const Text(
                'Participantes da Casa e Papel:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 4),
              const Text(
                'Participantes "Necessários" definem o status do evento (Confirmado ou Em Risco).',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 10),

              ..._selectedRoles.keys.map((memberId) {
                final name = _memberNames[memberId] ?? memberId;
                final currentRole = _selectedRoles[memberId];

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: theme.cardColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 16,
                        backgroundColor: memberId == 'member_carlos' ? AppColors.primary : AppColors.accent,
                        child: Text(
                          name[0],
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          name,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                      ),
                      DropdownButton<ParticipantRole?>(
                        value: currentRole,
                        underline: const SizedBox(),
                        items: const [
                          DropdownMenuItem(
                            value: ParticipantRole.required,
                            child: Text('Necessário ⭐', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.primary)),
                          ),
                          DropdownMenuItem(
                            value: ParticipantRole.optional,
                            child: Text('Opcional', style: TextStyle(fontSize: 13)),
                          ),
                          DropdownMenuItem(
                            value: ParticipantRole.info,
                            child: Text('Informado', style: TextStyle(fontSize: 13)),
                          ),
                          DropdownMenuItem(
                            value: null,
                            child: Text('Não Convidar', style: TextStyle(fontSize: 13, color: Colors.grey)),
                          ),
                        ],
                        onChanged: (newRole) {
                          setState(() {
                            _selectedRoles[memberId] = newRole;
                          });
                        },
                      ),
                    ],
                  ),
                );
              }),

              const SizedBox(height: 16),

              // Visibilidade
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Visibilidade:', style: TextStyle(fontWeight: FontWeight.w600)),
                  SegmentedButton<EventVisibility>(
                    segments: const [
                      ButtonSegment(value: EventVisibility.house, label: Text('Casa')),
                      ButtonSegment(value: EventVisibility.restricted, label: Text('Restrito')),
                      ButtonSegment(value: EventVisibility.private, label: Text('Privado')),
                    ],
                    selected: {_visibility},
                    onSelectionChanged: (val) => setState(() => _visibility = val.first),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Botão Criar
              ElevatedButton(
                onPressed: _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text(
                  'Salvar Compromisso',
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
