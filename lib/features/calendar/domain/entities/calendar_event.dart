import 'package:equatable/equatable.dart';
import '../../../../core/domain/enums/recurrence.dart';
import 'event_participant.dart';

enum EventDerivedStatus {
  confirmed,
  atRisk,
  waiting,
  cancelled,
  noEssential,
}

enum EventVisibility {
  house,
  restricted,
  private,
}

class CalendarEvent extends Equatable {
  final String id;
  final String title;
  final String? description;
  final String? location;
  final DateTime startTime;
  final DateTime endTime;
  final bool isAllDay;
  final String createdByMemberId;
  final EventVisibility visibility;
  final bool isCancelled;
  final List<EventParticipant> participants;
  final RecurrenceFrequency recurrenceFrequency;
  final String? seriesId;
  final DateTime? recurrenceEndDate;
  final bool isRecurringException;

  const CalendarEvent({
    required this.id,
    required this.title,
    this.description,
    this.location,
    required this.startTime,
    required this.endTime,
    this.isAllDay = false,
    required this.createdByMemberId,
    this.visibility = EventVisibility.house,
    this.isCancelled = false,
    this.participants = const [],
    this.recurrenceFrequency = RecurrenceFrequency.none,
    this.seriesId,
    this.recurrenceEndDate,
    this.isRecurringException = false,
  });

  bool get isRecurring =>
      recurrenceFrequency != RecurrenceFrequency.none || (seriesId != null && seriesId!.isNotEmpty);

  /// RN01: Status derivado a partir das respostas dos participantes Necessários
  EventDerivedStatus get derivedStatus {
    if (isCancelled) return EventDerivedStatus.cancelled;

    final essentialParticipants = participants.where((p) => p.isEssential).toList();

    if (essentialParticipants.isEmpty) {
      return EventDerivedStatus.noEssential;
    }

    final hasDeclinedOrMaybe = essentialParticipants.any(
      (p) => p.rsvpStatus == RsvpStatus.declined || p.rsvpStatus == RsvpStatus.tentative,
    );
    if (hasDeclinedOrMaybe) {
      return EventDerivedStatus.atRisk;
    }

    final hasPending = essentialParticipants.any((p) => p.rsvpStatus == RsvpStatus.pending);
    if (hasPending) {
      return EventDerivedStatus.waiting;
    }

    return EventDerivedStatus.confirmed;
  }

  CalendarEvent copyWith({
    String? id,
    String? title,
    String? description,
    String? location,
    DateTime? startTime,
    DateTime? endTime,
    bool? isAllDay,
    String? createdByMemberId,
    EventVisibility? visibility,
    bool? isCancelled,
    List<EventParticipant>? participants,
    RecurrenceFrequency? recurrenceFrequency,
    String? seriesId,
    bool clearSeriesId = false,
    DateTime? recurrenceEndDate,
    bool? isRecurringException,
  }) {
    return CalendarEvent(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      location: location ?? this.location,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      isAllDay: isAllDay ?? this.isAllDay,
      createdByMemberId: createdByMemberId ?? this.createdByMemberId,
      visibility: visibility ?? this.visibility,
      isCancelled: isCancelled ?? this.isCancelled,
      participants: participants ?? this.participants,
      recurrenceFrequency: recurrenceFrequency ?? this.recurrenceFrequency,
      seriesId: clearSeriesId ? null : (seriesId ?? this.seriesId),
      recurrenceEndDate: recurrenceEndDate ?? this.recurrenceEndDate,
      isRecurringException: isRecurringException ?? this.isRecurringException,
    );
  }

  @override
  List<Object?> get props => [
        id,
        title,
        description,
        location,
        startTime,
        endTime,
        isAllDay,
        createdByMemberId,
        visibility,
        isCancelled,
        participants,
        recurrenceFrequency,
        seriesId,
        recurrenceEndDate,
        isRecurringException,
      ];
}
