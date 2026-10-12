import 'package:equatable/equatable.dart';

class House extends Equatable {
  final String id;
  final String name;
  final int cycleStartDay;
  final String timezone;
  final String? createdBy;
  final String? pixKey;
  final String? pixKeyType;
  final String? pixKeyHolderName;
  final String? pixKeyBank;

  const House({
    required this.id,
    required this.name,
    this.cycleStartDay = 5,
    this.timezone = 'America/Sao_Paulo',
    this.createdBy,
    this.pixKey,
    this.pixKeyType,
    this.pixKeyHolderName,
    this.pixKeyBank,
  });

  House copyWith({
    String? id,
    String? name,
    int? cycleStartDay,
    String? timezone,
    String? createdBy,
    String? pixKey,
    String? pixKeyType,
    String? pixKeyHolderName,
    String? pixKeyBank,
    bool clearPixKey = false,
  }) {
    return House(
      id: id ?? this.id,
      name: name ?? this.name,
      cycleStartDay: cycleStartDay ?? this.cycleStartDay,
      timezone: timezone ?? this.timezone,
      createdBy: createdBy ?? this.createdBy,
      pixKey: clearPixKey ? null : (pixKey ?? this.pixKey),
      pixKeyType: clearPixKey ? null : (pixKeyType ?? this.pixKeyType),
      pixKeyHolderName: clearPixKey ? null : (pixKeyHolderName ?? this.pixKeyHolderName),
      pixKeyBank: clearPixKey ? null : (pixKeyBank ?? this.pixKeyBank),
    );
  }

  @override
  List<Object?> get props => [
        id,
        name,
        cycleStartDay,
        timezone,
        createdBy,
        pixKey,
        pixKeyType,
        pixKeyHolderName,
        pixKeyBank,
      ];
}
