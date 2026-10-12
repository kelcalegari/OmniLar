/**
 * Utilitários de sanitização e mascaramento de dados sensíveis para conformidade com privacidade.
 * Garante que CPFs, cartões e contas não sejam trafegados para modelos externos sem ofuscação.
 */

export function maskCpf(text: string): string {
  // Padrão: 000.000.000-00 ou 11 dígitos seguidos
  return text.replace(/\b(\d{3})\.?(\d{3})\.?(\d{3})-?(\d{2})\b/g, '$1.***.***-$4');
}

export function maskCreditCard(text: string): string {
  // 13 a 19 dígitos (Visa, Master, Elo, Amex)
  return text.replace(/\b(?:\d{4}[ -]?){3}\d{4}\b/g, '****-****-****-****');
}

export function maskSensitiveData(text: string): string {
  if (!text) return '';
  return maskCreditCard(maskCpf(text));
}
