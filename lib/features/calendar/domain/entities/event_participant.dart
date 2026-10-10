import 'package:equatable/equatable.dart';

enum ParticipantRole {
  required,
  optional,
  info,
}

enum RsvpStatus {
  pending,
  accepted,
  declined,
  tentative,
}

class EventParticipant extends Equatable {
  final String id;
  final String eventId;
  final String memberId;
  final String memberName;
  final ParticipantRole role;
  final RsvpStatus rsvpStatus;
  final DateTime? respondedAt;

  const EventParticipant({
    required this.id,
    required this.eventId,
    required this.memberId,
    required this.memberName,
    this.role = ParticipantRole.required,
    this.rsvpStatus = RsvpStatus.pending,
    this.respondedAt,
  });

  bool get isEssential => role == ParticipantRole.required;

  EventParticipant copyWith({
    String? id,
    String? eventId,
    String? memberId,
    String? memberName,
    ParticipantRole? role,
    RsvpStatus? rsvpStatus,
    DateTime? respondedAt,
  }) {
    return EventParticipant(
      id: id ?? this.id,
      eventId: eventId ?? this.eventId,
      memberId: memberId ?? this.memberId,
      memberName: memberName ?? this.memberName,
      role: role ?? this.role,
      rsvpStatus: rsvpStatus ?? this.rsvpStatus,
      respondedAt: respondedAt ?? this.respondedAt,
    );
  }

  @override
  List<Object?> get props => [id, eventId, memberId, memberName, role, rsvpStatus, respondedAt];
}
