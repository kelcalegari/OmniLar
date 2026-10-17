import 'package:flutter/material.dart';

/// Consentimento para a leitura por IA (decisão 13.7 de plano_proximas_frentes.md).
///
/// Toda chamada à IA (leitura de foto ou PDF, nota pelo QR, importação e
/// Assistente) passa por [request] antes de enviar algo: sem o consentimento
/// guardado no perfil, o app pergunta uma vez; recusou, nada é enviado.
/// O app liga [isGiven], [ask] e [record] na abertura; sem isso (testes), libera.
class AiConsent {
  AiConsent._();

  static bool Function() isGiven = () => true;
  static Future<bool> Function() ask = () async => true;
  static Future<void> Function() record = () async {};

  /// Se pode enviar à IA agora (perguntando, se ainda não houve resposta).
  static Future<bool> request() async {
    if (isGiven()) return true;
    final allowed = await ask();
    if (allowed) {
      try {
        await record();
      } catch (_) {}
    }
    return allowed;
  }

  /// Pergunta padrão, mostrada sobre a tela em uso.
  static Future<bool> showDialogIn(BuildContext context) async {
    final allowed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.auto_awesome_rounded),
        title: const Text('Leitura por inteligência artificial'),
        content: const Text(
          'Para ler fotos e arquivos (notas, boletos, faturas e extratos) e para o Assistente entender o que você '
          'escreve, o app envia o conteúdo para a IA do Google (Gemini). Fotos e PDFs vão inteiros; nada é guardado '
          'depois da leitura. Enquanto o app estiver em testes, o Google pode usar o conteúdo para melhorar os '
          'serviços dele. Você pode retirar a permissão em Ajustes › Assistente IA.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Agora não')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Permitir')),
        ],
      ),
    );
    return allowed ?? false;
  }
}
