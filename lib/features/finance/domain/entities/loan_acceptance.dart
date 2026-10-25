import 'package:equatable/equatable.dart';

/// Quando o empréstimo lançado por outra pessoa espera o aceite do devedor
/// (coluna `houses.loan_acceptance`, 0116), por origem. Por padrão todos
/// esperam, como na 0082.
class LoanAcceptance extends Equatable {
  /// Lançado à mão entre moradores.
  final bool manual;

  /// Criado pela importação da fatura (inclusive no cartão da Casa).
  final bool import;

  /// Do Caixa da Casa, lançado à mão.
  final bool house;

  const LoanAcceptance({this.manual = true, this.import = true, this.house = true});

  factory LoanAcceptance.fromJson(Object? json) {
    if (json is! Map) return const LoanAcceptance();
    bool flag(String key) => json[key] is bool ? json[key] as bool : true;
    return LoanAcceptance(manual: flag('manual'), import: flag('import'), house: flag('house'));
  }

  /// Objeto inteiro: o banco troca o objeto todo.
  Map<String, dynamic> toJson() => {'manual': manual, 'import': import, 'house': house};

  LoanAcceptance copyWith({bool? manual, bool? import, bool? house}) => LoanAcceptance(
        manual: manual ?? this.manual,
        import: import ?? this.import,
        house: house ?? this.house,
      );

  @override
  List<Object?> get props => [manual, import, house];
}
