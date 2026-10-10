import 'package:flutter/material.dart';
import '../../domain/entities/calendar_event.dart';
import 'month_calendar_view.dart';

/// Calendário compacto que adota o visual moderno e unificado de [MonthCalendarView].
class MiniCalendarCard extends StatelessWidget {
  final DateTime selectedDate;
  final ValueChanged<DateTime> onDateSelected;
  final List<CalendarEvent> events;
  final ValueChanged<CalendarEvent>? onEventTap;
  final ValueChanged<DateTime>? onAddEvent;

  const MiniCalendarCard({
    super.key,
    required this.selectedDate,
    required this.onDateSelected,
    this.events = const [],
    this.onEventTap,
    this.onAddEvent,
  });

  @override
  Widget build(BuildContext context) {
    return MonthCalendarView(
      isCompact: true,
      selectedDate: selectedDate,
      events: events,
      onDateSelected: onDateSelected,
      onEventTap: onEventTap ?? (_) {},
      onAddEvent: onAddEvent,
    );
  }
}
