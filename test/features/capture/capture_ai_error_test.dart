import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/features/capture/domain/services/capture_service.dart';

void main() {
  group('CaptureAiError.fromServer', () {
    test('429 por minuto traz a espera sugerida pelo servidor', () {
      final e = CaptureAiError.fromServer(429, {
        'scope': 'minute',
        'retry_after_s': 35,
        'error': 'Muitos pedidos neste minuto.',
      })!;
      expect(e.scope, CaptureAiScope.minute);
      expect(e.retryAfterSeconds, 35);
      expect(e.canRetry, isTrue);
    });

    test('429 por dia não promete espera', () {
      final e = CaptureAiError.fromServer(429, {
        'scope': 'day',
        'retry_after_s': 35,
        'error': 'Cota diária atingida.',
      })!;
      expect(e.scope, CaptureAiScope.day);
      expect(e.retryAfterSeconds, isNull);
      expect(e.canRetry, isFalse);
    });

    test('503 sem escopo vira instabilidade do servidor com espera padrão', () {
      final e = CaptureAiError.fromServer(503, null)!;
      expect(e.scope, CaptureAiScope.server);
      expect(e.retryAfterSeconds, 30);
    });

    test('erro que não é limite nem instabilidade segue o fluxo antigo', () {
      expect(CaptureAiError.fromServer(400, {'error': 'x'}), isNull);
      expect(CaptureAiError.fromServer(500, {'error': 'x'}), isNull);
    });
  });
}
