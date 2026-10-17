import 'package:equatable/equatable.dart';

class UserProfile extends Equatable {
  final String id;
  final String email;
  final String fullName;
  final String? avatarUrl;
  final String? phone;
  final String? pixKey;

  /// Versão dos Termos e da Política aceita (migration 0085).
  final String? termsVersion;

  /// Quando a pessoa permitiu a leitura por IA; null = não permitiu ou retirou.
  final DateTime? aiConsentAt;

  /// O perfil veio do banco: só então dá para saber se falta o aceite (sem
  /// perfil, por falha de rede, ninguém é mandado para a tela de aceite).
  final bool legalStatusKnown;

  const UserProfile({
    required this.id,
    required this.email,
    required this.fullName,
    this.avatarUrl,
    this.phone,
    this.pixKey,
    this.termsVersion,
    this.aiConsentAt,
    this.legalStatusKnown = false,
  });

  bool get hasAiConsent => aiConsentAt != null;

  /// Falta aceitar a versão [currentVersion] dos Termos e da Política.
  bool needsTermsAcceptance(String currentVersion) => legalStatusKnown && termsVersion != currentVersion;

  UserProfile copyWith({
    String? id,
    String? email,
    String? fullName,
    String? avatarUrl,
    String? phone,
    String? pixKey,
    String? termsVersion,
    DateTime? aiConsentAt,
    bool clearAiConsent = false,
    bool? legalStatusKnown,
  }) {
    return UserProfile(
      id: id ?? this.id,
      email: email ?? this.email,
      fullName: fullName ?? this.fullName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      phone: phone ?? this.phone,
      pixKey: pixKey ?? this.pixKey,
      termsVersion: termsVersion ?? this.termsVersion,
      aiConsentAt: clearAiConsent ? null : aiConsentAt ?? this.aiConsentAt,
      legalStatusKnown: legalStatusKnown ?? this.legalStatusKnown,
    );
  }

  @override
  List<Object?> get props =>
      [id, email, fullName, avatarUrl, phone, pixKey, termsVersion, aiConsentAt, legalStatusKnown];
}
