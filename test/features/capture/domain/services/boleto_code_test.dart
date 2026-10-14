import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/features/capture/domain/services/boleto_code.dart';

/// Monta um código de barras de boleto bancário com o dígito geral certo.
String _bankBarcode({String factor = '1368', String value = '0000021540'}) {
  const free = '0000000123456789012345678';
  final withoutDigit = '0019$factor$value$free';
  final digit = BoletoCodeReader.bankGeneralDigit(withoutDigit);
  return '${withoutDigit.substring(0, 4)}$digit${withoutDigit.substring(4)}';
}

/// Monta um código de barras de conta de consumo (energia) com o dígito geral certo.
String _utilityBarcode({String valueId = '6', String value = '00000015090'}) {
  final withoutDigit = '83$valueId${value}00482'.padRight(43, '0');
  final digit = valueId == '6' || valueId == '7'
      ? BoletoCodeReader.mod10(withoutDigit)
      : BoletoCodeReader.utilityMod11(withoutDigit);
  return '${withoutDigit.substring(0, 3)}$digit${withoutDigit.substring(3)}';
}

String _swapDigit(String text, int index) {
  final digit = int.parse(text[index]);
  return text.substring(0, index) + ((digit + 1) % 10).toString() + text.substring(index + 1);
}

void main() {
  group('Boleto bancário', () {
    test('o código de barras da câmera vira valor, vencimento e linha digitável', () {
      final code = BoletoCodeReader.read(_bankBarcode());

      expect(code.kind, BoletoKind.bank);
      expect(code.amount!.cents, 21540);
      // Fator 1368 no ciclo novo da FEBRABAN: 25/02/2026
      expect(code.dueDate, DateTime(2026, 2, 25));
      expect(BoletoCodeReader.digitsOf(code.digitableLine), hasLength(47));
    });

    test('a linha digitável lida de volta dá o mesmo código de barras', () {
      final barcode = _bankBarcode();
      final line = BoletoCodeReader.read(barcode).digitableLine;
      final again = BoletoCodeReader.read(line);

      expect(again.barcode, barcode);
      expect(again.amount!.cents, 21540);
    });

    test('número errado na linha digitável ou no código é recusado', () {
      final line = BoletoCodeReader.digitsOf(BoletoCodeReader.read(_bankBarcode()).digitableLine);
      expect(() => BoletoCodeReader.read(_swapDigit(line, 3)), throwsA(isA<BoletoCodeError>()));
      expect(() => BoletoCodeReader.read(_swapDigit(_bankBarcode(), 10)), throwsA(isA<BoletoCodeError>()));
    });

    test('fator zero é boleto sem vencimento', () {
      expect(BoletoCodeReader.read(_bankBarcode(factor: '0000')).dueDate, isNull);
    });
  });

  group('Conta de consumo', () {
    test('código de 44 e linha de 48 dígitos: valor e tipo da conta, sem vencimento', () {
      final barcode = _utilityBarcode();
      final code = BoletoCodeReader.read(barcode);

      expect(code.kind, BoletoKind.utility);
      expect(code.amount!.cents, 15090);
      expect(code.dueDate, isNull);
      expect(code.segment, BoletoSegment.energyGas);
      expect(code.suggestedTitle, 'Conta de energia ou gás');

      final line = BoletoCodeReader.digitsOf(code.digitableLine);
      expect(line, hasLength(48));
      expect(BoletoCodeReader.read(line).barcode, barcode);
    });

    test('código com módulo 11 também confere', () {
      final code = BoletoCodeReader.read(_utilityBarcode(valueId: '8'));
      expect(code.amount!.cents, 15090);
      final line = BoletoCodeReader.digitsOf(code.digitableLine);
      expect(() => BoletoCodeReader.read(_swapDigit(line, 5)), throwsA(isA<BoletoCodeError>()));
    });

    test('valor de referência (7 e 9) não é tomado como valor a pagar', () {
      expect(BoletoCodeReader.read(_utilityBarcode(valueId: '7')).amount, isNull);
    });
  });

  test('tamanho que não é de boleto explica o que esperava', () {
    expect(
      () => BoletoCodeReader.read('123456'),
      throwsA(isA<BoletoCodeError>().having((e) => e.message, 'message', contains('6 dígitos'))),
    );
  });
}
