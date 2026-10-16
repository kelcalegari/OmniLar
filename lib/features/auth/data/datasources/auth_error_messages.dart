import 'package:supabase_flutter/supabase_flutter.dart';

/// Traduz os erros do Supabase Auth (que chegam em inglês) para o usuário.
/// Lista dos códigos: https://supabase.com/docs/guides/auth/debugging/error-codes
String authErrorMessage(AuthException e) {
  switch (e.code) {
    case 'invalid_credentials':
      return 'E-mail ou senha inválidos.';
    case 'email_not_confirmed':
      return 'Confirme seu e-mail para entrar.';
    case 'user_already_exists':
    case 'email_exists':
      return 'Este e-mail já tem uma conta. Entre com sua senha.';
    case 'weak_password':
      return 'Senha fraca: use pelo menos 6 caracteres, misturando letras e números.';
    case 'same_password':
      return 'A nova senha precisa ser diferente da atual.';
    case 'email_address_invalid':
      return 'E-mail inválido.';
    case 'signup_disabled':
    case 'email_provider_disabled':
      return 'Novos cadastros estão desativados no momento.';
    case 'otp_expired':
      return 'Código inválido ou expirado. Peça um novo.';
    case 'over_email_send_rate_limit':
      return 'Muitos e-mails enviados. Aguarde alguns minutos e tente de novo.';
    case 'over_request_rate_limit':
      return 'Muitas tentativas. Aguarde alguns minutos e tente de novo.';
    case 'user_banned':
      return 'Esta conta está bloqueada.';
  }
  final message = e.message.toLowerCase();
  if (message.contains('invalid login credentials')) {
    return 'E-mail ou senha inválidos.';
  }
  if (message.contains('token has expired') || message.contains('invalid')) {
    if (message.contains('token') || message.contains('otp')) {
      return 'Código inválido ou expirado. Peça um novo.';
    }
  }
  if (message.contains('network') || message.contains('socket')) {
    return 'Sem conexão com o servidor. Confira sua internet.';
  }
  return e.message;
}
