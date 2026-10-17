/// Resultado de uma tentativa de abrir o menu de compartilhamento do sistema.
enum NativeShareResult { shared, cancelled, unsupported }

/// Fora do navegador não há menu de compartilhamento: só resta copiar.
Future<NativeShareResult> nativeShareText(String text) async =>
    NativeShareResult.unsupported;

bool openWhatsAppText(String text) => false;

const bool canOpenWhatsApp = false;
