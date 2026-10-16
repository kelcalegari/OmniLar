import 'camera_release_stub.dart' if (dart.library.js_interop) 'camera_release_web.dart' as impl;

// O mobile_scanner (7.4.2) para de ler mas não encerra a câmera na web, e o
// celular segue mostrando a câmera em uso mesmo com o scanner fechado.

/// Passa a anotar toda câmera que o navegador entregar ao leitor. Chamar ao
/// abrir o scanner, antes de ligar a câmera.
void watchBrowserCamera() => impl.watchBrowserCamera();

/// Desliga de verdade as câmeras anotadas desde a última vez.
void releaseBrowserCamera() => impl.releaseBrowserCamera();
