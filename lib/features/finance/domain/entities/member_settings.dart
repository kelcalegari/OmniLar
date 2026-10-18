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
