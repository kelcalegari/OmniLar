import 'package:equatable/equatable.dart';

import 'app_notification.dart';

/// Como o morador quer receber os avisos de um grupo.
class GroupPreference extends Equatable {
  /// Aparece no sino. Desligado, só os avisos essenciais chegam.
  final bool inApp;

  /// Chega como push neste e nos outros aparelhos do morador.
  final bool push;

  const GroupPreference({this.inApp = true, this.push = true});

  GroupPreference copyWith({bool? inApp, bool? push}) =>
      GroupPreference(inApp: inApp ?? this.inApp, push: push ?? this.push);

  @override
  List<Object?> get props => [inApp, push];
}

/// Preferências de notificação do morador (tabelas `notification_preferences`,
/// por casa e grupo, e `notification_settings`, gerais).
class NotificationPreferences extends Equatable {
  /// Grupos que o morador pode ajustar (a categoria `conta` é sempre essencial).
  static const groups = [
    NotificationCategory.despesas,
    NotificationCategory.fechamento,
    NotificationCategory.emprestimos,
    NotificationCategory.caixinhas,
    NotificationCategory.compras,
    NotificationCategory.tarefas,
    NotificationCategory.agenda,
    NotificationCategory.projetos,
    NotificationCategory.casa,
    NotificationCategory.assistente,
  ];

  /// Grupos com preferência gravada; os que faltam valem o padrão (tudo ligado).
  final Map<NotificationCategory, GroupPreference> byGroup;

  /// Horário silencioso (hora e minuto); sem os dois, não há horário silencioso.
  final ({int hour, int minute})? quietStart;
  final ({int hour, int minute})? quietEnd;
  final bool hideAmounts;
  final bool weeklySummary;

  const NotificationPreferences({
    this.byGroup = const {},
    this.quietStart,
    this.quietEnd,
    this.hideAmounts = false,
    this.weeklySummary = true,
  });

  GroupPreference of(NotificationCategory group) => byGroup[group] ?? const GroupPreference();

  bool get hasQuietHours => quietStart != null && quietEnd != null;

  NotificationPreferences withGroup(NotificationCategory group, GroupPreference preference) =>
      NotificationPreferences(
        byGroup: {...byGroup, group: preference},
        quietStart: quietStart,
        quietEnd: quietEnd,
        hideAmounts: hideAmounts,
        weeklySummary: weeklySummary,
      );

  NotificationPreferences withSettings({
    ({int hour, int minute})? quietStart,
    ({int hour, int minute})? quietEnd,
    bool clearQuietHours = false,
    bool? hideAmounts,
    bool? weeklySummary,
  }) =>
      NotificationPreferences(
        byGroup: byGroup,
        quietStart: clearQuietHours ? null : quietStart ?? this.quietStart,
        quietEnd: clearQuietHours ? null : quietEnd ?? this.quietEnd,
        hideAmounts: hideAmounts ?? this.hideAmounts,
        weeklySummary: weeklySummary ?? this.weeklySummary,
      );

  /// Nome do grupo na tela.
  static String labelOf(NotificationCategory group) => switch (group) {
        NotificationCategory.despesas => 'Despesas e contas',
        NotificationCategory.fechamento => 'Fechamento do ciclo',
        NotificationCategory.emprestimos => 'Empréstimos',
        NotificationCategory.caixinhas => 'Caixinhas',
        NotificationCategory.compras => 'Compras',
        NotificationCategory.tarefas => 'Tarefas',
        NotificationCategory.agenda => 'Agenda',
        NotificationCategory.projetos => 'Projetos',
        NotificationCategory.casa => 'Casa e moradores',
        NotificationCategory.assistente => 'Alertas de gasto',
        NotificationCategory.conta => 'Conta',
      };

  @override
  List<Object?> get props => [byGroup, quietStart, quietEnd, hideAmounts, weeklySummary];
}
