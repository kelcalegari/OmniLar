import 'package:equatable/equatable.dart';

import '../../../../core/domain/value_objects/money.dart';
import 'cycle_funding_estimate.dart';

/// O que o dinheiro que já está no Caixa no início do ciclo (sobra do ciclo
/// anterior e pagamentos de empréstimo do Caixa que voltaram a ele) faz no
/// rateio. Vale para o planejador de aportes e para o fechamento.
enum OpeningBalanceRule {
  /// Abate o aporte de cada morador, pelo percentual padrão ou pelo valor fixo.
  reduceQuotas('reduce_quotas'),

  /// Só paga o que passar do valor fixo somado (casas com valor fixo). Na
  /// divisão por despesa não há excedente: fica no Caixa.
  coverExcess('cover_excess'),

  /// Não mexe no rateio: fica no Caixa como folga.
  keep('keep');

  final String dbValue;
  const OpeningBalanceRule(this.dbValue);

  static OpeningBalanceRule? fromDb(Object? value) {
    for (final rule in values) {
      if (rule.dbValue == value) return rule;
    }
    return null;
  }

  String get label => switch (this) {
        OpeningBalanceRule.reduceQuotas => 'Abater os aportes',
        OpeningBalanceRule.coverExcess => 'Cobrir só o excedente',
        OpeningBalanceRule.keep => 'Guardar como folga',
      };

  String get description => switch (this) {
        OpeningBalanceRule.reduceQuotas =>
          'Cada morador aporta menos, na proporção da sua parte.',
        OpeningBalanceRule.coverExcess =>
          'Paga só o que passar do valor fixo combinado. Na divisão por despesa, fica no Caixa.',
        OpeningBalanceRule.keep =>
          'Ninguém aporta menos: o dinheiro fica no Caixa para imprevistos.',
      };
}

/// Regra de cada tipo de dinheiro que já está no Caixa ou entra nele no ciclo
/// sem ser aporte (coluna `houses.opening_inflow_rules`, 0092). O que não
/// tiver escolha própria segue [HouseSettings.openingBalanceRule]; resgate de
/// caixinha sem escolha fica no Caixa como folga.
class OpeningInflowRules extends Equatable {
  /// Sobra do ciclo anterior.
  final OpeningBalanceRule? rolledSurplus;

  /// Empréstimo do Caixa pago de volta.
  final OpeningBalanceRule? houseLoansRepaid;

  /// Resgate de caixinha: padrão da casa, para caixinhas sem escolha própria.
  final OpeningBalanceRule? vaultWithdrawals;

  /// Resgate de caixinha por caixinha (id da caixinha -> regra).
  final Map<String, OpeningBalanceRule> vaultOverrides;

  /// Entrada de fora (reservado). Sem escolha, segue a sobra do ciclo anterior.
  final OpeningBalanceRule? thirdParty;

  const OpeningInflowRules({
    this.rolledSurplus,
    this.houseLoansRepaid,
    this.vaultWithdrawals,
    this.vaultOverrides = const {},
    this.thirdParty,
  });

  factory OpeningInflowRules.fromJson(Object? json) {
    if (json is! Map) return const OpeningInflowRules();
    final overrides = <String, OpeningBalanceRule>{};
    final rawOverrides = json['vault_overrides'];
    if (rawOverrides is Map) {
      for (final entry in rawOverrides.entries) {
        final rule = OpeningBalanceRule.fromDb(entry.value);
        if (rule != null) overrides[entry.key.toString()] = rule;
      }
    }
    return OpeningInflowRules(
      rolledSurplus: OpeningBalanceRule.fromDb(json['rolled_surplus']),
      houseLoansRepaid: OpeningBalanceRule.fromDb(json['house_loans_repaid']),
      vaultWithdrawals: OpeningBalanceRule.fromDb(json['vault_withdrawals']),
      vaultOverrides: overrides,
      thirdParty: OpeningBalanceRule.fromDb(json['third_party']),
    );
  }

  Map<String, dynamic> toJson() => {
        'rolled_surplus': ?rolledSurplus?.dbValue,
        'house_loans_repaid': ?houseLoansRepaid?.dbValue,
        'vault_withdrawals': ?vaultWithdrawals?.dbValue,
        if (vaultOverrides.isNotEmpty)
          'vault_overrides': {for (final e in vaultOverrides.entries) e.key: e.value.dbValue},
        'third_party': ?thirdParty?.dbValue,
      };

  bool get isEmpty =>
      rolledSurplus == null &&
      houseLoansRepaid == null &&
      vaultWithdrawals == null &&
      vaultOverrides.isEmpty &&
      thirdParty == null;

  OpeningBalanceRule? rolledSurplusRule(OpeningBalanceRule? fallback) => rolledSurplus ?? fallback;

  OpeningBalanceRule? houseLoansRepaidRule(OpeningBalanceRule? fallback) => houseLoansRepaid ?? fallback;

  /// Resgate nunca abate nada sem que a casa escolha.
  OpeningBalanceRule vaultRule(String vaultId) =>
      vaultOverrides[vaultId] ?? vaultWithdrawals ?? OpeningBalanceRule.keep;

  OpeningBalanceRule? thirdPartyRule(OpeningBalanceRule? fallback) => thirdParty ?? rolledSurplusRule(fallback);

  @override
  List<Object?> get props => [rolledSurplus, houseLoansRepaid, vaultWithdrawals, vaultOverrides, thirdParty];
}

/// Configurações de planejamento e fechamento da casa (colunas de `houses`, 0091).
class HouseSettings extends Equatable {
  static const int defaultHistoryCycles = 3;
  static const int defaultAdjustPercent = 10;
  static const List<int> historyCyclesOptions = [1, 3, 6];
  static const List<int> adjustPercentOptions = [5, 10, 15, 20];

  /// Nulo: a casa ainda não escolheu. O planejador abate a sobra das cotas na
  /// divisão por despesa, e o fechamento usa a sobra só para cobrir o excedente
  /// do valor fixo (como antes desta configuração existir).
  final OpeningBalanceRule? openingBalanceRule;

  /// Quantos ciclos anteriores entram na média das categorias variáveis.
  final int historyCycles;

  /// Modo do planejador escolhido por último na casa.
  final FundingEstimateMode plannerMode;

  /// Percentual dos modos Econômico e Com folga.
  final int adjustPercent;

  /// Valor previsto ajustado à mão por categoria.
  final Map<String, Money> categoryOverrides;

  /// Regra de cada tipo de entrada no Caixa (0092).
  final OpeningInflowRules inflowRules;

  const HouseSettings({
    this.openingBalanceRule,
    this.historyCycles = defaultHistoryCycles,
    this.plannerMode = FundingEstimateMode.historicalAverage,
    this.adjustPercent = defaultAdjustPercent,
    this.categoryOverrides = const {},
    this.inflowRules = const OpeningInflowRules(),
  });

  static String plannerModeToDb(FundingEstimateMode mode) => switch (mode) {
        FundingEstimateMode.economical => 'economical',
        FundingEstimateMode.historicalAverage => 'historical_average',
        FundingEstimateMode.comfortable => 'comfortable',
      };

  static FundingEstimateMode plannerModeFromDb(Object? value) => switch (value) {
        'economical' => FundingEstimateMode.economical,
        'comfortable' => FundingEstimateMode.comfortable,
        _ => FundingEstimateMode.historicalAverage,
      };

  factory HouseSettings.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const HouseSettings();
    final overrides = <String, Money>{};
    final rawOverrides = json['planner_category_overrides'];
    if (rawOverrides is Map) {
      for (final entry in rawOverrides.entries) {
        final cents = entry.value;
        if (cents is num && cents >= 0) overrides[entry.key.toString()] = Money(cents.toInt());
      }
    }
    final history = (json['planner_history_cycles'] as num?)?.toInt();
    final adjust = (json['planner_adjust_percent'] as num?)?.toInt();
    return HouseSettings(
      openingBalanceRule: OpeningBalanceRule.fromDb(json['opening_balance_rule']),
      historyCycles: history != null && history >= 1 && history <= 12 ? history : defaultHistoryCycles,
      plannerMode: plannerModeFromDb(json['planner_mode']),
      adjustPercent: adjust != null && adjust >= 0 && adjust <= 50 ? adjust : defaultAdjustPercent,
      categoryOverrides: overrides,
      inflowRules: OpeningInflowRules.fromJson(json['opening_inflow_rules']),
    );
  }

  /// Colunas lidas de `houses`.
  static const String columns = '$columnsBefore0092, opening_inflow_rules';

  /// Colunas da 0091, para o banco que ainda não tem a 0092.
  static const String columnsBefore0092 =
      'opening_balance_rule, planner_history_cycles, planner_mode, planner_adjust_percent, planner_category_overrides';

  static Map<String, dynamic> overridesToJson(Map<String, Money> overrides) => {
        for (final entry in overrides.entries) entry.key: entry.value.cents,
      };

  HouseSettings copyWith({
    OpeningBalanceRule? openingBalanceRule,
    bool clearOpeningBalanceRule = false,
    int? historyCycles,
    FundingEstimateMode? plannerMode,
    int? adjustPercent,
    Map<String, Money>? categoryOverrides,
    OpeningInflowRules? inflowRules,
  }) =>
      HouseSettings(
        openingBalanceRule:
            clearOpeningBalanceRule ? null : (openingBalanceRule ?? this.openingBalanceRule),
        historyCycles: historyCycles ?? this.historyCycles,
        plannerMode: plannerMode ?? this.plannerMode,
        adjustPercent: adjustPercent ?? this.adjustPercent,
        categoryOverrides: categoryOverrides ?? this.categoryOverrides,
        inflowRules: inflowRules ?? this.inflowRules,
      );

  @override
  List<Object?> get props =>
      [openingBalanceRule, historyCycles, plannerMode, adjustPercent, categoryOverrides, inflowRules];
}
