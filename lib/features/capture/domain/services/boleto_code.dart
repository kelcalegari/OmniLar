import '../../../../core/domain/value_objects/money.dart';
import 'boleto_parser.dart';

/// Tipo de boleto pelo padrão FEBRABAN.
enum BoletoKind {
  /// Boleto de cobrança bancária (linha de 47 dígitos, código de barras de 44).
  bank,

  /// Conta de consumo e tributo (arrecadação: linha de 48 dígitos que começa
  /// com 8, código de barras de 44).
  utility,
}

/// Segmento da conta de arrecadação (2º dígito do código).
enum BoletoSegment { cityHall, sanitation, energyGas, telecom, government, carnets, trafficFines, bank, other }

/// O que dá para tirar só do código de um boleto, sem IA.
class BoletoCode {
  final BoletoKind kind;

  /// Os 44 dígitos do código de barras.
  final String barcode;

  /// Linha digitável formatada, para copiar e pagar no app do banco.
  final String digitableLine;

  /// Valor, quando o código traz (conta de consumo pode trazer só uma referência).
  final Money? amount;

  /// Vencimento: só o boleto bancário traz no código.
  final DateTime? dueDate;
  final BoletoSegment? segment;

  const BoletoCode({
    required this.kind,
    required this.barcode,
    required this.digitableLine,
    this.amount,
    this.dueDate,
    this.segment,
  });

  /// Categoria sugerida pelo segmento da conta de consumo (palavras para achar
  /// a categoria da casa).
  List<String> get categoryHints => switch (segment) {
        BoletoSegment.sanitation || BoletoSegment.energyGas || BoletoSegment.telecom => const ['conta', 'luz', 'água'],
        BoletoSegment.cityHall || BoletoSegment.government => const ['imposto', 'taxa', 'moradia'],
        _ => const [],
      };

  String get suggestedTitle => switch (segment) {
        BoletoSegment.energyGas => 'Conta de energia ou gás',
        BoletoSegment.sanitation => 'Conta de água',
        BoletoSegment.telecom => 'Conta de telefone ou internet',
        BoletoSegment.cityHall => 'Tributo municipal',
        BoletoSegment.government => 'Tributo',
        BoletoSegment.trafficFines => 'Multa de trânsito',
        _ => 'Boleto',
      };
}

class BoletoCodeError implements Exception {
  final String message;
  const BoletoCodeError(this.message);

  @override
  String toString() => message;
}

/// Lê código de barras (44 dígitos) e linhas digitáveis (47 e 48 dígitos),
/// conferindo os dígitos verificadores para recusar erro de digitação.
class BoletoCodeReader {
  const BoletoCodeReader._();

  static String digitsOf(String input) => input.replaceAll(RegExp(r'[^0-9]'), '');

  /// Módulo 10 (pesos 2, 1 da direita para a esquerda, somando os algarismos).
  static int mod10(String digits) {
    var sum = 0;
    var weight = 2;
    for (var i = digits.length - 1; i >= 0; i--) {
      var product = int.parse(digits[i]) * weight;
      if (product > 9) product = product ~/ 10 + product % 10;
      sum += product;
      weight = weight == 2 ? 1 : 2;
    }
    return (10 - sum % 10) % 10;
  }

  static int _mod11Sum(String digits) {
    var sum = 0;
    var weight = 2;
    for (var i = digits.length - 1; i >= 0; i--) {
      sum += int.parse(digits[i]) * weight;
      weight = weight == 9 ? 2 : weight + 1;
    }
    return sum;
  }

  /// Dígito geral do boleto bancário (módulo 11; 0, 10 e 11 viram 1).
  static int bankGeneralDigit(String barcodeWithoutDigit) {
    final dv = 11 - _mod11Sum(barcodeWithoutDigit) % 11;
    return dv == 0 || dv == 10 || dv == 11 ? 1 : dv;
  }

  /// Módulo 11 da arrecadação (resto 0 ou 1 vira 0; resto 10 vira 1).
  static int utilityMod11(String digits) {
    final rest = _mod11Sum(digits) % 11;
    if (rest == 0 || rest == 1) return 0;
    if (rest == 10) return 1;
    return 11 - rest;
  }

  static int _utilityDigit(String digits, String valueId) =>
      valueId == '6' || valueId == '7' ? mod10(digits) : utilityMod11(digits);

  /// Lê o que o usuário digitou, colou ou a câmera leu.
  static BoletoCode read(String input) {
    final digits = digitsOf(input);
    switch (digits.length) {
      case 44:
        return digits.startsWith('8') ? _utilityFromBarcode(digits) : _bankFromBarcode(digits);
      case 47:
        return _bankFromLine(digits);
      case 48:
        if (!digits.startsWith('8')) {
          throw const BoletoCodeError('Linha de 48 dígitos precisa começar com 8 (conta de consumo).');
        }
        return _utilityFromLine(digits);
      default:
        throw BoletoCodeError(
          'O código tem ${digits.length} dígitos. Boleto tem 47 (linha digitável), 48 (conta de consumo) ou 44 (código de barras).',
        );
    }
  }

  // --- Boleto bancário ---

  static BoletoCode _bankFromLine(String line) {
    final fields = [line.substring(0, 10), line.substring(10, 21), line.substring(21, 32)];
    for (var i = 0; i < fields.length; i++) {
      final field = fields[i];
      if (mod10(field.substring(0, field.length - 1)) != int.parse(field[field.length - 1])) {
        throw BoletoCodeError('O campo ${i + 1} da linha digitável tem um número errado. Confira a digitação.');
      }
    }
    final barcode = line.substring(0, 4) +
        line[32] +
        line.substring(33, 47) +
        line.substring(4, 9) +
        line.substring(10, 20) +
        line.substring(21, 31);
    return _bankFromBarcode(barcode);
  }

  static BoletoCode _bankFromBarcode(String barcode) {
    final digit = int.parse(barcode[4]);
    if (bankGeneralDigit(barcode.substring(0, 4) + barcode.substring(5)) != digit) {
      throw const BoletoCodeError('O código do boleto não confere. Confira a digitação ou escaneie de novo.');
    }
    final factor = int.parse(barcode.substring(5, 9));
    final cents = int.parse(barcode.substring(9, 19));

    final field1 = barcode.substring(0, 4) + barcode.substring(19, 24);
    final field2 = barcode.substring(24, 34);
    final field3 = barcode.substring(34, 44);
    String withDigit(String field) => '$field${mod10(field)}';
    final f1 = withDigit(field1);
    final f2 = withDigit(field2);
    final f3 = withDigit(field3);
    final line = '${f1.substring(0, 5)}.${f1.substring(5)} '
        '${f2.substring(0, 5)}.${f2.substring(5)} '
        '${f3.substring(0, 5)}.${f3.substring(5)} '
        '${barcode[4]} ${barcode.substring(5, 19)}';

    return BoletoCode(
      kind: BoletoKind.bank,
      barcode: barcode,
      digitableLine: line,
      amount: cents > 0 ? Money(cents) : null,
      // Fator zero: boleto sem vencimento
      dueDate: factor > 0 ? BoletoParser.calculateDueDateFromFactor(factor) : null,
    );
  }

  // --- Conta de consumo e tributo (arrecadação) ---

  static BoletoCode _utilityFromLine(String line) {
    final valueId = line[2];
    final blocks = [for (var i = 0; i < 4; i++) line.substring(i * 12, i * 12 + 12)];
    for (var i = 0; i < blocks.length; i++) {
      final block = blocks[i];
      if (_utilityDigit(block.substring(0, 11), valueId) != int.parse(block[11])) {
        throw BoletoCodeError('O bloco ${i + 1} da linha digitável tem um número errado. Confira a digitação.');
      }
    }
    return _utilityFromBarcode(blocks.map((b) => b.substring(0, 11)).join());
  }

  static BoletoCode _utilityFromBarcode(String barcode) {
    final valueId = barcode[2];
    if (!'6789'.contains(valueId)) {
      throw const BoletoCodeError('Este código de conta de consumo não é reconhecido.');
    }
    final general = _utilityDigit(barcode.substring(0, 3) + barcode.substring(4), valueId);
    if (general != int.parse(barcode[3])) {
      throw const BoletoCodeError('O código da conta não confere. Confira a digitação ou escaneie de novo.');
    }

    final blocks = [for (var i = 0; i < 4; i++) barcode.substring(i * 11, i * 11 + 11)];
    final line = blocks.map((b) => '$b-${_utilityDigit(b, valueId)}').join(' ');
    // 6 e 8: o campo de valor é o valor a pagar; 7 e 9: é só uma referência
    final cents = int.parse(barcode.substring(4, 15));
    final segment = switch (barcode[1]) {
      '1' => BoletoSegment.cityHall,
      '2' => BoletoSegment.sanitation,
      '3' => BoletoSegment.energyGas,
      '4' => BoletoSegment.telecom,
      '5' => BoletoSegment.government,
      '6' => BoletoSegment.carnets,
      '7' => BoletoSegment.trafficFines,
      '9' => BoletoSegment.bank,
      _ => BoletoSegment.other,
    };

    return BoletoCode(
      kind: BoletoKind.utility,
      barcode: barcode,
      digitableLine: line,
      amount: (valueId == '6' || valueId == '8') && cents > 0 ? Money(cents) : null,
      segment: segment,
    );
  }
}
