import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/features/capture/domain/services/capture_service.dart';

void main() {
  group('CaptureService.absorbDiscounts', () {
    test('abate o desconto do boleto de gás mantendo o total', () {
      final lines = CaptureService.absorbDiscounts([
        ('GLP Industrial', 1538),
        ('Serviço de leitura', 350),
        ('Desconto por cadastro atualizado', -154),
      ]);
      expect(lines, [('GLP Industrial', 1413), ('Serviço de leitura', 321)]);
      expect(lines.fold<int>(0, (s, l) => s + l.$2), 1734);
    });

    test('sem desconto só tira itens zerados', () {
      expect(CaptureService.absorbDiscounts([('A', 100), ('B', 0)]), [('A', 100)]);
    });

    test('desconto que engole os itens volta vazio', () {
      expect(CaptureService.absorbDiscounts([('A', 100), ('Desconto', -100)]), isEmpty);
    });
  });
}
