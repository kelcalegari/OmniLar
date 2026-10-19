import 'package:equatable/equatable.dart';

/// Ações da casa que exigem administrador por padrão e que a casa pode abrir
/// para todos os moradores ou para moradores escolhidos (`houses.permissions`,
/// 0103). Os nomes do banco são estáveis.
enum HousePermissionAction {
  editConfigurations('editar_configuracoes', 'Mudar os ajustes da casa',
      'Regras de rateio, fechamento, Fôlego, alertas, importação, nomes e demais parâmetros.'),
  closeCycle('fechar_ciclo', 'Fechar o ciclo', 'Confirmar o fechamento e salvar o resumo do ciclo.'),
  reopenCycle('reabrir_ciclo', 'Reabrir um ciclo fechado', 'Desfazer o fechamento de um ciclo.'),
  changeCycleDay('mudar_dia_do_ciclo', 'Mudar o dia do ciclo', 'Trocar o dia em que o ciclo financeiro começa.'),
  manageCategories('gerenciar_categorias', 'Apagar categorias com despesas',
      'Apagar uma categoria movendo ou apagando as despesas dela.'),
  houseLoans('emprestimos_da_casa', 'Emprestar do Caixa da Casa',
      'Criar empréstimo com o dinheiro do Caixa ou de uma caixinha.'),
  initialBalance('saldo_inicial', 'Informar o saldo inicial', 'Lançar o dinheiro que a casa já tinha ao começar.'),
  adjustQuotas('ajustar_aportes', 'Ajustar a cota das caixinhas',
      'Definir a meta mensal da caixinha dentro do planejamento de aportes.');

  final String dbValue;
  final String label;
  final String description;
  const HousePermissionAction(this.dbValue, this.label, this.description);

  static HousePermissionAction? fromDb(Object? value) {
    for (final action in values) {
      if (action.dbValue == value) return action;
    }
    return null;
  }
}

/// Quem pode fazer uma ação.
enum PermissionLevel {
  admins('admins', 'Só administradores'),
  all('all', 'Todos os moradores'),
  chosen('chosen', 'Moradores escolhidos');

  final String dbValue;
  final String label;
  const PermissionLevel(this.dbValue, this.label);

  static PermissionLevel? fromDb(Object? value) {
    for (final level in values) {
      if (level.dbValue == value) return level;
    }
    return null;
  }
}

/// Nível de uma ação e, no nível "escolhidos", quem pode.
class ActionPermission extends Equatable {
  static const int maxMembers = 50;
  static const admins = ActionPermission(PermissionLevel.admins);

  final PermissionLevel level;

  /// Só vale com [PermissionLevel.chosen].
  final List<String> members;

  const ActionPermission(this.level, {this.members = const []});

  Map<String, dynamic> toJson() => {
        'level': level.dbValue,
        if (level == PermissionLevel.chosen) 'members': members,
      };

  @override
  List<Object?> get props => [level, members];
}

/// Permissões por ação da casa. Ação sem configuração = só administradores
/// (o comportamento de antes); administradores sempre podem tudo.
class HousePermissions extends Equatable {
  final Map<HousePermissionAction, ActionPermission> byAction;

  const HousePermissions([this.byAction = const {}]);

  /// Lê o jsonb do banco; ação ou nível desconhecido vale "só administradores".
  factory HousePermissions.fromJson(Object? json) {
    if (json is! Map) return const HousePermissions();
    final parsed = <HousePermissionAction, ActionPermission>{};
    for (final entry in json.entries) {
      final action = HousePermissionAction.fromDb(entry.key);
      final value = entry.value;
      if (action == null || value is! Map) continue;
      final level = PermissionLevel.fromDb(value['level']);
      if (level == null || level == PermissionLevel.admins) continue;
      final members = <String>[];
      if (level == PermissionLevel.chosen) {
        final raw = value['members'];
        if (raw is List) {
          for (final m in raw) {
            if (m is String && !members.contains(m)) members.add(m);
          }
        }
      }
      parsed[action] = ActionPermission(level, members: members);
    }
    return HousePermissions(parsed);
  }

  /// Só o que foge do padrão vai ao banco.
  Map<String, dynamic> toJson() => {
        for (final e in byAction.entries)
          if (e.value.level != PermissionLevel.admins) e.key.dbValue: e.value.toJson(),
      };

  bool get isEmpty => toJson().isEmpty;

  ActionPermission of(HousePermissionAction action) => byAction[action] ?? ActionPermission.admins;

  /// Como o banco (`has_house_permission`): administrador sempre pode; os
  /// demais seguem o nível da ação.
  bool allows(HousePermissionAction action, {required bool isAdmin, String? memberId}) {
    if (isAdmin) return true;
    final permission = of(action);
    return switch (permission.level) {
      PermissionLevel.admins => false,
      PermissionLevel.all => true,
      PermissionLevel.chosen => memberId != null && permission.members.contains(memberId),
    };
  }

  HousePermissions withAction(HousePermissionAction action, ActionPermission permission) =>
      HousePermissions({...byAction, action: permission});

  @override
  List<Object?> get props => [toJson()];
}
