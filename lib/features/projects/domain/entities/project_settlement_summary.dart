import 'package:equatable/equatable.dart';
import '../../../../core/domain/value_objects/money.dart';
import '../../../settlement/domain/entities/super_pix_transfer.dart';
import 'shared_project.dart';

class ParticipantProjectBalance extends Equatable {
  final String participantId;
  final String participantName;
  final Money totalPaid; // Total desembolsado por este participante
  final Money totalShareDue; // Total de responsabilidade proporcional nos gastos
  final Money netBalance; // totalPaid - totalShareDue (positivo = credor, negativo = devedor)

  const ParticipantProjectBalance({
    required this.participantId,
    required this.participantName,
    required this.totalPaid,
    required this.totalShareDue,
    required this.netBalance,
  });

  bool get isCreditor => netBalance.cents > 0;
  bool get isDebtor => netBalance.cents < 0;
  bool get isSettled => netBalance.cents == 0;

  @override
  List<Object?> get props => [participantId, participantName, totalPaid, totalShareDue, netBalance];
}

class ProjectSettlementSummary extends Equatable {
  final SharedProject project;
  final Money totalExpenses;
  final List<ParticipantProjectBalance> participantBalances;
  final List<SuperPixTransfer> transfers;

  const ProjectSettlementSummary({
    required this.project,
    required this.totalExpenses,
    required this.participantBalances,
    required this.transfers,
  });

  @override
  List<Object?> get props => [project, totalExpenses, participantBalances, transfers];
}
