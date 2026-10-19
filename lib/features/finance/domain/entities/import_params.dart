import 'package:equatable/equatable.dart';

/// Janelas do casamento de linhas do extrato com despesas já lançadas
/// (coluna `houses.import_matching`, 0100). Chave ausente vale o padrão, que é
/// o que a importação sempre usou.
class ImportMatching extends Equatable {
  static const int defaultDateWindowDays = 3;
  static const int defaultOtherMethodWindowDays = 2;
  static const int defaultAmountDiffersDays = 1;
  static const int defaultAmountDriftPercent = 25;
  static const int defaultMinSimilarityPercent = 50;
  static const int defaultInvoiceWindowDays = 45;

  /// Dias de diferença aceitos entre a linha e a despesa (0 a 10).
  final int dateWindowDays;

  /// O mesmo para despesa em outra forma de pagamento, que o usuário confirma
  /// (0 a [dateWindowDays]).
  final int otherMethodWindowDays;

  /// Dias aceitos quando o valor difere (gorjeta, taxa): 0 a [dateWindowDays].
  final int amountDiffersDays;

  /// Diferença de valor aceita nesse caso, em % do maior valor (0 a 100).
  final int amountDriftPercent;

  /// Semelhança mínima do nome nesse caso, em % (0 a 100).
  final int minSimilarityPercent;

  /// Distância máxima, em dias, entre um pagamento de fatura no extrato da
  /// conta e o vencimento dela (1 a 120).
  final int invoiceWindowDays;

  const ImportMatching({
    this.dateWindowDays = defaultDateWindowDays,
    this.otherMethodWindowDays = defaultOtherMethodWindowDays,
    this.amountDiffersDays = defaultAmountDiffersDays,
    this.amountDriftPercent = defaultAmountDriftPercent,
    this.minSimilarityPercent = defaultMinSimilarityPercent,
    this.invoiceWindowDays = defaultInvoiceWindowDays,
  });

  double get maxAmountDrift => amountDriftPercent / 100;
  double get minSimilarityForDrift => minSimilarityPercent / 100;

  /// Valor ausente, fora da faixa ou incoerente cai no padrão (como o banco
  /// recusaria gravar).
  factory ImportMatching.fromJson(Object? json) {
    if (json is! Map) return const ImportMatching();
    int pick(String key, int min, int max, int fallback) {
      final raw = json[key];
      if (raw is! num || raw != raw.truncate()) return fallback;
      final value = raw.toInt();
      return value >= min && value <= max ? value : fallback;
    }

    final parsed = ImportMatching(
      dateWindowDays: pick('date_window_days', 0, 10, defaultDateWindowDays),
      otherMethodWindowDays: pick('other_method_window_days', 0, 10, defaultOtherMethodWindowDays),
      amountDiffersDays: pick('amount_differs_days', 0, 10, defaultAmountDiffersDays),
      amountDriftPercent: pick('amount_drift_percent', 0, 100, defaultAmountDriftPercent),
      minSimilarityPercent: pick('min_similarity_percent', 0, 100, defaultMinSimilarityPercent),
      invoiceWindowDays: pick('invoice_window_days', 1, 120, defaultInvoiceWindowDays),
    );
    return parsed.isValid ? parsed : const ImportMatching();
  }

  /// Objeto inteiro: o banco troca o objeto todo.
  Map<String, dynamic> toJson() => {
        'date_window_days': dateWindowDays,
        'other_method_window_days': otherMethodWindowDays,
        'amount_differs_days': amountDiffersDays,
        'amount_drift_percent': amountDriftPercent,
        'min_similarity_percent': minSimilarityPercent,
        'invoice_window_days': invoiceWindowDays,
      };

  /// Mesmo teste do banco (import_matching_valid), para avisar antes de gravar.
  bool get isValid =>
      dateWindowDays >= 0 &&
      dateWindowDays <= 10 &&
      otherMethodWindowDays >= 0 &&
      otherMethodWindowDays <= dateWindowDays &&
      amountDiffersDays >= 0 &&
      amountDiffersDays <= dateWindowDays &&
      amountDriftPercent >= 0 &&
      amountDriftPercent <= 100 &&
      minSimilarityPercent >= 0 &&
      minSimilarityPercent <= 100 &&
      invoiceWindowDays >= 1 &&
      invoiceWindowDays <= 120;

  ImportMatching copyWith({
    int? dateWindowDays,
    int? otherMethodWindowDays,
    int? amountDiffersDays,
    int? amountDriftPercent,
    int? minSimilarityPercent,
    int? invoiceWindowDays,
  }) =>
      ImportMatching(
        dateWindowDays: dateWindowDays ?? this.dateWindowDays,
        otherMethodWindowDays: otherMethodWindowDays ?? this.otherMethodWindowDays,
        amountDiffersDays: amountDiffersDays ?? this.amountDiffersDays,
        amountDriftPercent: amountDriftPercent ?? this.amountDriftPercent,
        minSimilarityPercent: minSimilarityPercent ?? this.minSimilarityPercent,
        invoiceWindowDays: invoiceWindowDays ?? this.invoiceWindowDays,
      );

  @override
  List<Object?> get props => [
        dateWindowDays,
        otherMethodWindowDays,
        amountDiffersDays,
        amountDriftPercent,
        minSimilarityPercent,
        invoiceWindowDays,
      ];
}

/// Como as linhas novas importadas são divididas entre os moradores.
enum ImportSplitMode {
  /// A divisão da categoria ou, sem ela, a padrão da casa (como sempre foi).
  category('category'),

  /// Partes iguais entre os moradores.
  equal('equal'),

  /// Só quem paga.
  payer('payer');

  final String dbValue;
  const ImportSplitMode(this.dbValue);

  /// Valor desconhecido vale o de sempre.
  static ImportSplitMode fromDb(Object? value) {
    for (final mode in values) {
      if (mode.dbValue == value) return mode;
    }
    return category;
  }

  String get label => switch (this) {
        ImportSplitMode.category => 'Divisão da categoria ou da casa',
        ImportSplitMode.equal => 'Partes iguais',
        ImportSplitMode.payer => 'Só quem paga',
      };
}

/// Destino padrão das linhas novas importadas (coluna `houses.import_defaults`,
/// 0100). Campo nulo = o comportamento de sempre.
class ImportDefaults extends Equatable {
  static final _uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    caseSensitive: false,
  );

  /// Categoria das linhas sem categoria sugerida.
  final String? categoryId;
  final ImportSplitMode splitMode;

  /// Cartão ou conta que a tela de importação abre selecionado.
  final String? paymentMethodId;

  const ImportDefaults({
    this.categoryId,
    this.splitMode = ImportSplitMode.category,
    this.paymentMethodId,
  });

  factory ImportDefaults.fromJson(Object? json) {
    if (json is! Map) return const ImportDefaults();
    String? id(String key) {
      final raw = json[key];
      return raw is String && _uuid.hasMatch(raw) ? raw : null;
    }

    return ImportDefaults(
      categoryId: id('category_id'),
      splitMode: ImportSplitMode.fromDb(json['split_mode']),
      paymentMethodId: id('payment_method_id'),
    );
  }

  /// Objeto inteiro: o banco troca o objeto todo. Só vão as chaves escolhidas.
  Map<String, dynamic> toJson() => {
        'category_id': ?categoryId,
        if (splitMode != ImportSplitMode.category) 'split_mode': splitMode.dbValue,
        'payment_method_id': ?paymentMethodId,
      };

  bool get isEmpty => categoryId == null && splitMode == ImportSplitMode.category && paymentMethodId == null;

  /// Ids precisam ser uuid (o banco recusa o resto).
  bool get isValid =>
      (categoryId == null || _uuid.hasMatch(categoryId!)) &&
      (paymentMethodId == null || _uuid.hasMatch(paymentMethodId!));

  ImportDefaults copyWith({
    String? categoryId,
    bool clearCategory = false,
    ImportSplitMode? splitMode,
    String? paymentMethodId,
    bool clearPaymentMethod = false,
  }) =>
      ImportDefaults(
        categoryId: clearCategory ? null : (categoryId ?? this.categoryId),
        splitMode: splitMode ?? this.splitMode,
        paymentMethodId: clearPaymentMethod ? null : (paymentMethodId ?? this.paymentMethodId),
      );

  @override
  List<Object?> get props => [categoryId, splitMode, paymentMethodId];
}
