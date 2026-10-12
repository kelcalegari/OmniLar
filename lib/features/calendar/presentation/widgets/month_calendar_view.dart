import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/entities/calendar_event.dart';

class MonthCalendarView extends StatelessWidget {
  final DateTime selectedDate;
  final List<CalendarEvent> events;
  final List<DateTime> billDueDates;
  final ValueChanged<DateTime> onDateSelected;
  final ValueChanged<CalendarEvent> onEventTap;
  final ValueChanged<DateTime>? onAddEvent;
  final bool isCompact;

  const MonthCalendarView({
    super.key,
    required this.selectedDate,
    required this.events,
    this.billDueDates = const [],
    required this.onDateSelected,
    required this.onEventTap,
    this.onAddEvent,
    this.isCompact = false,
  });

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDesktop = MediaQuery.of(context).size.width >= 900;

    final firstDayOfMonth = DateTime(selectedDate.year, selectedDate.month, 1);
    final daysInMonth = DateTime(selectedDate.year, selectedDate.month + 1, 0).day;
    final firstWeekday = firstDayOfMonth.weekday % 7; // 0 = Dom, 1 = Seg ...

    // Preenche os dias anteriores para alinhar com o primeiro dia da semana
    final prevMonthLastDay = DateTime(selectedDate.year, selectedDate.month, 0).day;
    final totalCells = ((firstWeekday + daysInMonth + 6) ~/ 7) * 7;

    const weekHeaders = ['Domingo', 'Segunda', 'Terça', 'Quarta', 'Quinta', 'Sexta', 'Sábado'];
    const shortWeekHeaders = ['Dom', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb'];

    final now = DateTime.now();

    final gridContent = Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
        border: Border(
          left: BorderSide(color: Colors.grey.withValues(alpha: 0.15)),
          right: BorderSide(color: Colors.grey.withValues(alpha: 0.15)),
          bottom: BorderSide(color: Colors.grey.withValues(alpha: 0.15)),
        ),
      ),
      child: GridView.builder(
        padding: EdgeInsets.zero,
        shrinkWrap: isCompact,
        physics: isCompact
            ? const NeverScrollableScrollPhysics()
            : const AlwaysScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 7,
          childAspectRatio: isCompact
              ? 1.05
              : (isDesktop ? 1.35 : 0.85),
        ),
        itemCount: totalCells,
        itemBuilder: (context, index) {
          DateTime cellDate;
          bool isCurrentMonth = true;

          if (index < firstWeekday) {
            // Dias do mês anterior
            final day = prevMonthLastDay - (firstWeekday - index - 1);
            cellDate = DateTime(selectedDate.year, selectedDate.month - 1, day);
            isCurrentMonth = false;
          } else if (index >= firstWeekday + daysInMonth) {
            // Dias do próximo mês
            final day = index - (firstWeekday + daysInMonth) + 1;
            cellDate = DateTime(selectedDate.year, selectedDate.month + 1, day);
            isCurrentMonth = false;
          } else {
            // Dias do mês corrente
            final day = index - firstWeekday + 1;
            cellDate = DateTime(selectedDate.year, selectedDate.month, day);
          }

          final isToday = _isSameDay(cellDate, now);
          final isSelected = _isSameDay(cellDate, selectedDate);

          // Eventos deste dia
          final dayEvents = events.where((e) => _isSameDay(e.startTime, cellDate)).toList();
          final hasBillDue = billDueDates.any((b) => _isSameDay(b, cellDate));

          return InkWell(
            onTap: () => onDateSelected(cellDate),
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
                color: isSelected
                    ? AppColors.primary.withValues(alpha: 0.08)
                    : (isCurrentMonth ? null : Colors.grey.withValues(alpha: 0.03)),
              ),
              padding: isCompact
                  ? const EdgeInsets.symmetric(vertical: 2, horizontal: 1)
                  : const EdgeInsets.all(4),
              child: isCompact
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isToday
                                ? AppColors.primary
                                : (isSelected ? AppColors.primary.withValues(alpha: 0.2) : Colors.transparent),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '${cellDate.day}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: isToday || isSelected ? FontWeight.bold : FontWeight.w500,
                              color: isToday
                                  ? Colors.white
                                  : (isCurrentMonth
                                      ? (isSelected ? AppColors.primary : theme.textTheme.bodyMedium?.color)
                                      : Colors.grey.withValues(alpha: 0.4)),
                            ),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (dayEvents.isNotEmpty)
                              Container(
                                width: 5,
                                height: 5,
                                margin: const EdgeInsets.symmetric(horizontal: 1),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isSelected ? AppColors.primary : AppColors.primary.withValues(alpha: 0.85),
                                ),
                              ),
                            if (hasBillDue)
                              Container(
                                width: 5,
                                height: 5,
                                margin: const EdgeInsets.symmetric(horizontal: 1),
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.amber,
                                ),
                              ),
                            if (dayEvents.isEmpty && !hasBillDue)
                              const SizedBox(height: 5),
                          ],
                        ),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Cabeçalho da Célula (Número do dia)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isToday
                                    ? AppColors.primary
                                    : (isSelected ? AppColors.primary.withValues(alpha: 0.2) : Colors.transparent),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                '${cellDate.day}',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: isToday || isSelected ? FontWeight.bold : FontWeight.w500,
                                  color: isToday
                                      ? Colors.white
                                      : (isCurrentMonth
                                          ? theme.textTheme.bodyMedium?.color
                                          : Colors.grey.withValues(alpha: 0.4)),
                                ),
                              ),
                            ),
                            if (!isDesktop)
                              Row(
                                children: [
                                  if (dayEvents.isNotEmpty)
                                    Container(
                                      width: 6,
                                      height: 6,
                                      margin: const EdgeInsets.only(right: 2),
                                      decoration: const BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                  if (hasBillDue)
                                    Container(
                                      width: 6,
                                      height: 6,
                                      decoration: const BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: Colors.amber,
                                      ),
                                    ),
                                ],
                              ),
                            if (isDesktop && isCurrentMonth)
                              InkWell(
                                onTap: onAddEvent != null ? () => onAddEvent!(cellDate) : null,
                                borderRadius: BorderRadius.circular(4),
                                child: Padding(
                                  padding: const EdgeInsets.all(2),
                                  child: Icon(
                                    Icons.add_rounded,
                                    size: 14,
                                    color: Colors.grey.withValues(alpha: 0.5),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 2),

                        // Lista de Pílulas de Eventos (em desktop mostra os cards/chips dentro do dia)
                        if (isDesktop) ...[
                          Expanded(
                            child: ListView.builder(
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: dayEvents.length > 3 ? 4 : dayEvents.length,
                              itemBuilder: (ctx, i) {
                                if (i == 3) {
                                  final remaining = dayEvents.length - 3;
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 2, left: 2),
                                    child: Text(
                                      '+$remaining mais',
                                      style: const TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                  );
                                }

                                final event = dayEvents[i];
                                Color eventColor;
                                switch (event.derivedStatus) {
                                  case EventDerivedStatus.confirmed:
                                    eventColor = AppColors.creditGreen;
                                    break;
                                  case EventDerivedStatus.atRisk:
                                    eventColor = AppColors.debtRed;
                                    break;
                                  case EventDerivedStatus.waiting:
                                    eventColor = Colors.orange;
                                    break;
                                  default:
                                    eventColor = AppColors.primary;
                                }

                                final timeStr = DateFormat('HH:mm').format(event.startTime);

                                return InkWell(
                                  onTap: () => onEventTap(event),
                                  borderRadius: BorderRadius.circular(4),
                                  child: Container(
                                    margin: const EdgeInsets.only(bottom: 2),
                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: eventColor.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: eventColor.withValues(alpha: 0.3)),
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 4,
                                          height: 4,
                                          decoration: BoxDecoration(shape: BoxShape.circle, color: eventColor),
                                        ),
                                        const SizedBox(width: 3),
                                        Expanded(
                                          child: Text(
                                            '$timeStr ${event.title}',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w600,
                                              color: theme.textTheme.bodyMedium?.color,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ] else ...[
                          // Em mobile (não-compacto): mostra indicadores compactos ou títulos curtos
                          if (dayEvents.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                '${dayEvents.length} evento(s)',
                                style: const TextStyle(fontSize: 9, color: AppColors.primary, fontWeight: FontWeight.bold),
                                maxLines: 1,
                              ),
                            ),
                        ],
                      ],
                    ),
            ),
          );
        },
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: isCompact ? MainAxisSize.min : MainAxisSize.max,
      children: [
        // Cabeçalho dos dias da semana
        Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
          ),
          child: Row(
            children: List.generate(7, (index) {
              final useShortHeaders = isCompact || !isDesktop;
              final label = useShortHeaders ? shortWeekHeaders[index] : weekHeaders[index];
              final isWeekend = index == 0 || index == 6;
              return Expanded(
                child: Center(
                  child: Text(
                    label,
                    maxLines: 1,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: useShortHeaders ? 12 : 13,
                      color: isWeekend ? Colors.grey : theme.textTheme.bodyMedium?.color,
                    ),
                  ),
                ),
              );
            }),
          ),
        ),

        // Grade do mês
        if (isCompact) gridContent else Expanded(child: gridContent),
      ],
    );
  }
}
