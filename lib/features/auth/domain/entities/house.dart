import 'package:equatable/equatable.dart';

class House extends Equatable {
  final String id;
  final String name;
  final int cycleStartDay;
  final String timezone;
  final String? createdBy;

  const House({
    required this.id,
    required this.name,
    this.cycleStartDay = 5,
    this.timezone = 'America/Sao_Paulo',
    this.createdBy,
  });

  House copyWith({
    String? id,
    String? name,
    int? cycleStartDay,
    String? timezone,
    String? createdBy,
  }) {
    return House(
      id: id ?? this.id,
      name: name ?? this.name,
      cycleStartDay: cycleStartDay ?? this.cycleStartDay,
      timezone: timezone ?? this.timezone,
      createdBy: createdBy ?? this.createdBy,
    );
  }

  @override
  List<Object?> get props => [id, name, cycleStartDay, timezone, createdBy];
}
