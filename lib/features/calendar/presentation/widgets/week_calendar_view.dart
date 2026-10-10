import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/entities/calendar_event.dart';

class WeekCalendarView extends StatelessWidget {
  final DateTime selectedDate;
  final List<CalendarEvent> events;
  final ValueChanged<DateTime> onDateSelected;
  final ValueChanged<CalendarEvent> onEventTap;
  final ValueChanged<DateTime>? onAddEvent;

  const WeekCalendarView({
    super.key,
    required this.selectedDate,
    required this.events,
    required this.onDateSelected,
    required this.onEventTap,
    this.onAddEvent,
  });

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  DateTime get _startOfWeek {
    final diff = selectedDate.weekday % 7; // 0 = Dom, 1 = Seg ...
    return DateTime(selectedDate.year, selectedDate.month, selectedDate.day).subtract(Duration(days: diff));
  }

  List<DateTime> get _daysOfWeek {
    final start = _startOfWeek;
    return List.generate(7, (i) => start.add(Duration(days: i)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final days = _daysOfWeek;
    final now = DateTime.now();

    const weekDayNames = ['Dom', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb'];
    const fullWeekDayNames = [
      'Domingo',
      'Segunda',
      'Terça',
      'Quarta',
      'Quinta',
      'Sexta',
      'Sábado',
    ];

    final isWide = MediaQuery.of(context).size.width >= 1000;

    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: List.generate(7, (index) {
              final dayDate = days[index];
              final isToday = _isSameDay(dayDate, now);
              final isSelected = _isSameDay(dayDate, selectedDate);
              final dayEvents = events.where((e) => _isSameDay(e.startTime, dayDate)).toList();

              return Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    border: Border(
                      right: index < 6
                          ? BorderSide(color: Colors.grey.withValues(alpha: 0.15))
                          : BorderSide.none,
                    ),
                    color: isSelected ? AppColors.primary.withValues(alpha: 0.04) : null,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Cabeçalho do Dia na Semana
                      InkWell(
                        onTap: () => onDateSelected(dayDate),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                          decoration: BoxDecoration(
                            color: isToday
                                ? AppColors.primary.withValues(alpha: 0.1)
                                : (isSelected ? AppColors.primary.withValues(alpha: 0.08) : null),
                            border: Border(
                              bottom: BorderSide(color: Colors.grey.withValues(alpha: 0.15)),
                            ),
                          ),
                          child: Column(
                            children: [
                              Text(
                                isWide ? fullWeekDayNames[index] : weekDayNames[index],
                                style: TextStyle(
                                  fontSize: isWide ? 12 : 11,
                                  fontWeight: FontWeight.w600,
                                  color: isToday ? AppColors.primary : Colors.grey,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Container(
                                width: 26,
                                height: 26,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isToday
                                      ? AppColors.primary
                                      : (isSelected ? AppColors.primary.withValues(alpha: 0.2) : Colors.transparent),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  '${dayDate.day}',
                                  style: TextStyle(
                                    fontWeight: isToday || isSelected ? FontWeight.bold : FontWeight.normal,
                                    fontSize: 13,
                                    color: isToday ? Colors.white : theme.textTheme.bodyMedium?.color,
                                  ),
                                ),
                              ),
                              if (isWide && onAddEvent != null) ...[
                                const SizedBox(height: 4),
                                InkWell(
                                  onTap: () => onAddEvent!(dayDate),
                                  borderRadius: BorderRadius.circular(4),
                                  child: const Icon(Icons.add_rounded, size: 14, color: Colors.grey),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),

                      // Lista de Eventos do Dia
                      Expanded(
                        child: dayEvents.isEmpty
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: Text(
                                    'Livre',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.withValues(alpha: 0.4),
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ),
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.all(6),
                                itemCount: dayEvents.length,
                                itemBuilder: (context, i) {
                                  final event = dayEvents[i];
                                  return _buildWeekEventCard(context, event, theme, isWide);
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          );
        },
      ),
    );
  }

  Widget _buildWeekEventCard(
    BuildContext context,
    CalendarEvent event,
    ThemeData theme,
    bool isWide,
  ) {
    Color statusColor;
    switch (event.derivedStatus) {
      case EventDerivedStatus.confirmed:
        statusColor = AppColors.creditGreen;
        break;
      case EventDerivedStatus.atRisk:
        statusColor = AppColors.debtRed;
        break;
      case EventDerivedStatus.waiting:
        statusColor = Colors.orange;
        break;
      default:
        statusColor = AppColors.primary;
    }

    final startTimeStr = DateFormat('HH:mm').format(event.startTime);
    final endTimeStr = DateFormat('HH:mm').format(event.endTime);

    return InkWell(
      onTap: () => onEventTap(event),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: statusColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: statusColor.withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: statusColor),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    startTimeStr,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              event.title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (isWide && event.location != null) ...[
              const SizedBox(height: 2),
              Row(
                children: [
                  const Icon(Icons.location_on_outlined, size: 10, color: Colors.grey),
                  const SizedBox(width: 2),
                  Expanded(
                    child: Text(
                      event.location!,
                      style: const TextStyle(fontSize: 9, color: Colors.grey),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
            if (isWide) ...[
              const SizedBox(height: 4),
              Text(
                'até $endTimeStr',
                style: const TextStyle(fontSize: 9, color: Colors.grey),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
