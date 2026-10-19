/// Quem pode ler a renda mensal dos moradores (coluna `houses.income_visibility`, 0102).
enum IncomeVisibility {
  /// Todos os moradores veem a renda de todos.
  all('all'),

  /// Só os administradores veem a renda dos outros.
  admins('admins'),

  /// Cada um vê só a própria renda (padrão).
  self('self');

  final String dbValue;
  const IncomeVisibility(this.dbValue);

  /// Valor desconhecido vale o mais restrito (cada um vê só a sua).
  static IncomeVisibility fromDb(Object? value) {
    for (final v in values) {
      if (v.dbValue == value) return v;
    }
    return self;
  }

  String get label => switch (this) {
        IncomeVisibility.all => 'Todos os moradores',
        IncomeVisibility.admins => 'Só administradores',
        IncomeVisibility.self => 'Cada um vê só a sua',
      };

  String get description => switch (this) {
        IncomeVisibility.all => 'Todos veem a renda de todos.',
        IncomeVisibility.admins => 'Administradores veem a renda de todos; os demais, só a própria.',
        IncomeVisibility.self => 'Ninguém vê a renda dos outros, nem os administradores. Só o percentual calculado aparece.',
      };

  /// Se quem tem esse papel pode ler a renda dos outros moradores.
  bool canSeeOthers({required bool isAdmin}) => switch (this) {
        IncomeVisibility.all => true,
        IncomeVisibility.admins => isAdmin,
        IncomeVisibility.self => false,
      };
}

/// Base do rateio padrão da casa (coluna `houses.split_basis`, 0102).
enum SplitBasis {
  /// Percentuais definidos à mão nos Modelos de Rateio (padrão).
  manual('manual'),

  /// Proporcional à renda informada pelos moradores.
  income('income');

  final String dbValue;
  const SplitBasis(this.dbValue);

  static SplitBasis fromDb(Object? value) => value == 'income' ? income : manual;

  String get label => switch (this) {
        SplitBasis.manual => 'Percentuais definidos à mão',
        SplitBasis.income => 'Proporcional à renda',
      };
}

/// Cálculo e privacidade da divisão por renda. Espelha o banco (0102).
class IncomeSplit {
  const IncomeSplit._();

  /// Percentuais (duas casas, somando 100) proporcionais às rendas. Nulo
  /// quando algum morador ativo não informou renda: vale o rateio atual. A
  /// sobra do arredondamento vai a quem ganha mais (empate: o primeiro da lista).
  static Map<String, double>? compute(Map<String, int> incomeCentsByMember, List<String> activeMemberIds) {
    if (activeMemberIds.isEmpty) return null;
    var total = 0;
    for (final id in activeMemberIds) {
      final cents = incomeCentsByMember[id];
      if (cents == null || cents <= 0) return null;
      total += cents;
    }
    final percents = <String, int>{
      for (final id in activeMemberIds) id: (incomeCentsByMember[id]! * 10000 / total).round(),
    };
    final diff = 10000 - percents.values.fold<int>(0, (a, b) => a + b);
    if (diff != 0) {
      var top = activeMemberIds.first;
      for (final id in activeMemberIds) {
        if (incomeCentsByMember[id]! > incomeCentsByMember[top]!) top = id;
      }
      percents[top] = percents[top]! + diff;
    }
    return {for (final e in percents.entries) e.key: e.value / 100};
  }

  /// Rendas que [viewerId] pode ler: a própria sempre; as dos outros só se a
  /// visibilidade da casa permitir. Mesma regra da policy de `member_incomes`.
  static Map<String, int> visibleTo({
    required Map<String, int> all,
    required String viewerId,
    required bool viewerIsAdmin,
    required IncomeVisibility visibility,
  }) {
    if (visibility.canSeeOthers(isAdmin: viewerIsAdmin)) return Map.of(all);
    return {
      for (final e in all.entries)
        if (e.key == viewerId) e.key: e.value,
    };
  }
}
