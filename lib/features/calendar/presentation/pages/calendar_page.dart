import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../../../core/domain/enums/recurrence.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/responsive.dart';
import '../../../../core/widgets/recurrence_scope_dialog.dart';
import '../../../../core/widgets/responsive_container.dart';
import '../../domain/entities/calendar_event.dart';
import '../../domain/entities/event_participant.dart';
import '../../../../core/di/service_locator.dart';
import '../../../auth/domain/repositories/auth_repository.dart';
import '../../../auth/presentation/cubit/auth_cubit.dart';
import '../../../auth/presentation/cubit/auth_state.dart';
import '../../../finance/presentation/cubit/finance_cubit.dart';
import '../cubit/calendar_cubit.dart';
import '../cubit/calendar_state.dart';
import '../widgets/add_event_sheet.dart';
import '../widgets/mini_calendar_card.dart';
import '../widgets/month_calendar_view.dart';
import '../widgets/week_calendar_view.dart';
import '../../../../core/widgets/save_feedback.dart';

enum CalendarViewMode {
  day,
  week,
  month,
  list,
}

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  DateTime _selectedDate = DateTime.now();
  CalendarViewMode _viewMode = CalendarViewMode.month;

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  DateTime get _startOfWeek {
    final diff = _selectedDate.weekday % 7; // 0 = Dom, 1 = Seg ...
    return DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day).subtract(Duration(days: diff));
  }

  DateTime get _endOfWeek {
    return _startOfWeek.add(const Duration(days: 6));
  }

  void _previousPeriod() {
    setState(() {
      switch (_viewMode) {
        case CalendarViewMode.day:
          _selectedDate = _selectedDate.subtract(const Duration(days: 1));
          break;
        case CalendarViewMode.week:
          _selectedDate = _selectedDate.subtract(const Duration(days: 7));
          break;
        case CalendarViewMode.month:
          _selectedDate = DateTime(_selectedDate.year, _selectedDate.month - 1, 1);
          break;
        case CalendarViewMode.list:
          _selectedDate = _selectedDate.subtract(const Duration(days: 30));
          break;
      }
    });
  }

  void _nextPeriod() {
    setState(() {
      switch (_viewMode) {
        case CalendarViewMode.day:
          _selectedDate = _selectedDate.add(const Duration(days: 1));
          break;
        case CalendarViewMode.week:
          _selectedDate = _selectedDate.add(const Duration(days: 7));
          break;
        case CalendarViewMode.month:
          _selectedDate = DateTime(_selectedDate.year, _selectedDate.month + 1, 1);
          break;
        case CalendarViewMode.list:
          _selectedDate = _selectedDate.add(const Duration(days: 30));
          break;
      }
    });
  }

  void _goToToday() {
    setState(() {
      _selectedDate = DateTime.now();
    });
  }

  bool get _isCurrentPeriodToday {
    final now = DateTime.now();
    switch (_viewMode) {
      case CalendarViewMode.day:
        return _isSameDay(_selectedDate, now);
      case CalendarViewMode.week:
        final start = _startOfWeek;
        final end = _endOfWeek.add(const Duration(days: 1));
        return now.isAfter(start.subtract(const Duration(seconds: 1))) && now.isBefore(end);
      case CalendarViewMode.month:
        return now.year == _selectedDate.year && now.month == _selectedDate.month;
      case CalendarViewMode.list:
        return true;
    }
  }

  String get _periodTitle {
    try {
      switch (_viewMode) {
        case CalendarViewMode.day:
          final formatted = DateFormat("EEEE, d 'de' MMMM", 'pt_BR').format(_selectedDate);
          return formatted[0].toUpperCase() + formatted.substring(1);
        case CalendarViewMode.week:
          final start = _startOfWeek;
          final end = _endOfWeek;
          if (start.month == end.month) {
            final monthStr = DateFormat('MMMM yyyy', 'pt_BR').format(end);
            return '${start.day} a ${end.day} de $monthStr';
          } else {
            final startMonthStr = DateFormat('MMM', 'pt_BR').format(start);
            final endMonthStr = DateFormat('MMM yyyy', 'pt_BR').format(end);
            return '${start.day} de $startMonthStr a ${end.day} de $endMonthStr';
          }
        case CalendarViewMode.month:
          final formatted = DateFormat("MMMM 'de' yyyy", 'pt_BR').format(_selectedDate);
          return formatted[0].toUpperCase() + formatted.substring(1);
        case CalendarViewMode.list:
          return 'Todos os Compromissos';
      }
    } catch (_) {
      return DateFormat('dd/MM/yyyy').format(_selectedDate);
    }
  }

  void _showEventDetailsModal(
    BuildContext context,
    CalendarEvent event,
    CalendarState state,
    CalendarCubit cubit,
  ) {
    showAdaptiveModal(
      context: context,
      maxWidth: 540,
      child: BlocProvider.value(
        value: cubit,
        child: BlocBuilder<CalendarCubit, CalendarState>(
          builder: (modalCtx, currentState) {
            // Recarrega o evento do estado atual para refletir mudanças de RSVP
            final currentEvent = currentState.events.firstWhere(
              (e) => e.id == event.id,
              orElse: () => event,
            );
            return Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Detalhes do Compromisso',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        tooltip: 'Fechar',
                        onPressed: () => Navigator.pop(modalCtx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildEventItem(modalCtx, currentEvent, currentState, cubit),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _openAddEventSheet(
    BuildContext context,
    CalendarState state, {
    CalendarEvent? initialEvent,
    DateTime? date,
  }) async {
    final targetDate = date ?? _selectedDate;
    final created = await AddEventSheet.show(
      context,
      state.activeMemberId,
      initialEvent: initialEvent,
      initialDate: targetDate,
    );
    if (created != null && mounted) {
      setState(() {
        _selectedDate = created.startTime;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<CalendarCubit, CalendarState>(
      listener: (context, state) {
        if (state.errorMessage != null && state.errorMessage!.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.errorMessage!),
              backgroundColor: AppColors.debtRed,
            ),
          );
        }
      },
      builder: (context, state) {
        final cubit = context.read<CalendarCubit>();
        final theme = Theme.of(context);
        final isDesktop = context.isDesktop;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Agenda do Lar', style: TextStyle(fontWeight: FontWeight.bold)),
            actions: [
              BlocBuilder<AuthCubit, AuthState>(
                builder: (context, authState) {
                  final isDemo = sl<AuthRepository>().isDemoMode;
                  final currentUser = authState.user;

                  if (isDemo) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: PopupMenuButton<String>(
                        initialValue: state.activeMemberId,
                        tooltip: 'Simular Membro (Demo)',
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
                            value: 'member_carlos',
                            child: Text('Ver como Carlos (Demo)'),
                          ),
                          PopupMenuItem(
                            value: 'member_marina',
                            child: Text('Ver como Marina (Demo)'),
                          ),
                        ],
                      ),
                    );
                  }

                  if (currentUser != null) {
                    final initial = currentUser.fullName.isNotEmpty
                        ? currentUser.fullName[0].toUpperCase()
                        : (currentUser.email.isNotEmpty ? currentUser.email[0].toUpperCase() : 'U');
                    final displayName = currentUser.fullName.isNotEmpty
                        ? currentUser.fullName.split(' ').first
                        : (currentUser.email.split('@').first);

                    return Padding(
                      padding: const EdgeInsets.only(right: 16),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircleAvatar(
                            radius: 13,
                            backgroundColor: AppColors.primary,
                            child: Text(
                              initial,
                              style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            displayName,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    );
                  }

                  return const SizedBox.shrink();
                },
              ),
            ],
          ),
          body: state.status == CalendarCubitStatus.loading && state.events.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    // Seletor de Modo (Dia, Semana, Mês, Lista no Desktop | Mês, Lista no Mobile)
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
                            children: isDesktop
                                ? [
                                    Expanded(
                                      child: _buildModeTabButton(
                                        label: 'Visão Dia',
                                        icon: Icons.view_day_rounded,
                                        isSelected: _viewMode == CalendarViewMode.day,
                                        onTap: () => setState(() => _viewMode = CalendarViewMode.day),
                                      ),
                                    ),
                                    Expanded(
                                      child: _buildModeTabButton(
                                        label: 'Visão Semana',
                                        icon: Icons.view_week_rounded,
                                        isSelected: _viewMode == CalendarViewMode.week,
                                        onTap: () => setState(() => _viewMode = CalendarViewMode.week),
                                      ),
                                    ),
                                    Expanded(
                                      child: _buildModeTabButton(
                                        label: 'Visão Mês',
                                        icon: Icons.calendar_view_month_rounded,
                                        isSelected: _viewMode == CalendarViewMode.month,
                                        onTap: () => setState(() => _viewMode = CalendarViewMode.month),
                                      ),
                                    ),
                                    Expanded(
                                      child: _buildModeTabButton(
                                        label: 'Visão Lista',
                                        icon: Icons.format_list_bulleted_rounded,
                                        isSelected: _viewMode == CalendarViewMode.list,
                                        onTap: () => setState(() => _viewMode = CalendarViewMode.list),
                                      ),
                                    ),
                                  ]
                                : [
                                    Expanded(
                                      child: _buildModeTabButton(
                                        label: 'Mês',
                                        icon: Icons.calendar_view_month_rounded,
                                        isSelected: _viewMode == CalendarViewMode.month || _viewMode == CalendarViewMode.day || _viewMode == CalendarViewMode.week,
                                        onTap: () => setState(() => _viewMode = CalendarViewMode.month),
                                      ),
                                    ),
                                    Expanded(
                                      child: _buildModeTabButton(
                                        label: 'Lista',
                                        icon: Icons.format_list_bulleted_rounded,
                                        isSelected: _viewMode == CalendarViewMode.list,
                                        onTap: () => setState(() => _viewMode = CalendarViewMode.list),
                                      ),
                                    ),
                                  ],
                          ),
                        ),
                      ),
                    ),

                    // Barra de Navegação (exceto na lista)
                    if (_viewMode != CalendarViewMode.list)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: ResponsiveContainer(
                          maxWidth: kMaxContentWidth,
                          child: _buildNavigationToolbar(theme, state),
                        ),
                      ),

                    // Conteúdo Baseado no Modo Ativo
                    Expanded(
                      child: _buildCurrentViewContent(context, state, cubit, theme, isDesktop),
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
            const SizedBox(width: 6),
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

  Widget _buildNavigationToolbar(ThemeData theme, CalendarState state) {
    final monthEventsCount = state.events.where((e) =>
      e.startTime.year == _selectedDate.year && e.startTime.month == _selectedDate.month
    ).length;
    final countLabel = monthEventsCount == 1 ? '1 compromisso no mês' : '$monthEventsCount compromissos no mês';

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
            tooltip: 'Anterior',
            visualDensity: VisualDensity.compact,
            onPressed: _previousPeriod,
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  _periodTitle,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  countLabel,
                  style: TextStyle(
                    fontSize: 11,
                    color: _isCurrentPeriodToday ? AppColors.primary : (theme.textTheme.bodySmall?.color?.withValues(alpha: 0.8) ?? Colors.grey),
                    fontWeight: _isCurrentPeriodToday ? FontWeight.bold : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          if (!_isCurrentPeriodToday) ...[
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
            tooltip: 'Próximo',
            visualDensity: VisualDensity.compact,
            onPressed: _nextPeriod,
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentViewContent(
    BuildContext context,
    CalendarState state,
    CalendarCubit cubit,
    ThemeData theme,
    bool isDesktop,
  ) {
    switch (_viewMode) {
      case CalendarViewMode.day:
        return isDesktop
            ? _buildDesktopDayLayout(context, state, cubit, theme)
            : _buildMobileMonthLayout(context, state, cubit, theme);

      case CalendarViewMode.week:
        return isDesktop
            ? Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: ResponsiveContainer(
                  maxWidth: kMaxContentWidth,
                  child: WeekCalendarView(
                    selectedDate: _selectedDate,
                    events: state.events,
                    onDateSelected: (date) {
                      setState(() {
                        _selectedDate = date;
                        _viewMode = CalendarViewMode.day;
                      });
                    },
                    onEventTap: (event) => _showEventDetailsModal(context, event, state, cubit),
                    onAddEvent: (date) {
                      setState(() => _selectedDate = date);
                      _openAddEventSheet(context, state, date: date);
                    },
                  ),
                ),
              )
            : _buildMobileMonthLayout(context, state, cubit, theme);

      case CalendarViewMode.month:
        final billDates = <DateTime>[];
        try {
          final expenses = context.read<FinanceCubit>().state.expenses;
          for (final exp in expenses) {
            billDates.add(exp.effectiveDueDate);
          }
        } catch (_) {}

        return isDesktop
            ? Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: ResponsiveContainer(
                  maxWidth: kMaxContentWidth,
                  child: MonthCalendarView(
                    selectedDate: _selectedDate,
                    events: state.events,
                    billDueDates: billDates,
                    onDateSelected: (date) {
                      setState(() {
                        _selectedDate = date;
                        _viewMode = CalendarViewMode.day;
                      });
                    },
                    onEventTap: (event) => _showEventDetailsModal(context, event, state, cubit),
                    onAddEvent: (date) {
                      setState(() => _selectedDate = date);
                      _openAddEventSheet(context, state, date: date);
                    },
                  ),
                ),
              )
            : _buildMobileMonthLayout(context, state, cubit, theme, billDates);
      case CalendarViewMode.list:
        return _buildListView(context, state, cubit, theme, isDesktop);
    }
  }

  // --- VISÃO MÊS UNIFICADA COM AGENDA DO DIA (MOBILE COM SCROLL CONTÍNUO) ---
  Widget _buildMobileMonthLayout(
    BuildContext context,
    CalendarState state,
    CalendarCubit cubit,
    ThemeData theme, [
    List<DateTime> billDueDates = const [],
  ]) {
    final dayEvents = state.events.where((e) => _isSameDay(e.startTime, _selectedDate)).toList();
    String formattedSelectedDay;
    try {
      formattedSelectedDay = DateFormat("EEEE, d 'de' MMMM", 'pt_BR').format(_selectedDate);
    } catch (_) {
      formattedSelectedDay = DateFormat('dd/MM/yyyy').format(_selectedDate);
    }
    final capitalizedDay = formattedSelectedDay.isNotEmpty
        ? formattedSelectedDay[0].toUpperCase() + formattedSelectedDay.substring(1)
        : '';

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
      children: [
        // Grade do Mês compacta no topo (rola junto com toda a tela)
        MonthCalendarView(
          isCompact: true,
          selectedDate: _selectedDate,
          events: state.events,
          billDueDates: billDueDates,
          onDateSelected: (date) {
            setState(() => _selectedDate = date);
          },
          onEventTap: (event) => _showEventDetailsModal(context, event, state, cubit),
          onAddEvent: (date) {
            setState(() => _selectedDate = date);
            _openAddEventSheet(context, state, date: date);
          },
        ),
        const SizedBox(height: 14),

        // Cabeçalho dos compromissos da data selecionada
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      capitalizedDay,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.primary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'Compromissos (${dayEvents.length})',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: () => _openAddEventSheet(context, state, date: _selectedDate),
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('Novo', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // Lista de compromissos do dia selecionado (rola de forma unificada)
        if (dayEvents.isEmpty)
          _buildEmptyDayState(context, state, theme)
        else
          ...dayEvents.map((event) => _buildEventItem(context, event, state, cubit)),
      ],
    );
  }



  // --- VISÃO DIA (DESKTOP) ---
  Widget _buildDesktopDayLayout(
    BuildContext context,
    CalendarState state,
    CalendarCubit cubit,
    ThemeData theme,
  ) {
    final dayEvents = state.events.where((e) => _isSameDay(e.startTime, _selectedDate)).toList();

    return ResponsiveContainer(
      maxWidth: kMaxContentWidth,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Coluna Esquerda: Mini Calendário (estilo moderno unificado)
            SizedBox(
              width: 320,
              child: MiniCalendarCard(
                selectedDate: _selectedDate,
                events: state.events,
                onDateSelected: (date) {
                  setState(() => _selectedDate = date);
                },
                onEventTap: (event) => _showEventDetailsModal(context, event, state, cubit),
                onAddEvent: (date) {
                  setState(() => _selectedDate = date);
                  _openAddEventSheet(context, state, date: date);
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
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Compromissos do Dia (${dayEvents.length})',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          FilledButton.tonalIcon(
                            onPressed: () => _openAddEventSheet(context, state),
                            icon: const Icon(Icons.add_rounded, size: 18),
                            label: const Text('Novo Evento'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
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
            onPressed: () => _openAddEventSheet(context, state),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Adicionar Compromisso'),
          ),
        ],
      ),
    );
  }

  // --- VISÃO LISTA CORRIDA COM MINI CALENDÁRIO ---
  Widget _buildListView(
    BuildContext context,
    CalendarState state,
    CalendarCubit cubit,
    ThemeData theme,
    bool isDesktop,
  ) {
    if (isDesktop) {
      return ResponsiveContainer(
        maxWidth: kMaxContentWidth,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Coluna Esquerda: Mini Calendário (estilo moderno unificado)
              SizedBox(
                width: 320,
                child: MiniCalendarCard(
                  selectedDate: _selectedDate,
                  events: state.events,
                  onDateSelected: (date) {
                    setState(() => _selectedDate = date);
                  },
                  onEventTap: (event) => _showEventDetailsModal(context, event, state, cubit),
                  onAddEvent: (date) {
                    setState(() => _selectedDate = date);
                    _openAddEventSheet(context, state, date: date);
                  },
                ),
              ),
              const SizedBox(width: 20),

              // Coluna Direita: Todos os Compromissos
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
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Todos os Compromissos (${state.events.length})',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            FilledButton.tonalIcon(
                              onPressed: () => _openAddEventSheet(context, state),
                              icon: const Icon(Icons.add_rounded, size: 18),
                              label: const Text('Novo Evento'),
                              style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Expanded(
                          child: _buildEventsList(context, state, cubit),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Mobile: lista corrida de compromissos com mini calendário compacto no topo
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
      children: [
        MonthCalendarView(
          isCompact: true,
          selectedDate: _selectedDate,
          events: state.events,
          onDateSelected: (date) {
            setState(() {
              _selectedDate = date;
              _viewMode = CalendarViewMode.month;
            });
          },
          onEventTap: (event) => _showEventDetailsModal(context, event, state, cubit),
          onAddEvent: (date) {
            setState(() => _selectedDate = date);
            _openAddEventSheet(context, state, date: date);
          },
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Todos os Compromissos (${state.events.length})',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            FilledButton.tonalIcon(
              onPressed: () => _openAddEventSheet(context, state),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Novo Evento'),
              style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (state.events.isEmpty)
          _buildEmptyEventsWidget(context, state)
        else
          ...state.events.map((event) => _buildEventItem(context, event, state, cubit)),
      ],
    );
  }

  Widget _buildEmptyEventsWidget(BuildContext context, CalendarState state) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
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
              onPressed: () => _openAddEventSheet(context, state),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Criar Primeiro Evento'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEventsList(BuildContext context, CalendarState state, CalendarCubit cubit) {
    if (state.events.isEmpty) {
      return _buildEmptyEventsWidget(context, state);
    }

    return ListView.builder(
      padding: EdgeInsets.zero,
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              event.title,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                          ),
                          if (event.isRecurring) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.repeat_rounded, size: 11, color: AppColors.primary),
                                  const SizedBox(width: 2),
                                  Text(
                                    event.recurrenceFrequency.shortLabel,
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          if (event.isRecurringException) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.orange.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.push_pin_outlined, size: 11, color: Colors.orange),
                                  SizedBox(width: 2),
                                  Text(
                                    'Exceção',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.orange,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
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
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  tooltip: 'Editar',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => _openAddEventSheet(context, state, initialEvent: event),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.debtRed),
                  tooltip: 'Excluir',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => _handleDeleteEvent(context, event, cubit),
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

  Future<void> _handleDeleteEvent(BuildContext context, CalendarEvent event, CalendarCubit cubit) async {
    RecurrenceScope scope = RecurrenceScope.thisInstanceOnly;
    if (event.isRecurring) {
      final chosenScope = await showRecurrenceScopeDialog(
        context: context,
        itemTitle: event.title,
        isDelete: true,
      );
      if (chosenScope == null) return;
      scope = chosenScope;
    } else {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Excluir Compromisso'),
          content: Text('Tem certeza que deseja excluir "${event.title}"?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.debtRed, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Excluir'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    final messenger = ScaffoldMessenger.of(context);
    var ok = true;
    try {
      await cubit.deleteEvent(event.id, scope: scope);
    } catch (_) {
      ok = false;
    }
    showSaveFeedback(
      messenger,
      ok: ok,
      success: 'Compromisso "${event.title}" excluído.',
      failure: cubit.state.errorMessage,
    );
  }
}
