import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/features/calendar/data/datasources/mock_calendar_datasource.dart';
import 'package:omni_lar/features/calendar/data/repositories/calendar_repository_impl.dart';
import 'package:omni_lar/features/calendar/domain/entities/calendar_event.dart';
import 'package:omni_lar/features/calendar/domain/entities/event_participant.dart';
import 'package:omni_lar/features/calendar/domain/entities/task_item.dart';

void main() {
  group('Calendar & Tasks Module - RN01 Status Derivado & Regras', () {
    late MockCalendarDataSource dataSource;
    late CalendarRepositoryImpl repository;

    setUp(() {
      dataSource = MockCalendarDataSource();
      repository = CalendarRepositoryImpl(dataSource);
    });

    test('RN01: Evento é Confirmado quando todos os Necessários aceitam', () {
      final now = DateTime.now();
        final event = CalendarEvent(
        id: 'ev_test',
        title: 'Almoço de Domingo',
        startTime: DateTime(2026, 10, 18, 12),
        endTime: DateTime(2026, 10, 18, 15),
        createdByMemberId: 'm1',
        participants: const [
          EventParticipant(
            id: 'p1',
            eventId: 'ev_test',
            memberId: 'm1',
            memberName: 'Carlos',
            role: ParticipantRole.required,
            rsvpStatus: RsvpStatus.accepted,
          ),
          EventParticipant(
            id: 'p2',
            eventId: 'ev_test',
            memberId: 'm2',
            memberName: 'Marina',
            role: ParticipantRole.required,
            rsvpStatus: RsvpStatus.accepted,
          ),
          EventParticipant(
            id: 'p3',
            eventId: 'ev_test',
            memberId: 'm3',
            memberName: 'Amigo',
            role: ParticipantRole.optional,
            rsvpStatus: RsvpStatus.pending, // Opcional pendente NÃO altera o status
          ),
        ],
      );

      expect(event.derivedStatus, equals(EventDerivedStatus.confirmed));
    });

    test('RN01: Evento fica Em Risco quando um Necessário recusa ou responde Talvez', () {
      final eventWithDeclined = CalendarEvent(
        id: 'ev_risk_1',
        title: 'Reunião de Condomínio',
        startTime: DateTime(2026, 10, 19, 19),
        endTime: DateTime(2026, 10, 19, 21),
        createdByMemberId: 'm1',
        participants: const [
          EventParticipant(
            id: 'p1',
            eventId: 'ev_risk_1',
            memberId: 'm1',
            memberName: 'Carlos',
            role: ParticipantRole.required,
            rsvpStatus: RsvpStatus.accepted,
          ),
          EventParticipant(
            id: 'p2',
            eventId: 'ev_risk_1',
            memberId: 'm2',
            memberName: 'Marina',
            role: ParticipantRole.required,
            rsvpStatus: RsvpStatus.declined, // Recusou
          ),
        ],
      );

      expect(eventWithDeclined.derivedStatus, equals(EventDerivedStatus.atRisk));

      final eventWithTentative = CalendarEvent(
        id: 'ev_risk_2',
        title: 'Reunião com Síndico',
        startTime: DateTime(2026, 10, 19, 19),
        endTime: DateTime(2026, 10, 19, 21),
        createdByMemberId: 'm1',
        participants: const [
          EventParticipant(
            id: 'p1',
            eventId: 'ev_risk_2',
            memberId: 'm1',
            memberName: 'Carlos',
            role: ParticipantRole.required,
            rsvpStatus: RsvpStatus.accepted,
          ),
          EventParticipant(
            id: 'p2',
            eventId: 'ev_risk_2',
            memberId: 'm2',
            memberName: 'Marina',
            role: ParticipantRole.required,
            rsvpStatus: RsvpStatus.tentative, // Respondeu talvez
          ),
        ],
      );

      expect(eventWithTentative.derivedStatus, equals(EventDerivedStatus.atRisk));
    });

    test('RN01: Evento fica Aguardando quando há Necessário pendente', () {
      final eventWaiting = CalendarEvent(
        id: 'ev_waiting',
        title: 'Dedetização',
        startTime: DateTime(2026, 10, 20, 10),
        endTime: DateTime(2026, 10, 20, 14),
        createdByMemberId: 'm1',
        participants: const [
          EventParticipant(
            id: 'p1',
            eventId: 'ev_waiting',
            memberId: 'm1',
            memberName: 'Carlos',
            role: ParticipantRole.required,
            rsvpStatus: RsvpStatus.accepted,
          ),
          EventParticipant(
            id: 'p2',
            eventId: 'ev_waiting',
            memberId: 'm2',
            memberName: 'Marina',
            role: ParticipantRole.required,
            rsvpStatus: RsvpStatus.pending, // Pendente
          ),
        ],
      );

      expect(eventWaiting.derivedStatus, equals(EventDerivedStatus.waiting));
    });

    test('Interação de RSVP atualiza participante e recalcula status derivado', () async {
      // event_2 na mockDataSource está Aguardando (Marina aceitou, Carlos pendente)
      var events = await repository.getEvents();
      var event2 = events.firstWhere((e) => e.id == 'event_2');
      expect(event2.derivedStatus, equals(EventDerivedStatus.waiting));

      // Carlos responde Aceitando
      await repository.updateRsvp(
        eventId: 'event_2',
        memberId: 'member_carlos',
        status: RsvpStatus.accepted,
      );

      events = await repository.getEvents();
      event2 = events.firstWhere((e) => e.id == 'event_2');
      // Agora ambos aceitaram, passa para Confirmado!
      expect(event2.derivedStatus, equals(EventDerivedStatus.confirmed));
    });

    test('Tarefas: Concluir e desmarcar tarefa atualiza completion state', () async {
      var tasks = await repository.getTasks();
      final task1 = tasks.firstWhere((t) => t.id == 'task_1');
      expect(task1.isCompleted, isFalse);

      await repository.toggleTaskComplete(
        taskId: 'task_1',
        completedByMemberId: 'member_carlos',
      );

      tasks = await repository.getTasks();
      final updatedTask1 = tasks.firstWhere((t) => t.id == 'task_1');
      expect(updatedTask1.isCompleted, isTrue);
      expect(updatedTask1.completedByMemberId, equals('member_carlos'));
      expect(updatedTask1.completedAt, isNotNull);
    });

    test('Tarefas: isOverdue é verdadeiro quando vencida e não concluída', () {
      final overdueTask = TaskItem(
        id: 't_overdue',
        title: 'Pagar conta de água',
        dueDate: DateTime.now().subtract(const Duration(days: 2)),
        isCompleted: false,
        createdByMemberId: 'm1',
        createdAt: DateTime.now().subtract(const Duration(days: 5)),
      );

      expect(overdueTask.isOverdue, isTrue);

      final completedPastTask = overdueTask.copyWith(isCompleted: true);
      expect(completedPastTask.isOverdue, isFalse);
    });
  });
}
