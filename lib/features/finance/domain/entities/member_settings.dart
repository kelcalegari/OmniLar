import 'package:equatable/equatable.dart';

/// Quem paga uma despesa nova, pelo padrão do morador.
enum LaunchPayer {
  /// O próprio morador que lança.
  me,

  /// O Caixa da casa (a conta conjunta).
  house,
}

/// Ajustes de um morador em uma casa (tabela `member_settings`, 0095). O
/// objeto é genérico: o app guarda o que não conhece como veio, para não
/// apagar o que outra versão gravou. Por enquanto só os padrões de lançamento.
class MemberSettings extends Equatable {
  static const launchPayerKey = 'launch_payer';
  static const launchPaymentMethodKey = 'launch_payment_method_id';
  static const launchCategoryKey = 'launch_category_id';

  /// Hora (0 a 23, fuso da casa) a partir da qual chegam os lembretes do dia (0099).
  static const alertHourKey = 'alert_hour';

  /// Grupos de lembrete silenciados (0099).
  static const mutedRemindersKey = 'muted_reminders';

  /// Dia (0 = domingo a 6) e hora do resumo semanal (0099).
  static const weeklyDayKey = 'weekly_day';
  static const weeklyHourKey = 'weekly_hour';

  static const int defaultAlertHour = 9;
  static const int defaultWeeklyDay = 0;
  static const int defaultWeeklyHour = 18;

  /// Grupos de lembrete do dia que cada morador pode silenciar.
  static const List<String> reminderGroups = ['bills', 'invoices', 'cycle', 'loans', 'tasks', 'budget'];

  final Map<String, dynamic> values;

  const MemberSettings([this.values = const {}]);

  factory MemberSettings.fromJson(Object? json) =>
      json is Map ? MemberSettings(Map<String, dynamic>.from(json)) : const MemberSettings();

  Map<String, dynamic> toJson() => Map<String, dynamic>.of(values);

  String? _text(String key) {
    final value = values[key];
    return value is String && value.isNotEmpty ? value : null;
  }

  /// Quem paga por padrão (null = eu, sem escolha própria).
  LaunchPayer? get launchPayer => switch (values[launchPayerKey]) {
        'me' => LaunchPayer.me,
        'house' => LaunchPayer.house,
        _ => null,
      };

  /// Forma de pagamento fixa (null = a última usada).
  String? get launchPaymentMethodId => _text(launchPaymentMethodKey);

  /// Categoria fixa (null = a mais usada).
  String? get launchCategoryId => _text(launchCategoryKey);

  int _int(String key, int min, int max, int fallback) {
    final value = values[key];
    return value is num && value == value.truncate() && value >= min && value <= max ? value.toInt() : fallback;
  }

  /// A partir de que hora chegam os lembretes do dia (padrão 9).
  int get alertHour => _int(alertHourKey, 0, 23, defaultAlertHour);

  /// Dia do resumo semanal, 0 = domingo (padrão).
  int get weeklyDay => _int(weeklyDayKey, 0, 6, defaultWeeklyDay);

  /// Hora do resumo semanal (padrão 18).
  int get weeklyHour => _int(weeklyHourKey, 0, 23, defaultWeeklyHour);

  /// Grupos silenciados (nenhum, sem escolha).
  Set<String> get mutedReminders {
    final value = values[mutedRemindersKey];
    if (value is! List) return const {};
    return {for (final g in value) if (g is String && reminderGroups.contains(g)) g};
  }

  /// Horário e lembretes escolhidos em Ajustes; o padrão não fica gravado.
  MemberSettings withAlertPrefs({
    required int alertHour,
    required Set<String> muted,
    required int weeklyDay,
    required int weeklyHour,
  }) =>
      withValues({
        alertHourKey: alertHour == defaultAlertHour ? null : alertHour,
        mutedRemindersKey: muted.isEmpty ? null : [for (final g in reminderGroups) if (muted.contains(g)) g],
        weeklyDayKey: weeklyDay == defaultWeeklyDay ? null : weeklyDay,
        weeklyHourKey: weeklyHour == defaultWeeklyHour ? null : weeklyHour,
      });

  /// Cópia com [changes]; valor null tira a chave.
  MemberSettings withValues(Map<String, Object?> changes) {
    final next = Map<String, dynamic>.of(values);
    changes.forEach((key, value) => value == null ? next.remove(key) : next[key] = value);
    return MemberSettings(next);
  }

  /// Os três padrões escolhidos em Ajustes (null = o automático de cada um).
  MemberSettings withLaunchDefaults({
    required LaunchPayer? payer,
    required String? paymentMethodId,
    required String? categoryId,
  }) =>
      withValues({
        launchPayerKey: payer?.name,
        launchPaymentMethodKey: paymentMethodId,
        launchCategoryKey: categoryId,
      });

  @override
  List<Object?> get props => [values];
}
