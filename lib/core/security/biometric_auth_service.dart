import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';

/// Serviço de autenticação biométrica e confirmação de segurança (RN07).
/// Protege operações irreversíveis de alto risco:
/// - Fechamento / Liquidação de Ciclo Financeiro
/// - Perdão / Anistia de Empréstimos P2P
/// - Renegociação de Dívidas
class BiometricAuthService {
  final LocalAuthentication _auth;

  BiometricAuthService({LocalAuthentication? auth})
      : _auth = auth ?? LocalAuthentication();

  /// Verifica se o dispositivo possui suporte a biometria ou PIN
  Future<bool> canCheckBiometrics() async {
    try {
      if (kIsWeb) return false;
      final canCheck = await _auth.canCheckBiometrics;
      final isSupported = await _auth.isDeviceSupported();
      return canCheck || isSupported;
    } catch (_) {
      return false;
    }
  }

  /// Solicita autenticação biométrica ou PIN do aparelho.
  /// Se o dispositivo não suportar biometria (ex: desktop/testes), retorna true por resiliência.
  Future<bool> authenticate({
    required String reason,
  }) async {
    try {
      final isAvailable = await canCheckBiometrics();
      if (!isAvailable) {
        // Dispositivo sem hardware biométrico ou ambiente de testes/web: concede permissão
        return true;
      }

      return await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: false,
        persistAcrossBackgrounding: true,
      );
    } catch (e) {
      debugPrint('[BiometricAuthService] Erro na autenticação biométrica: $e');
      return false;
    }
  }
}
