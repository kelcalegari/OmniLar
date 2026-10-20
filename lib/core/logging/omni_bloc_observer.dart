import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Observador global de Cubits e Blocs para capturar exceções não tratadas
/// e transições de estado para erro, encaminhando-as ao Sentry com contexto do estado atual.
class OmniBlocObserver extends BlocObserver {
  BlocBase? _lastErrorBloc;
  DateTime? _lastErrorTime;

  @override
  void onError(BlocBase bloc, Object error, StackTrace stackTrace) {
    super.onError(bloc, error, stackTrace);
    _lastErrorBloc = bloc;
    _lastErrorTime = DateTime.now();

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

  @override
  void onChange(BlocBase bloc, Change change) {
    super.onChange(bloc, change);

    final next = change.nextState;
    final typeName = next.runtimeType.toString();
    final isErrorState = typeName.endsWith('Error') ||
        typeName.endsWith('Failure') ||
        typeName.endsWith('Exception');

    if (!isErrorState) return;

    // Se já foi reportado via onError nos últimos 1.5s pelo mesmo bloc,
    // não duplica o alerta no Sentry, apenas adiciona breadcrumb.
    final now = DateTime.now();
    final recentlyReported = _lastErrorBloc == bloc &&
        _lastErrorTime != null &&
        now.difference(_lastErrorTime!).inMilliseconds < 1500;

    if (recentlyReported) {
      Sentry.addBreadcrumb(
        Breadcrumb(
          category: 'bloc.state',
          message: '${bloc.runtimeType} mudou para estado de erro: $next',
          level: SentryLevel.info,
        ),
      );
      return;
    }

    // Se o cubit tratou a exceção com try/catch mas emitiu um estado de erro sem chamar addError(),
    // capturamos aqui para garantir que o Sentry registre no dashboard de incidentes!
    dynamic dynState = next;
    String? message;
    try {
      message = dynState.message as String?;
    } catch (_) {}

    final alertMessage = message != null && message.isNotEmpty
        ? '[${bloc.runtimeType}] $message'
        : '[${bloc.runtimeType}] Transição para estado de erro: $next';

    Sentry.captureMessage(
      alertMessage,
      level: SentryLevel.error,
      withScope: (scope) {
        scope.setTag('bloc', bloc.runtimeType.toString());
        scope.setTag('state_type', typeName);
        scope.setContexts('bloc_transition', {
          'previous_state': change.currentState.toString(),
          'next_state': change.nextState.toString(),
          if (message != null) 'error_message': message,
        });
      },
    );
  }
}
