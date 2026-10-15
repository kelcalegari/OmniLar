import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Mensagem genérica quando a gravação falha e a tela não tem detalhe melhor.
const kSaveFailedMessage = 'Não foi possível salvar. Confira a conexão e tente de novo.';

/// Mostra o resultado de uma gravação já concluída: [success] quando [ok],
/// senão [failure] (ou a mensagem genérica) em vermelho.
///
/// Use depois de esperar a gravação: a mensagem de sucesso só pode aparecer
/// quando o banco confirmou.
void showSaveFeedback(
  ScaffoldMessengerState messenger, {
  required bool ok,
  required String success,
  String? failure,
}) {
  messenger.showSnackBar(
    SnackBar(
      backgroundColor: ok ? null : AppColors.debtRed,
      content: Text(ok ? success : (failure ?? kSaveFailedMessage)),
    ),
  );
}
