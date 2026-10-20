import '../../../../core/domain/value_objects/cycle_schedule.dart';
import 'package:equatable/equatable.dart';

class House extends Equatable {
  final String id;
  final String name;
  final int cycleStartDay;

  /// Trocas do dia de início do ciclo (da mais antiga para a mais recente).
  final List<CycleDayChange> cycleDayChanges;

  /// Mínimo de dias do ciclo de transição na troca do dia (houses.folego_params, 0098).
  final int transitionMinDays;
  final String timezone;
  final String? createdBy;
  final String? pixKey;
  final String? pixKeyType;
  final String? pixKeyHolderName;
  final String? pixKeyBank;
  final DateTime? archivedAt;

  const House({
    required this.id,
    required this.name,
    this.cycleStartDay = 5,
    this.cycleDayChanges = const [],
    this.transitionMinDays = CycleSchedule.defaultTransitionDays,
    this.timezone = 'America/Sao_Paulo',
    this.createdBy,
    this.pixKey,
    this.pixKeyType,
    this.pixKeyHolderName,
    this.pixKeyBank,
    this.archivedAt,
  });

  bool get isArchived => archivedAt != null;

  /// Calendário de ciclos da casa, já com as trocas de dia.
  CycleSchedule get cycleSchedule => CycleSchedule(cycleStartDay, cycleDayChanges, transitionMinDays);

  House copyWith({
    String? id,
    String? name,
    int? cycleStartDay,
    List<CycleDayChange>? cycleDayChanges,
    int? transitionMinDays,
    String? timezone,
    String? createdBy,
    String? pixKey,
    String? pixKeyType,
    String? pixKeyHolderName,
    String? pixKeyBank,
    bool clearPixKey = false,
    DateTime? archivedAt,
    bool clearArchivedAt = false,
  }) {
    return House(
      id: id ?? this.id,
      name: name ?? this.name,
      cycleStartDay: cycleStartDay ?? this.cycleStartDay,
      cycleDayChanges: cycleDayChanges ?? this.cycleDayChanges,
      transitionMinDays: transitionMinDays ?? this.transitionMinDays,
      timezone: timezone ?? this.timezone,
      createdBy: createdBy ?? this.createdBy,
      pixKey: clearPixKey ? null : (pixKey ?? this.pixKey),
      pixKeyType: clearPixKey ? null : (pixKeyType ?? this.pixKeyType),
      pixKeyHolderName: clearPixKey ? null : (pixKeyHolderName ?? this.pixKeyHolderName),
      pixKeyBank: clearPixKey ? null : (pixKeyBank ?? this.pixKeyBank),
      archivedAt: clearArchivedAt ? null : (archivedAt ?? this.archivedAt),
    );
  }

  @override
  List<Object?> get props => [
        id,
        name,
        cycleStartDay,
        cycleDayChanges,
        transitionMinDays,
        timezone,
        createdBy,
        pixKey,
        pixKeyType,
        pixKeyHolderName,
        pixKeyBank,
        archivedAt,
      ];
}
