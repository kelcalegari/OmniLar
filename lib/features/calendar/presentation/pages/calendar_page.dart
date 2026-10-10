import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/responsive.dart';
import '../../../../core/widgets/responsive_container.dart';
import '../../domain/entities/calendar_event.dart';
import '../../domain/entities/event_participant.dart';
import '../cubit/calendar_cubit.dart';
import '../cubit/calendar_state.dart';
import '../widgets/add_event_sheet.dart';
import '../widgets/mini_calendar_card.dart';

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  DateTime _selectedDate = DateTime.now();
  bool _isAgendaMode = true; // true = Visão Agenda (Calendário com Dots + Timeline do Dia), false = Visão Lista Corrida

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  void _previousDay() {
    setState(() {
      _selectedDate = _selectedDate.subtract(const Duration(days: 1));
    });
  }

  void _nextDay() {
    setState(() {
      _selectedDate = _selectedDate.add(const Duration(days: 1));
    });
  }

  void _goToToday() {
    setState(() {
      _selectedDate = DateTime.now();
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CalendarCubit, CalendarState>(
      builder: (context, state) {
        final cubit = context.read<CalendarCubit>();
        final theme = Theme.of(context);
        final isDesktop = context.isDesktop;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Agenda do Lar', style: TextStyle(fontWeight: FontWeight.bold)),
            actions: [
              // Alternador rápido na AppBar
              IconButton(
                icon: Icon(
                  _isAgendaMode ? Icons.format_list_bulleted_rounded : Icons.calendar_month_rounded,
                  color: AppColors.primary,
                ),
                tooltip: _isAgendaMode ? 'Alternar para Visão Lista' : 'Alternar para Visão Agenda',
                onPressed: () {
                  setState(() {
                    _isAgendaMode = !_isAgendaMode;
                  });
                },
              ),
              // Adicionar Novo Evento
              IconButton(
                icon: const Icon(Icons.add_alarm_rounded, color: AppColors.primary),
                tooltip: 'Novo Compromisso',
                onPressed: () => AddEventSheet.show(context, state.activeMemberId),
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
          body: state.status == CalendarCubitStatus.loading && state.events.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    // Seletor de Modo Universal (Agenda vs Lista)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: ResponsiveContainer(
                        maxWidth: kMaxContentWidth,
                        child: Container(
                          decoration: BoxDecoration(
                            color: theme.cardColor,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: _buildModeTabButton(
                                  label: 'Visão Agenda',
                                  icon: Icons.calendar_month_rounded,
                                  isSelected: _isAgendaMode,
                                  onTap: () => setState(() => _isAgendaMode = true),
                                ),
                              ),
                              Expanded(
                                child: _buildModeTabButton(
                                  label: 'Visão Lista',
                                  icon: Icons.format_list_bulleted_rounded,
                                  isSelected: !_isAgendaMode,
                                  onTap: () => setState(() => _isAgendaMode = false),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // Conteúdo Baseado no Modo Ativo
                    Expanded(
                      child: _isAgendaMode
                          ? (isDesktop
                              ? _buildDesktopAgendaLayout(context, state, cubit, theme)
                              : _buildMobileAgendaLayout(context, state, cubit, theme))
                          : _buildListView(context, state, cubit, theme),
                    ),
                  ],
                ),
        );
      },
    );
  }

  Widget _buildModeTabButton({
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
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

  // --- VISÃO AGENDA (MOBILE) ---
  Widget _buildMobileAgendaLayout(
    BuildContext context,
    CalendarState state,
    CalendarCubit cubit,
    ThemeData theme,
  ) {
    final dayEvents = state.events.where((e) => _isSameDay(e.startTime, _selectedDate)).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
      children: [
        MiniCalendarCard(
          selectedDate: _selectedDate,
          events: state.events,
          onDateSelected: (date) {
            setState(() => _selectedDate = date);
          },
        ),
        const SizedBox(height: 12),
        _buildDayNavigationHeader(theme),
        const SizedBox(height: 14),
        if (dayEvents.isEmpty)
          _buildEmptyDayState(context, state, theme)
        else ...[
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              'Compromissos (${dayEvents.length})',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.primary),
            ),
          ),
          ...dayEvents.map((event) => _buildEventItem(context, event, state, cubit)),
        ],
      ],
    );
  }

  // --- VISÃO AGENDA (DESKTOP) ---
  Widget _buildDesktopAgendaLayout(
    BuildContext context,
    CalendarState state,
    CalendarCubit cubit,
    ThemeData theme,
  ) {
    final dayEvents = state.events.where((e) => _isSameDay(e.startTime, _selectedDate)).toList();

    return ResponsiveContainer(
      maxWidth: kMaxContentWidth,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Coluna Esquerda: Mini Calendário
          SizedBox(
            width: 320,
            child: MiniCalendarCard(
              selectedDate: _selectedDate,
              events: state.events,
              onDateSelected: (date) {
                setState(() => _selectedDate = date);
              },
            ),
          ),
          const SizedBox(width: 20),

          // Coluna Direita: Timeline do Dia Selecionado
          Expanded(
            child: Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Colors.grey.withValues(alpha: 0.15)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(child: _buildDayNavigationHeader(theme)),
                        const SizedBox(width: 12),
                        FilledButton.tonalIcon(
                          onPressed: () => AddEventSheet.show(context, state.activeMemberId),
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: const Text('Novo Evento'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: dayEvents.isEmpty
                          ? _buildEmptyDayState(context, state, theme)
                          : ListView.builder(
                              itemCount: dayEvents.length,
                              itemBuilder: (context, index) {
                                return _buildEventItem(context, dayEvents[index], state, cubit);
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDayNavigationHeader(ThemeData theme) {
    String formattedDay;
    try {
      formattedDay = DateFormat("EEEE, d 'de' MMMM", 'pt_BR').format(_selectedDate);
      formattedDay = formattedDay[0].toUpperCase() + formattedDay.substring(1);
    } catch (_) {
      formattedDay = DateFormat("EEE, d MMM").format(_selectedDate);
    }

    final isToday = _isSameDay(_selectedDate, DateTime.now());

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left_rounded, size: 22),
            tooltip: 'Dia Anterior',
            visualDensity: VisualDensity.compact,
            onPressed: _previousDay,
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  formattedDay,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
                if (isToday)
                  const Text(
                    'Hoje',
                    style: TextStyle(fontSize: 11, color: AppColors.primary, fontWeight: FontWeight.bold),
                  ),
              ],
            ),
          ),
          if (!isToday) ...[
            TextButton(
              onPressed: _goToToday,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: const Text('Hoje', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            ),
          ],
          IconButton(
            icon: const Icon(Icons.chevron_right_rounded, size: 22),
            tooltip: 'Próximo Dia',
            visualDensity: VisualDensity.compact,
            onPressed: _nextDay,
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyDayState(BuildContext context, CalendarState state, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.event_available_outlined, size: 42, color: Colors.grey.withValues(alpha: 0.4)),
          const SizedBox(height: 10),
          const Text(
            'Nenhum compromisso para este dia',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 14),
          ),
          const SizedBox(height: 4),
          const Text(
            'Aproveite o tempo livre ou adicione um novo evento para a casa.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 14),
          FilledButton.tonalIcon(
            onPressed: () => AddEventSheet.show(context, state.activeMemberId),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Adicionar Compromisso'),
          ),
        ],
      ),
    );
  }

  // --- VISÃO LISTA CORRIDA (TODOS OS COMPROMISSOS DA CASA) ---
  Widget _buildListView(BuildContext context, CalendarState state, CalendarCubit cubit, ThemeData theme) {
    return ResponsiveContainer(
      maxWidth: 900,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Todos os Compromissos (${state.events.length})',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                FilledButton.tonalIcon(
                  onPressed: () => AddEventSheet.show(context, state.activeMemberId),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Novo Evento'),
                  style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                ),
              ],
            ),
          ),
          Expanded(
            child: _buildEventsList(context, state, cubit),
          ),
        ],
      ),
    );
  }

  Widget _buildEventsList(BuildContext context, CalendarState state, CalendarCubit cubit) {
    if (state.events.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.event_note_outlined, size: 56, color: Colors.grey.withValues(alpha: 0.4)),
            const SizedBox(height: 12),
            const Text(
              'Nenhum compromisso agendado no lar',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.grey),
            ),
            const SizedBox(height: 6),
            const Text(
              'Organize jantares, faxinas conjuntas, visitas e reuniões.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: () => AddEventSheet.show(context, state.activeMemberId),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Criar Primeiro Evento'),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
      itemCount: state.events.length,
      itemBuilder: (context, index) {
        return _buildEventItem(context, state.events[index], state, cubit);
      },
    );
  }

  Widget _buildEventItem(BuildContext context, CalendarEvent event, CalendarState state, CalendarCubit cubit) {
    final derivedStatus = event.derivedStatus;
    final myParticipant = event.participants.firstWhere(
      (p) => p.memberId == state.activeMemberId,
      orElse: () => const EventParticipant(id: '', eventId: '', memberId: '', memberName: ''),
    );

    DateFormat dateFormat;
    try {
      dateFormat = DateFormat('EEE, d MMM - HH:mm', 'pt_BR');
    } catch (_) {
      dateFormat = DateFormat('EEE, d MMM - HH:mm');
    }

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
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
            if (event.description != null && event.description!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                event.description!,
                style: TextStyle(fontSize: 13, color: Colors.grey[300]),
              ),
            ],
            const Divider(height: 20),
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
}
