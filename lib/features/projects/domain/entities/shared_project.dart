import 'package:equatable/equatable.dart';
import '../../../../core/domain/value_objects/money.dart';
import 'project_participant.dart';

enum ProjectType {
  trip, // Viagem / Férias / Fim de semana
  assetPurchase, // Compra de Imóvel, Veículo, Obras ou Reforma
  investment, // Investimento Coletivo, Poupança / Fundo de Oportunidade
  event, // Festa, Churrasco, Comemoração
  generic, // Outros projetos colaborativos
}

enum ProjectStatus {
  planning,
  active,
  settled,
  archived,
}

class SharedProject extends Equatable {
  final String id;
  final String houseId;
  final String title;
  final String? description;
  final ProjectType type;
  final Money? targetBudget;
  final ProjectStatus status;
  final DateTime? startDate;
  final DateTime? endDate;
  final String currency;
  final String? vaultId; // ID da Caixinha / Cofre vinculada (SavingsVault)
  final List<ProjectParticipant> participants;
  final String createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  const SharedProject({
    required this.id,
    required this.houseId,
    required this.title,
    this.description,
    this.type = ProjectType.trip,
    this.targetBudget,
    this.status = ProjectStatus.active,
    this.startDate,
    this.endDate,
    this.currency = 'BRL',
    this.vaultId,
    this.participants = const [],
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isActive => status == ProjectStatus.active;
  bool get isSettled => status == ProjectStatus.settled;

  /// Retorna o percentual de orçamento consumido para um total de gastos realizado
  double budgetProgressPercent(Money totalSpent) {
    if (targetBudget == null || targetBudget!.cents <= 0) return 0.0;
    return (totalSpent.cents / targetBudget!.cents).clamp(0.0, 1.0);
  }

  /// Retorna se o orçamento estourou
  bool isOverBudget(Money totalSpent) {
    if (targetBudget == null || targetBudget!.cents <= 0) return false;
    return totalSpent.cents > targetBudget!.cents;
  }

  SharedProject copyWith({
    String? id,
    String? houseId,
    String? title,
    String? description,
    ProjectType? type,
    Money? targetBudget,
    ProjectStatus? status,
    DateTime? startDate,
    DateTime? endDate,
    String? currency,
    String? vaultId,
    bool clearVaultId = false,
    List<ProjectParticipant>? participants,
    String? createdBy,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return SharedProject(
      id: id ?? this.id,
      houseId: houseId ?? this.houseId,
      title: title ?? this.title,
      description: description ?? this.description,
      type: type ?? this.type,
      targetBudget: targetBudget ?? this.targetBudget,
      status: status ?? this.status,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      currency: currency ?? this.currency,
      vaultId: clearVaultId ? null : (vaultId ?? this.vaultId),
      participants: participants ?? this.participants,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  List<Object?> get props => [
        id,
        houseId,
        title,
        description,
        type,
        targetBudget,
        status,
        startDate,
        endDate,
        currency,
        vaultId,
        participants,
        createdBy,
        createdAt,
        updatedAt,
      ];
}
