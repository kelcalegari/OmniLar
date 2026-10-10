import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/domain/value_objects/money.dart';
import '../../domain/entities/calendar_event.dart';
import '../../domain/entities/event_participant.dart';
import '../../domain/entities/task_item.dart';
import '../cubit/calendar_cubit.dart';
import '../cubit/calendar_state.dart';
import '../widgets/add_event_sheet.dart';
import '../widgets/add_task_sheet.dart';

class CalendarPage extends StatelessWidget {
  const CalendarPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CalendarCubit, CalendarState>(
      builder: (context, state) {
        final cubit = context.read<CalendarCubit>();
        final theme = Theme.of(context);

        return Scaffold(
          appBar: AppBar(
            title: const Text('Agenda do Lar', style: TextStyle(fontWeight: FontWeight.bold)),
            actions: [
              IconButton(
                icon: Icon(
                  state.activeView == CalendarViewType.events
                      ? Icons.add_alarm_rounded
                      : Icons.add_task_rounded,
                  color: AppColors.primary,
                ),
                tooltip: state.activeView == CalendarViewType.events ? 'Novo Evento' : 'Nova Tarefa',
                onPressed: () {
                  if (state.activeView == CalendarViewType.events) {
                    AddEventSheet.show(context, state.activeMemberId);
                  } else {
                    AddTaskSheet.show(context, state.activeMemberId);
                  }
                },
              ),
              // Seletor rápido de quem está logado para testar RSVP
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: PopupMenuButton<String>(
                  initialValue: state.activeMemberId,
                  tooltip: 'Simular Membro',
                  icon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircleAvatar(
                        radius: 12,
                        backgroundColor: AppColors.primary,
                        child: Text(
                          state.activeMemberId == 'member_marina' ? 'M' : 'C',
                          style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        state.activeMemberId == 'member_marina' ? 'Marina' : 'Carlos',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                      const Icon(Icons.arrow_drop_down, size: 18),
                    ],
                  ),
                  onSelected: (val) => cubit.switchActiveMember(val),
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'member_marina',
                      child: Text('Ver como Marina'),
                    ),
                    PopupMenuItem(
                      value: 'member_carlos',
                      child: Text('Ver como Carlos'),
                    ),
                  ],
                ),
              ),
            ],
          ),
          body: Column(
            children: [
              // Seletor de visualização (Compromissos vs Tarefas)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Container(
                  decoration: BoxDecoration(
                    color: theme.cardColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _buildTabButton(
                          context,
                          label: 'Compromissos (${state.events.length})',
                          icon: Icons.calendar_today_rounded,
                          isSelected: state.activeView == CalendarViewType.events,
                          onTap: () => cubit.switchView(CalendarViewType.events),
                        ),
                      ),
                      Expanded(
                        child: _buildTabButton(
                          context,
                          label: 'Tarefas (${state.tasks.where((t) => !t.isCompleted).length})',
                          icon: Icons.checklist_rounded,
                          isSelected: state.activeView == CalendarViewType.tasks,
                          onTap: () => cubit.switchView(CalendarViewType.tasks),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Conteúdo Dinâmico
              Expanded(
                child: state.status == CalendarCubitStatus.loading && state.events.isEmpty
                    ? const Center(child: CircularProgressIndicator())
                    : state.activeView == CalendarViewType.events
                        ? _buildEventsList(context, state, cubit)
                        : _buildTasksList(context, state, cubit),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTabButton(
    BuildContext context, {
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: isSelected ? AppColors.primary : Colors.grey,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? AppColors.primary : Colors.grey,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEventsList(BuildContext context, CalendarState state, CalendarCubit cubit) {
    if (state.events.isEmpty) {
      return const Center(child: Text('Nenhum compromisso agendado'));
    }

    DateFormat dateFormat;
    try {
      dateFormat = DateFormat('EEE, d MMM - HH:mm', 'pt_BR');
    } catch (_) {
      dateFormat = DateFormat('EEE, d MMM - HH:mm');
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
      itemCount: state.events.length,
      itemBuilder: (context, index) {
        final event = state.events[index];
        final derivedStatus = event.derivedStatus;
        final myParticipant = event.participants.firstWhere(
          (p) => p.memberId == state.activeMemberId,
          orElse: () => const EventParticipant(id: '', eventId: '', memberId: '', memberName: ''),
        );

        Color statusColor;
        String statusLabel;
        IconData statusIcon;

        switch (derivedStatus) {
          case EventDerivedStatus.confirmed:
            statusColor = AppColors.creditGreen;
            statusLabel = 'Confirmado';
            statusIcon = Icons.check_circle_rounded;
            break;
          case EventDerivedStatus.atRisk:
            statusColor = AppColors.debtRed;
            statusLabel = 'Em Risco';
            statusIcon = Icons.warning_amber_rounded;
            break;
          case EventDerivedStatus.waiting:
            statusColor = Colors.orange;
            statusLabel = 'Aguardando';
            statusIcon = Icons.hourglass_top_rounded;
            break;
          case EventDerivedStatus.cancelled:
            statusColor = Colors.grey;
            statusLabel = 'Cancelado';
            statusIcon = Icons.cancel_outlined;
            break;
          case EventDerivedStatus.noEssential:
            statusColor = Colors.blue;
            statusLabel = 'Informativo';
            statusIcon = Icons.info_outline;
            break;
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Topo com Título e Status Derivado
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        event.title,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(statusIcon, size: 14, color: statusColor),
                          const SizedBox(width: 4),
                          Text(
                            statusLabel,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: statusColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),

                // Data e Horário
                Row(
                  children: [
                    Icon(Icons.access_time_rounded, size: 14, color: Colors.grey[500]),
                    const SizedBox(width: 6),
                    Text(
                      '${dateFormat.format(event.startTime)} às ${DateFormat('HH:mm').format(event.endTime)}',
                      style: TextStyle(fontSize: 13, color: Colors.grey[400]),
                    ),
                    if (event.location != null) ...[
                      const SizedBox(width: 12),
                      Icon(Icons.location_on_outlined, size: 14, color: Colors.grey[500]),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          event.location!,
                          style: TextStyle(fontSize: 13, color: Colors.grey[400]),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),

                if (event.description != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    event.description!,
                    style: TextStyle(fontSize: 13, color: Colors.grey[300]),
                  ),
                ],

                const Divider(height: 24),

                // Participantes e RSVP
                Row(
                  children: [
                    const Text(
                      'Participantes:',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: event.participants.map((p) {
                          Color rsvpColor;
                          IconData rsvpIcon;

                          switch (p.rsvpStatus) {
                            case RsvpStatus.accepted:
                              rsvpColor = AppColors.creditGreen;
                              rsvpIcon = Icons.check_circle_rounded;
                              break;
                            case RsvpStatus.declined:
                              rsvpColor = AppColors.debtRed;
                              rsvpIcon = Icons.cancel_rounded;
                              break;
                            case RsvpStatus.tentative:
                              rsvpColor = Colors.orange;
                              rsvpIcon = Icons.help_rounded;
                              break;
                            case RsvpStatus.pending:
                              rsvpColor = Colors.grey;
                              rsvpIcon = Icons.schedule_rounded;
                              break;
                          }

                          return Chip(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            avatar: Icon(rsvpIcon, size: 14, color: rsvpColor),
                            label: Text(
                              '${p.memberName} ${p.isEssential ? '(Necessário)' : ''}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: p.isEssential ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),

                // Barra de Resposta Rápida para o usuário ativo (se participante)
                if (myParticipant.id.isNotEmpty && !event.isCancelled) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const Text(
                          'Sua Presença:',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                        const Spacer(),
                        _buildRsvpActionButton(
                          label: 'Sim',
                          icon: Icons.check,
                          color: AppColors.creditGreen,
                          isSelected: myParticipant.rsvpStatus == RsvpStatus.accepted,
                          onTap: () => cubit.answerRsvp(
                            eventId: event.id,
                            status: RsvpStatus.accepted,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _buildRsvpActionButton(
                          label: 'Talvez',
                          icon: Icons.question_mark,
                          color: Colors.orange,
                          isSelected: myParticipant.rsvpStatus == RsvpStatus.tentative,
                          onTap: () => cubit.answerRsvp(
                            eventId: event.id,
                            status: RsvpStatus.tentative,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _buildRsvpActionButton(
                          label: 'Não',
                          icon: Icons.close,
                          color: AppColors.debtRed,
                          isSelected: myParticipant.rsvpStatus == RsvpStatus.declined,
                          onTap: () => cubit.answerRsvp(
                            eventId: event.id,
                            status: RsvpStatus.declined,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildRsvpActionButton({
    required String label,
    required IconData icon,
    required Color color,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? color : color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: isSelected ? Colors.white : color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: isSelected ? Colors.white : color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTasksList(BuildContext context, CalendarState state, CalendarCubit cubit) {
    if (state.tasks.isEmpty) {
      return const Center(child: Text('Nenhuma tarefa cadastrada'));
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
      itemCount: state.tasks.length,
      itemBuilder: (context, index) {
        final task = state.tasks[index];

        Color priorityColor;
        String priorityLabel;
        switch (task.priority) {
          case TaskPriority.high:
            priorityColor = AppColors.debtRed;
            priorityLabel = 'Alta';
            break;
          case TaskPriority.medium:
            priorityColor = Colors.orange;
            priorityLabel = 'Média';
            break;
          case TaskPriority.low:
            priorityColor = Colors.blue;
            priorityLabel = 'Baixa';
            break;
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: Checkbox(
              value: task.isCompleted,
              activeColor: AppColors.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
              onChanged: (_) => cubit.toggleTask(task.id),
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    task.title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      decoration: task.isCompleted ? TextDecoration.lineThrough : null,
                      color: task.isCompleted ? Colors.grey : null,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: priorityColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    priorityLabel,
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: priorityColor),
                  ),
                ),
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (task.description != null) ...[
                  const SizedBox(height: 4),
                  Text(task.description!, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ],
                const SizedBox(height: 6),
                Row(
                  children: [
                    if (task.assignedToMemberName != null) ...[
                      const Icon(Icons.person_outline, size: 14, color: Colors.grey),
                      const SizedBox(width: 4),
                      Text(
                        task.assignedToMemberName!,
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const SizedBox(width: 12),
                    ],
                    if (task.dueDate != null) ...[
                      Icon(
                        Icons.calendar_today_outlined,
                        size: 14,
                        color: task.isOverdue ? AppColors.debtRed : Colors.grey,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        DateFormat('dd/MM').format(task.dueDate!),
                        style: TextStyle(
                          fontSize: 12,
                          color: task.isOverdue ? AppColors.debtRed : Colors.grey,
                          fontWeight: task.isOverdue ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      if (task.isOverdue) ...[
                        const SizedBox(width: 4),
                        const Text(
                          '(Atrasada)',
                          style: TextStyle(fontSize: 11, color: AppColors.debtRed, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ],
                    if (task.cost != null) ...[
                      const Spacer(),
                      Text(
                        task.cost!.formatted,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primary),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
