import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Observador global de Cubits e Blocs para capturar exceções não tratadas
/// e encaminhá-las ao Sentry com contexto do estado atual.
class OmniBlocObserver extends BlocObserver {
  @override
  void onError(BlocBase bloc, Object error, StackTrace stackTrace) {
    super.onError(bloc, error, stackTrace);

    Sentry.captureException(
      error,
      stackTrace: stackTrace,
      withScope: (scope) {
        scope.setTag('bloc', bloc.runtimeType.toString());
        scope.setContexts('bloc_state', {
          'state': bloc.state.toString(),
        });
      },
    );
  }
}
