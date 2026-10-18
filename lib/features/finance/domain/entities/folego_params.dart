import 'package:equatable/equatable.dart';

import '../../../../core/domain/value_objects/cycle_schedule.dart';

/// Limites do Fôlego, das contas recorrentes e da transição do dia do ciclo
/// (coluna `houses.folego_params`, 0098). Chave ausente vale o padrão, que é o
/// que o app sempre usou.
class FolegoParams extends Equatable {
  static const int defaultWarningPercent = 15;
  static const int defaultCommitmentWarningPercent = 65;
  static const int defaultCommitmentDangerPercent = 85;
  static const int defaultComfortableDailyCents = 5000;
  static const int defaultRecurringHorizonMonths = 3;
  static const int defaultTransitionMinDays = CycleSchedule.defaultTransitionDays;

  /// Fôlego abaixo desta % dos aportes do ciclo = atenção.
  final int warningPercent;

  /// A barra de comprometimento passa a atenção acima desta %...
  final int commitmentWarningPercent;

  /// ...e a crítica acima desta.
  final int commitmentDangerPercent;

  /// Gasto diário seguro (centavos) a partir do qual o selo é confortável.
  final int comfortableDailyCents;

  /// Até quantos meses à frente nascem as contas recorrentes (1 a 6).
  final int recurringHorizonMonths;

  /// Mínimo de dias do ciclo de transição na troca do dia de início (15 a 30).
  final int transitionMinDays;

  const FolegoParams({
    this.warningPercent = defaultWarningPercent,
    this.commitmentWarningPercent = defaultCommitmentWarningPercent,
    this.commitmentDangerPercent = defaultCommitmentDangerPercent,
    this.comfortableDailyCents = defaultComfortableDailyCents,
    this.recurringHorizonMonths = defaultRecurringHorizonMonths,
    this.transitionMinDays = defaultTransitionMinDays,
  });

  /// Valor ausente, fora da faixa ou incoerente cai no padrão (como o banco
  /// recusaria gravar).
  factory FolegoParams.fromJson(Object? json) {
    if (json is! Map) return const FolegoParams();
    int pick(String key, int min, int max, int fallback) {
      final raw = json[key];
      if (raw is! num || raw != raw.truncate()) return fallback;
      final value = raw.toInt();
      return value >= min && value <= max ? value : fallback;
    }

    final warning = pick('commitment_warning_percent', 0, 100, defaultCommitmentWarningPercent);
    final danger = pick('commitment_danger_percent', 0, 100, defaultCommitmentDangerPercent);
    final coherent = warning < danger;
    return FolegoParams(
      warningPercent: pick('warning_percent', 0, 100, defaultWarningPercent),
      commitmentWarningPercent: coherent ? warning : defaultCommitmentWarningPercent,
      commitmentDangerPercent: coherent ? danger : defaultCommitmentDangerPercent,
      comfortableDailyCents: pick('comfortable_daily_cents', 0, 100000000, defaultComfortableDailyCents),
      recurringHorizonMonths: pick('recurring_horizon_months', 1, 6, defaultRecurringHorizonMonths),
      transitionMinDays: pick('transition_min_days', 15, 30, defaultTransitionMinDays),
    );
  }

  /// Objeto inteiro: o banco troca o objeto todo.
  Map<String, dynamic> toJson() => {
        'warning_percent': warningPercent,
        'commitment_warning_percent': commitmentWarningPercent,
        'commitment_danger_percent': commitmentDangerPercent,
        'comfortable_daily_cents': comfortableDailyCents,
        'recurring_horizon_months': recurringHorizonMonths,
        'transition_min_days': transitionMinDays,
      };

  /// Mesmo teste do banco (folego_params_valid), para avisar antes de gravar.
  bool get isValid =>
      warningPercent >= 0 &&
      warningPercent <= 100 &&
      commitmentWarningPercent >= 0 &&
      commitmentDangerPercent <= 100 &&
      commitmentWarningPercent < commitmentDangerPercent &&
      comfortableDailyCents >= 0 &&
      recurringHorizonMonths >= 1 &&
      recurringHorizonMonths <= 6 &&
      transitionMinDays >= 15 &&
      transitionMinDays <= 30;

  FolegoParams copyWith({
    int? warningPercent,
    int? commitmentWarningPercent,
    int? commitmentDangerPercent,
    int? comfortableDailyCents,
    int? recurringHorizonMonths,
    int? transitionMinDays,
  }) =>
      FolegoParams(
        warningPercent: warningPercent ?? this.warningPercent,
        commitmentWarningPercent: commitmentWarningPercent ?? this.commitmentWarningPercent,
        commitmentDangerPercent: commitmentDangerPercent ?? this.commitmentDangerPercent,
        comfortableDailyCents: comfortableDailyCents ?? this.comfortableDailyCents,
        recurringHorizonMonths: recurringHorizonMonths ?? this.recurringHorizonMonths,
        transitionMinDays: transitionMinDays ?? this.transitionMinDays,
      );

  @override
  List<Object?> get props => [
        warningPercent,
        commitmentWarningPercent,
        commitmentDangerPercent,
        comfortableDailyCents,
        recurringHorizonMonths,
        transitionMinDays,
      ];
}
