import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/entities/calendar_event.dart';

class MiniCalendarCard extends StatefulWidget {
  final DateTime selectedDate;
  final ValueChanged<DateTime> onDateSelected;
  final List<CalendarEvent> events;

  const MiniCalendarCard({
    super.key,
    required this.selectedDate,
    required this.onDateSelected,
    this.events = const [],
  });

  @override
  State<MiniCalendarCard> createState() => _MiniCalendarCardState();
}

class _MiniCalendarCardState extends State<MiniCalendarCard> {
  late DateTime _displayedMonth;

  @override
  void initState() {
    super.initState();
    _displayedMonth = DateTime(widget.selectedDate.year, widget.selectedDate.month, 1);
  }

  @override
  void didUpdateWidget(covariant MiniCalendarCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedDate.year != widget.selectedDate.year ||
        oldWidget.selectedDate.month != widget.selectedDate.month) {
      _displayedMonth = DateTime(widget.selectedDate.year, widget.selectedDate.month, 1);
    }
  }

  void _prevMonth() {
    setState(() {
      _displayedMonth = DateTime(_displayedMonth.year, _displayedMonth.month - 1, 1);
    });
  }

  void _nextMonth() {
    setState(() {
      _displayedMonth = DateTime(_displayedMonth.year, _displayedMonth.month + 1, 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final daysInMonth = DateTime(_displayedMonth.year, _displayedMonth.month + 1, 0).day;
    final firstWeekday = DateTime(_displayedMonth.year, _displayedMonth.month, 1).weekday % 7; // Dom = 0

    const monthNames = [
      'Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio', 'Junho',
      'Julho', 'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro'
    ];

    const weekHeaders = ['D', 'S', 'T', 'Q', 'Q', 'S', 'S'];

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.withValues(alpha: 0.15)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${monthNames[_displayedMonth.month - 1]} ${_displayedMonth.year}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left_rounded, size: 20),
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Mês anterior',
                      onPressed: _prevMonth,
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right_rounded, size: 20),
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Próximo mês',
                      onPressed: _nextMonth,
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: weekHeaders
                  .map(
                    (d) => SizedBox(
                      width: 28,
                      child: Text(
                        d,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey),
                      ),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 8),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: 42, // 6 semanas
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                mainAxisSpacing: 4,
                crossAxisSpacing: 4,
              ),
              itemBuilder: (context, index) {
                final dayNumber = index - firstWeekday + 1;
                final isValidDay = dayNumber >= 1 && dayNumber <= daysInMonth;

                if (!isValidDay) {
                  return const SizedBox.shrink();
                }

                final currentDate = DateTime(_displayedMonth.year, _displayedMonth.month, dayNumber);
                final isSelected = currentDate.year == widget.selectedDate.year &&
                    currentDate.month == widget.selectedDate.month &&
                    currentDate.day == widget.selectedDate.day;
                final isToday = currentDate.year == DateTime.now().year &&
                    currentDate.month == DateTime.now().month &&
                    currentDate.day == DateTime.now().day;

                final hasEvents = widget.events.any((e) =>
                    e.startTime.year == currentDate.year &&
                    e.startTime.month == currentDate.month &&
                    e.startTime.day == currentDate.day);

                return InkWell(
                  onTap: () => widget.onDateSelected(currentDate),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.primary
                          : (isToday ? AppColors.primary.withValues(alpha: 0.15) : null),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '$dayNumber',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: isSelected || isToday ? FontWeight.bold : FontWeight.normal,
                            color: isSelected
                                ? Colors.white
                                : (isToday ? AppColors.primary : theme.textTheme.bodyMedium?.color),
                          ),
                        ),
                        if (hasEvents) ...[
                          const SizedBox(height: 2),
                          Container(
                            width: 5,
                            height: 5,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isSelected ? Colors.white : AppColors.primary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
            const Divider(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.primary),
                ),
                const SizedBox(width: 6),
                const Text('Compromissos agendados', style: TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
