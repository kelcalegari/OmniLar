import 'package:equatable/equatable.dart';
import 'package:intl/intl.dart';

/// Representação monetária segura usando centavos inteiros (Evita problemas de precisão de ponto flutuante).
/// Toda operação financeira no Omni Lar deve utilizar esta classe.
class Money extends Equatable implements Comparable<Money> {
  final int cents;

  const Money(this.cents);

  const Money.zero() : cents = 0;

  factory Money.fromReal(num reais) {
    return Money((reais * 100).round());
  }

  factory Money.fromCents(int cents) {
    return Money(cents);
  }

  /// Converte uma string formatada (ex: "1.250,50" ou "R$ 1.250,50" ou "1250.50") para Money.
  factory Money.parse(String text) {
    final cleanText = text
        .replaceAll('R\$', '')
        .replaceAll(' ', '')
        .trim();

    if (cleanText.isEmpty) {
      return const Money.zero();
    }

    if (cleanText.contains(',')) {
      // Formato brasileiro: 1.234,56
      final normalized = cleanText.replaceAll('.', '').replaceAll(',', '.');
      final value = double.tryParse(normalized) ?? 0.0;
      return Money.fromReal(value);
    } else {
      // Formato padrão / internacional: 1234.56 ou 1234
      final value = double.tryParse(cleanText) ?? 0.0;
      return Money.fromReal(value);
    }
  }

  double get inReais => cents / 100.0;

  bool get isZero => cents == 0;
  bool get isPositive => cents > 0;
  bool get isNegative => cents < 0;

  Money operator +(Money other) => Money(cents + other.cents);
  Money operator -(Money other) => Money(cents - other.cents);
  Money operator *(num factor) => Money((cents * factor).round());
  Money operator -() => Money(-cents);

  Money abs() => Money(cents.abs());

  /// Divide o valor em [parts] partes iguais de forma justa (sem perder centavos).
  /// Exemplo: R$ 10,00 / 3 -> [R$ 3,34, R$ 3,33, R$ 3,33]
  List<Money> splitEqually(int parts) {
    if (parts <= 0) throw ArgumentError('O número de partes deve ser maior que zero');
    final quotient = cents ~/ parts;
    final remainder = cents % parts;

    return List.generate(parts, (index) {
      final extra = index < remainder ? 1 : 0;
      return Money(quotient + extra);
    });
  }

  /// Calcula uma porcentagem (ex: 50.0 para 50%).
  Money percentage(num percent) {
    return Money(((cents * percent) / 100.0).round());
  }

  /// Formata para o padrão brasileiro: R$ 1.234,56
  String format({bool includeSymbol = true}) {
    final formatter = NumberFormat.currency(
      locale: 'pt_BR',
      symbol: includeSymbol ? 'R\$' : '',
      decimalDigits: 2,
    );
    return formatter.format(inReais).trim();
  }

  /// Atalho para formatação padrão em reais
  String get formatted => format();

  /// Formata com sinal explícito (+R$ 10,00 ou -R$ 10,00)
  String formatSigned({bool includeSymbol = true}) {
    if (cents > 0) {
      return '+${format(includeSymbol: includeSymbol)}';
    }
    return format(includeSymbol: includeSymbol);
  }

  @override
  int compareTo(Money other) => cents.compareTo(other.cents);

  bool operator <(Money other) => cents < other.cents;
  bool operator <=(Money other) => cents <= other.cents;
  bool operator >(Money other) => cents > other.cents;
  bool operator >=(Money other) => cents >= other.cents;

  @override
  List<Object?> get props => [cents];

  @override
  String toString() => format();
}
